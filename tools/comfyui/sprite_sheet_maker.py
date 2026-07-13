"""
스프라이트시트 메이커 — Civitai "Sprite Sheet Maker" (model #448101, v H42) 재구현.

원본 워크플로우 핵심 기술:
  - IPAdapter (캐릭터 일관성 유지)
  - AnimateDiff + AnimateLCM (모션 생성 + 고속 샘플링)
  - LCM 스케줄러 (8~12스텝 생성)
  - Rembg (배경 제거)
  - Create Grid Image from Batch (프레임 → 시트)

주의: AnimateLCM_sd15_t2v_lora.safetensors는 temporal key가 없는 일반 LCM 가속 LoRA이므로
      ADE_AnimateDiffLoRALoader(motion_lora)가 아닌 일반 LoraLoader로 UNet에 적용해야 함.

DOTS 환경 최적화 (GTX 1060 6GB, SD 1.5):
  - idle 8프레임 × 128px 스펙
  - 단일 패스 (원본은 2패스, idle 모션은 1패스로 충분)
  - ControlNet OpenPose는 옵션 (idle은 포즈 변화 최소)

입력: 캐릭터 이미지 1장 (정면/측면 스프라이트)
출력:
  1. 개별 프레임 8장 (128×128, 투명 배경 PNG — PIL 후처리로 알pha 적용)
  2. 스프라이트시트 1장 (그리드, 투명 배경)
  3. GIF 미리보기 (10fps 루핑)

투명 배경 처리:
  ComfyUI의 SaveImage 노드는 RGB PNG만 저장하므로 Rembg의 알파 채널이 검은색으로 변함.
  따라서 노드 61(Rembg 후)의 배경을 흰색으로 렌더링하고, PIL 후처리로 흰색→투명 변환.
  comfy_gem.py의 flood-fill 알고리즘을 적용하여 심볼 내부 하이라이트는 보존.

사용법:
  # 기본 (서버 입력 이미지 경로 지정)
  python3 sprite_sheet_maker.py --input my_character.png --name knight_idle

  # ControlNet OpenPose 사용 (걷기 등 포즈 변화 클 때)
  python3 sprite_sheet_maker.py --input walk_pose.png --name knight_walk --controlnet

  # 프레임 수 / 해상도 조정
  python3 sprite_sheet_maker.py --input char.png --name mage_idle --frames 12 --size 96

워크플로우 노드 구조 (노드 ID 체계):
  1x: 로더 (체크포인트, AnimateDiff, IPAdapter)
  2x: 입력 이미지 처리 (LoadImage, PrepImageForClipVision)
  3x: 컨디셔닝 (CLIP 텍스트 인코딩 + ControlNet)
  4x: 생성 (EmptyLatent batch, KSampler LCM, VAEDecode)
  5x: 후처리 (Rembg, ImageScale, Grid, GIF)
  6x: PIL 투명화 후처리 (흰 배경 → 알파)
"""
import json
import urllib.request
import urllib.parse
import time
import sys
import argparse
import os
import subprocess
from collections import deque

SERVER = "http://localhost:8188"
OUTPUT_DIR = "/opt/ComfyUI/output"


def make_transparent(solid_path, out_path, bg_threshold=235, feather=2):
    """배경(순백) 영역만 투명화 — flood-fill 기반 (comfy_gem.py 알고리즘 재사용).

    핵심: 모서리에서 준백 픽셀을 따라 BFS 탐색하여 '외부 배경 영역'만 식별.
    캐릭터 내부의 밝은 하이라이트는 모서리와 연결되지 않으므로 불투명하게 유지.

    bg_threshold: R,G,B 모두 이值 이상이면 배경색 후보 (0~255).
    feather: 경계 안티앨리어싱 페더링 폭 (픽셀).
    """
    try:
        from PIL import Image
        import numpy as np
    except ImportError:
        return None

    img = Image.open(solid_path).convert("RGB")
    arr = np.array(img).astype(np.float32)
    h, w = arr.shape[:2]
    is_bg_color = np.all(arr >= bg_threshold, axis=2)  # 배경색(준백) 픽셀 마스크

    # BFS flood-fill: 4 모서리에서 시드 시작, is_bg_color 픽셀만 탐색
    visited = np.zeros((h, w), dtype=bool)
    bg_mask = np.zeros((h, w), dtype=bool)
    queue = deque()
    for x in range(w):
        for y in [0, h - 1]:
            if is_bg_color[y, x] and not visited[y, x]:
                queue.append((y, x)); visited[y, x] = True; bg_mask[y, x] = True
    for y in range(h):
        for x in [0, w - 1]:
            if is_bg_color[y, x] and not visited[y, x]:
                queue.append((y, x)); visited[y, x] = True; bg_mask[y, x] = True
    while queue:
        y, x = queue.popleft()
        for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and is_bg_color[ny, nx]:
                visited[ny, nx] = True; bg_mask[ny, nx] = True
                queue.append((ny, nx))

    # 알파: 배경=0, 캐릭터=255. 페더링으로 경계 안티앨리어싱.
    alpha = np.where(bg_mask, 0.0, 255.0)
    if feather > 0:
        cur = bg_mask.copy()
        for i in range(feather):
            dil = cur.copy()
            dil[1:, :] |= cur[:-1, :]; dil[:-1, :] |= cur[1:, :]
            dil[:, 1:] |= cur[:, :-1]; dil[:, :-1] |= cur[:, 1:]
            edge = dil & ~cur
            ys, xs = np.where(edge)
            if len(ys) > 0:
                brightness = arr[ys, xs].min(axis=1)
                ratio = np.clip((255.0 - brightness) / max(1.0, 255.0 - bg_threshold), 0, 1)
                t = (i + 1) / (feather + 1)
                alpha[ys, xs] = 255.0 * t * ratio
            cur = dil

    rgba = np.dstack([arr, alpha]).astype(np.uint8)
    result = Image.fromarray(rgba, "RGBA")
    result.save(out_path)
    return result.size


def postprocess_transparent(result, name, bg_threshold=235, feather=2):
    """생성된 프레임/시트를 다운로드하여 투명 PNG로 변환.

    ComfyUI SaveImage는 RGB만 저장하므로, 흰 배경 PNG를 받아서 flood-fill 투명화.
    원본(흰 배경)은 _solid 접미사로 보존, 투명 버전은 기본명으로 저장.

    반환: 투명화된 파일 경로 목록
    """
    transparent_files = []
    for img_info in result.get("images", []):
        fname = img_info["filename"]
        subfolder = img_info.get("subfolder", "")
        # ComfyUI 출력 파일 경로
        src_path = os.path.join(OUTPUT_DIR, subfolder, fname) if subfolder else os.path.join(OUTPUT_DIR, fname)
        if not os.path.exists(src_path):
            continue

        # 투명화: {name}_frame_00001_.png → {name}_frame_00001_transparent.png
        base, ext = os.path.splitext(fname)
        out_path = os.path.join(OUTPUT_DIR, base + "_transparent" + ext)

        size = make_transparent(src_path, out_path, bg_threshold=bg_threshold, feather=feather)
        if size:
            transparent_files.append(out_path)
            print("    🔄 투명화: %s → %s" % (fname, os.path.basename(out_path)))
        else:
            print("    ⚠️ PIL 없음 — %s 투명화 생략" % fname)
    return transparent_files

# === 기본 설정값 ===
# 체크포인트: SD1.5 계열 필요. 원본은 GeekyGhost_LCM_v2 (Civitai 인증 필요).
# 대안: DreamShaper_8 (SD1.5, LCM LoRA로 고속 샘플링 흉내) 또는 Mistoon_Pearl (SD1.5 툰).
# GeekyGhost LCM을 받았으면 아래 값을 교체 (빠른 8스텝 생성 가능).
CHECKPOINT = "DreamShaper_8_pruned.safetensors"    # SD1.5 (LCM LoRA로 보완)
ANIMATEDIFF_MODEL = "AnimateLCM_sd15_t2v.ckpt"     # AnimateDiff 모션 모듈
ANIMATEDIFF_LORA = "AnimateLCM_sd15_t2v_lora.safetensors"  # LCM 가속 LoRA
IPADAPTER_PRESET = "PLUS (high strength)"          # IPAdapter 프리셋
REMBG_MODEL = "isnet-anime"                        # 배경 제거 (애니메이션 특화)
CONTROLNET_OPENPOSE = "controlnet11Models_openpose.safetensors"

# idle 모션 기본 프롬프트 (원본 H42에서 캡틴 마블 러닝 → 범용 idle로 변경)
DEFAULT_POSITIVE = (
    "pixel art, sprite, single character, chibi, cute, "
    "idle breathing animation, subtle motion, standing pose, "
    "centered, full body, vibrant colors, clean outline, "
    "white background, game asset, 16bit retro RPG"
)
DEFAULT_NEGATIVE = (
    "nsfw, watermark, text, signature, blurry, "
    "multiple characters, busy background, landscape, scenery, "
    "deformed, extra limbs, bad anatomy, cropped, out of frame, "
    "fast motion, action pose, running, jumping"
)


def build_workflow(input_image, name, frames, out_size, gen_size,
                   seed, steps, ip_weight, use_controlnet, cn_strength,
                   positive, negative):
    """스프라이트시트 생성 API JSON 빌드.

    인자:
      input_image: ComfyUI 입력 폴더 기준 이미지 파일명 (예: "knight_base.png")
      name: 출력 파일명 접두사
      frames: 프레임 수 (batch_size)
      out_size: 최종 출력 해상도 (정사각형)
      gen_size: SD 생성 해상도 (512 권장, SD1.5 최적)
      seed: 재현성 시드
      steps: LCM 스텝 수 (6~10 권장)
      ip_weight: IPAdapter 가중치 (0.6~1.0, 캐릭터 일관성 강도)
      use_controlnet: ControlNet OpenPose 사용 여부
      cn_strength: ControlNet 강도 (1.0~1.5)
      positive: 긍정 프롬프트
      negative: 부정 프롬프트
    """
    api = {
        # ================================================================
        # 1x: 로더 그룹
        # ================================================================
        # 10. CheckpointLoaderSimple — SD1.5 (DreamShaper 또는 GeekyGhost LCM)
        "10": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": CHECKPOINT}
        },
        # 11. LoraLoader — AnimateLCM 가속 LoRA (일반 UNet LoRA, motion_lora 아님)
        #     AnimateLCM_sd15_t2v_lora는 temporal key가 없는 일반 LCM 가속 LoRA이므로
        #     ADE_AnimateDiffLoRALoader가 아닌 일반 LoraLoader로 UNet에 적용.
        "11": {
            "class_type": "LoraLoader",
            "inputs": {
                "model": ["10", 0],
                "clip": ["10", 1],
                "lora_name": ANIMATEDIFF_LORA,
                "strength_model": 0.8,
                "strength_clip": 0.8,
            }
        },
        # 12. ADE_LoopedUniformContextOptions — 프레임 간 컨텍스트 (루핑)
        #     context_length: 부분 배치 처리 (VRAM 절약). 16이 기본.
        "12": {
            "class_type": "ADE_LoopedUniformContextOptions",
            "inputs": {
                "context_length": min(16, frames),
                "context_stride": 1,
                "context_overlap": 4,
                "closed_loop": True,   # idle은 루핑 (마지막→첫 프레임 연결)
                "fuse_method": "pyramid",
            }
        },
        # 13. ADE_AnimateDiffLoaderGen1 — AnimateDiff 모션 모듈 적용
        #     motion_lora 없음 — AnimateLCM LoRA는 노드 11에서 이미 UNet에 적용됨.
        "13": {
            "class_type": "ADE_AnimateDiffLoaderGen1",
            "inputs": {
                "model": ["11", 0],
                "model_name": ANIMATEDIFF_MODEL,
                "beta_schedule": "lcm",         # LCM용 베타 스케줄
                "context_options": ["12", 0],
            }
        },

        # ================================================================
        # 2x: 입력 이미지 처리 (IPAdapter용)
        # ================================================================
        # 20. LoadImage — 캐릭터 기준 이미지
        "20": {
            "class_type": "LoadImage",
            "inputs": {"image": input_image}
        },
        # 21. PrepImageForClipVision — IPAdapter 입력 전처리 (패딩+리사이즈)
        "21": {
            "class_type": "PrepImageForClipVision",
            "inputs": {
                "image": ["20", 0],
                "interpolation": "LANCZOS",
                "crop_position": "pad",
                "sharpening": 0.0,
            }
        },
        # 22. IPAdapterUnifiedLoader — SD1.5 PLUS 프리셋 자동 로드
        "22": {
            "class_type": "IPAdapterUnifiedLoader",
            "inputs": {
                "model": ["13", 0],
                "preset": IPADAPTER_PRESET,
            }
        },
        # 23. IPAdapterAdvanced — 캐릭터 일관성 주입
        "23": {
            "class_type": "IPAdapterAdvanced",
            "inputs": {
                "model": ["22", 0],
                "ipadapter": ["22", 1],
                "image": ["21", 0],
                "weight": ip_weight,
                "weight_type": "linear",
                "combine_embeds": "concat",
                "start_at": 0.0,
                "end_at": 1.0,
                "embeds_scaling": "V only",
            }
        },

        # ================================================================
        # 3x: 컨디셔닝 (텍스트 + 옵션 ControlNet)
        # ================================================================
        # 30. CLIPTextEncode (positive)
        "30": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": positive, "clip": ["11", 1]}  # LoRA 적용된 CLIP
        },
        # 31. CLIPTextEncode (negative)
        "31": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": negative, "clip": ["11", 1]}  # LoRA 적용된 CLIP
        },
    }

    # ControlNet (옵션 — 포즈 변화가 큰 액션용)
    positive_ref = ["30", 0]
    negative_ref = ["31", 0]
    if use_controlnet:
        api["40"] = {
            "class_type": "ControlNetLoaderAdvanced",
            "inputs": {"control_net_name": CONTROLNET_OPENPOSE}
        }
        # 포즈 이미지는 입력 캐릭터와 동일하게 사용 (idle에서는 약하게)
        api["41"] = {
            "class_type": "ControlNetApplyAdvanced",
            "inputs": {
                "positive": ["30", 0],
                "negative": ["31", 0],
                "control_net": ["40", 0],
                "image": ["21", 0],
                "strength": cn_strength,
                "start_percent": 0.0,
                "end_percent": 1.0,
            }
        }
        positive_ref = ["41", 0]
        negative_ref = ["41", 1]

    # ================================================================
    # 4x: 생성 (배치 latent → LCM KSampler → VAE 디코드)
    # ================================================================
    # 50. EmptyLatentImage — batch_size = 프레임 수
    api["50"] = {
        "class_type": "EmptyLatentImage",
        "inputs": {"width": gen_size, "height": gen_size, "batch_size": frames}
    }
    # 51. KSampler — AnimateLCM LoRA 가속 생성
    #     GeekyGhost LCM 체크포인트 사용 시: steps=8, cfg=1.5, sampler=lcm
    #     일반 SD1.5 (DreamShaper) + AnimateLCM LoRA 시: steps=12~15, cfg=2.0~3.0, sampler=lcm
    api["51"] = {
        "class_type": "KSampler",
        "inputs": {
            "model": ["23", 0],
            "seed": seed,
            "steps": steps,
            "cfg": 2.0,                   # LCM LoRA 사용 시 낮은 cfg (1.5~3.0)
            "sampler_name": "lcm",
            "scheduler": "sgm_uniform",   # AnimateLCM 권장 스케줄러
            "positive": positive_ref,
            "negative": negative_ref,
            "latent_image": ["50", 0],
            "denoise": 1.0,
        }
    }
    # 52. VAEDecode (체크포인트 내장 VAE 사용)
    api["52"] = {
        "class_type": "VAEDecode",
        "inputs": {"samples": ["51", 0], "vae": ["10", 2]}
    }

    # ================================================================
    # 5x: 후처리 (배경제거 → 리사이즈 → 그리드 → GIF)
    # ================================================================
    # 60. Image Rembg — 배경 제거 (isnet-anime, 애니메이션 특화)
    #     background_color: "white" — 흰 배경으로 렌더링 후 PIL flood-fill로 투명화.
    #     (ComfyUI SaveImage는 RGB만 저장하므로 알파를 흰색으로 변환)
    api["60"] = {
        "class_type": "Image Rembg (Remove Background)",
        "inputs": {
            "images": ["52", 0],
            "transparency": True,
            "model": REMBG_MODEL,
            "post_processing": False,
            "only_mask": False,
            "alpha_matting": False,
            "alpha_matting_foreground_threshold": 240,
            "alpha_matting_background_threshold": 10,
            "alpha_matting_erode_size": 10,
            "background_color": "white",
        }
    }
    # 61. ImageScale — 최종 해상도로 축소 (nearest-exact, 픽셀 보존)
    api["61"] = {
        "class_type": "ImageScale",
        "inputs": {
            "image": ["60", 0],
            "upscale_method": "nearest-exact",
            "width": out_size,
            "height": out_size,
            "crop": "disabled",
        }
    }
    # 62. SaveImage — 개별 프레임 저장 (배치 → 각각 PNG)
    api["62"] = {
        "class_type": "SaveImage",
        "inputs": {"images": ["61", 0], "filename_prefix": name + "_frame"}
    }
    # 63. Create Grid Image from Batch — 스프라이트시트 (1행 N열)
    grid_cols = frames  # 1행 배치 (필요시 --cols 로 조정 가능)
    api["63"] = {
        "class_type": "Create Grid Image from Batch",
        "inputs": {
            "images": ["61", 0],
            "border_width": 0,            # 테두리 없음 (게임용)
            "number_of_columns": grid_cols,
            "max_cell_size": out_size,
            "border_red": 0,
            "border_green": 0,
            "border_blue": 0,
        }
    }
    # 64. SaveImage — 스프라이트시트 저장
    api["64"] = {
        "class_type": "SaveImage",
        "inputs": {"images": ["63", 0], "filename_prefix": name + "_sheet"}
    }
    # 65. VHS_VideoCombine — GIF 미리보기 (10fps 루핑)
    api["65"] = {
        "class_type": "VHS_VideoCombine",
        "inputs": {
            "images": ["61", 0],
            "frame_rate": 10.0,
            "loop_count": 0,              # 0 = 무한 루프
            "filename_prefix": name + "_preview",
            "format": "image/gif",
            "pingpong": False,            # idle은 단방향 루핑
            "save_output": True,
        }
    }
    return api


def submit_and_wait(prompt_api, timeout_s=600):
    """API JSON을 /prompt에 제출하고 완료 대기.

    반환: (result_dict, error_dict)
      result_dict: {elapsed, status, images, prompt_id}
      error_dict: None 또는 에러 정보
    """
    data = json.dumps({"prompt": prompt_api}).encode("utf-8")
    req = urllib.request.Request(
        SERVER + "/prompt", data=data,
        headers={"Content-Type": "application/json"}
    )
    try:
        resp = json.loads(urllib.request.urlopen(req, timeout=30).read())
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")[:500]
        return None, {"http_error": e.code, "body": body}
    if "error" in resp:
        return None, resp
    if "node_errors" in resp and resp["node_errors"]:
        return None, {"node_errors": resp["node_errors"]}
    pid = resp["prompt_id"]

    t0 = time.time()
    while time.time() - t0 < timeout_s:
        time.sleep(3)
        try:
            h = json.loads(
                urllib.request.urlopen(SERVER + "/history/" + pid, timeout=10).read()
            )
        except Exception:
            continue
        if pid in h:
            outputs = h[pid].get("outputs", {})
            status = h[pid].get("status", {})
            # 실행 실패 감지
            if status.get("status_str") == "error":
                return None, {"execution_error": status.get("messages", [])}
            imgs = []
            gifs = []
            for o in outputs.values():
                if "images" in o:
                    imgs.extend(o["images"])
                if "gifs" in o:
                    gifs.extend(o["gifs"])
            return {
                "elapsed": round(time.time() - t0, 1),
                "status": status,
                "images": imgs,
                "gifs": gifs,
                "prompt_id": pid,
            }, None
    return None, {"timeout": True, "elapsed": timeout_s}


def generate_spritesheet(input_image, name, frames, out_size, gen_size,
                         seed, steps, ip_weight, use_controlnet, cn_strength,
                         positive, negative):
    """스프라이트시트 1세트 생성."""
    print("[%s] 생성 중... (%d프레임, %dx%d → %dx%d, IP=%.2f, ControlNet=%s)" % (
        name, frames, gen_size, gen_size, out_size, out_size,
        ip_weight, "ON" if use_controlnet else "OFF"
    ))
    sys.stdout.flush()

    api = build_workflow(
        input_image, name, frames, out_size, gen_size,
        seed, steps, ip_weight, use_controlnet, cn_strength,
        positive, negative
    )
    result, err = submit_and_wait(api, timeout_s=900)  # 15분 타임아웃 (GTX1060)
    if err:
        print("  ❌ 실패: " + json.dumps(err, ensure_ascii=False)[:1500])
        return False

    print("  ✅ 완료! (%.1f초)" % result["elapsed"])
    print("  📁 출력 파일:")
    for img in result["images"]:
        print("    -> %s (%s)" % (img["filename"], img.get("subfolder", "")))
    for g in result["gifs"]:
        print("    -> %s [GIF]" % g["filename"])

    # PIL 투명화 후처리 (흰 배경 → 알파)
    print("  🔄 투명 배경 후처리 중...")
    transparent_files = postprocess_transparent(result, name, bg_threshold=230, feather=2)
    if transparent_files:
        print("  ✅ 투명 PNG %d개 생성 완료" % len(transparent_files))
    return True


if __name__ == "__main__":
    ap = argparse.ArgumentParser(
        description="스프라이트시트 메이커 — Civitai Sprite Sheet Maker v H42 재구현 (idle 8프레임 기본)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
사용 예:
  # 기본 idle 8프레임 (입력 이미지는 ComfyUI input 폴더에 업로드 필요)
  python3 sprite_sheet_maker.py --input knight_base.png --name knight_idle

  # 걷기 애니메이션 (ControlNet 사용, 12프레임)
  python3 sprite_sheet_maker.py --input walk_ref.png --name knight_walk \\
      --frames 12 --controlnet --positive "walking cycle animation, legs moving"

  # 저사양 모드 (더 작은 해상도, 적은 프레임)
  python3 sprite_sheet_maker.py --input char.png --name simple_idle \\
      --frames 6 --size 96 --steps 10
        """.strip()
    )
    ap.add_argument("--input", required=True,
                    help="입력 캐릭터 이미지 (ComfyUI input 폴더 내 파일명)")
    ap.add_argument("--name", required=True,
                    help="출력 파일명 접두사 (예: knight_idle)")
    ap.add_argument("--frames", type=int, default=8,
                    help="프레임 수 (기본 8)")
    ap.add_argument("--size", type=int, default=128,
                    help="최종 출력 해상도 (기본 128)")
    ap.add_argument("--gen-size", type=int, default=512,
                    help="SD 생성 해상도 (기본 512, SD1.5 최적)")
    ap.add_argument("--seed", type=int, default=42,
                    help="시드 (기본 42)")
    ap.add_argument("--steps", type=int, default=12,
                    help="LCM 스텝 수 (기본 12, LCM 체크포인트면 8, 일반 SD1.5면 12~15)")
    ap.add_argument("--ip-weight", type=float, default=0.8,
                    help="IPAdapter 가중치 — 캐릭터 일관성 (기본 0.8)")
    ap.add_argument("--controlnet", action="store_true",
                    help="ControlNet OpenPose 사용 (포즈 변화 큰 액션용)")
    ap.add_argument("--cn-strength", type=float, default=1.2,
                    help="ControlNet 강도 (기본 1.2)")
    ap.add_argument("--positive", default=DEFAULT_POSITIVE,
                    help="긍정 프롬프트")
    ap.add_argument("--negative", default=DEFAULT_NEGATIVE,
                    help="부정 프롬프트")
    args = ap.parse_args()

    ok = generate_spritesheet(
        args.input, args.name, args.frames, args.size, args.gen_size,
        args.seed, args.steps, args.ip_weight, args.controlnet, args.cn_strength,
        args.positive, args.negative
    )
    sys.exit(0 if ok else 1)
