"""
DOTS 픽셀아트 워크플로우 — inzaniak 가이드 정석 스택
128x128 타겟 해상도로 게임 캐릭터 유닛 생성.

가이드 정석 모델 스택:
  체크포인트: Mistoon_Pearl (SD 1.5 툰/애니메이션)
  LoRA: Skormino Pixel Art Style v8 (Illustrious — 일단 시도, 호환 시 사용)
  업스케일러: 4x-Fatal-Anime (가이드 추천 애니메이션 업스케일)
  픽셀화: comfy_pixelization (가이드 핵심 — Pixelization 노드)

워크플로우 구조:
  1패스: 512x512 생성 (SD 1.5 최적 해상도)
  ESRGAN 업스케일: 512→2048 (4x-Fatal-Anime)
  축소: 2048→128 (lanczos 고품질 다운샘플링)
  Pixelization: comfy_pixelization 픽셀화
  PixelArtDetector: GAMEBOY 팔레트 적용

사용법:
  python3 pixel_guide_workflow.py --unit knight
  python3 pixel_guide_workflow.py --unit archer
  python3 pixel_guide_workflow.py --batch
"""
import json, urllib.request, time, sys, argparse

SERVER = "http://localhost:8188"

# === 캐릭터별 프롬프트 (3등신 chibi, idle, 발 잘림 방지) ===
# 체크포인트: Mistoon_Pearl (SD 1.5 툰/애니메이션)
UNITS = {
    "knight": {
        "seed": 42,
        "positive": (
            "pixel art, sprite, "
            "exactly one character, solo, "
            "cute chibi knight, super deformed, 3 head ratio, big head small body, kawaii, adorable, "
            "polished steel plate armor with gold trim and engravings, "
            "blue tabard with lion crest, chainmail underneath, "
            "ornate silver helmet with red plume, steel gauntlets, plate boots, "
            "small sword in right hand pointing down, round shield with cross emblem on left arm, "
            "standing idle pose, relaxed neutral stance, facing right, right side profile view, "
            "wearing plate boots, feet visible, standing on ground, "
            "full body head to toe, entire character fits inside frame with margin, "
            "nothing cropped, nothing cut off, "
            "centered, vibrant saturated colors, thick clean bold black outline, "
            "detailed shading, highlights and shadows, pure white background, "
            "16bit retro RPG game asset, highly detailed"
        ),
    },
    "archer": {
        "seed": 43,
        "positive": (
            "pixel art, sprite, "
            "exactly one character, solo, "
            "cute chibi archer, super deformed, 3 head ratio, big head small body, kawaii, adorable, "
            "forest green hooded cloak with leaf patterns, "
            "brown leather tunic with belt, leather bracers, fur-trimmed shoulders, "
            "leather quiver with feathered arrows on back, "
            "small wooden recurve bow held down in left hand, "
            "standing idle pose, relaxed neutral stance, facing right, right side profile view, "
            "wearing leather boots, feet visible, standing on ground, "
            "full body head to toe, entire character fits inside frame with margin, "
            "nothing cropped, nothing cut off, "
            "centered, vibrant saturated colors, thick clean bold black outline, "
            "detailed shading, highlights and shadows, pure white background, "
            "16bit retro RPG game asset, highly detailed"
        ),
    },
}

NEGATIVE = (
    "realistic, photorealistic, 3d render, text, watermark, signature, blurry, "
    "two characters, multiple characters, group, crowd, sprite sheet, grid, "
    "busy background, landscape, scenery, environment, "
    "messy lines, nsfw, deformed, extra limbs, bad anatomy, "
    "scary, ugly, creepy, muscular, realistic proportions, "
    "small character, tiny, far away, distant, zoomed out, wide shot, "
    "cropped, cut off, out of frame, partially visible, weapon cut off, head cut off, feet cut off"
)

# === 해상도 상수 ===
GEN_SIZE = 128      # 최종 타겟 해상도
GEN_W = 768         # 생성 가로 (SD 1.5 디테일 확보)
GEN_H = 1024        # 생성 세로 (캐릭터 전체 신장 수용 — 잘림 방지)


def build_api(unit_key, seed):
    """가이드 기반 SD 1.5 픽셀아트 워크플로우 API JSON 생성.

    노드 ID 체계:
      1x: 로더 (체크포인트, 업스케일 모델)
      2x: 1패스 (프롬프트, latent, KSampler, VAE 디코드)
      3x: ESRGAN 업스케일 (4x-Fatal-Anime)
      4x: 축소 + Pixelization
      5x: PixelArtDetector (GAMEBOY 팔레트)
    """
    unit = UNITS[unit_key]
    pos = unit["positive"]

    api = {
        # === 로더 그룹 ===
        # 10. CheckpointLoaderSimple — Mistoon_Pearl (SD 1.5, 가이드 추천)
        "10": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": "mistoonPearl_v10.safetensors"}
        },
        # 12. UpscaleModelLoader — 4x-Fatal-Anime
        "12": {
            "class_type": "UpscaleModelLoader",
            "inputs": {"model_name": "4x-Fatal-Anime.pth"}
        },

        # === 1패스: SD 1.5 최적 해상도로 캐릭터 생성 ===
        # 20. EmptyLatentImage — 768x1024 (세로형 — 캐릭터 전체 신장 수용)
        "20": {
            "class_type": "EmptyLatentImage",
            "inputs": {"width": GEN_W, "height": GEN_H, "batch_size": 1}
        },
        # 21. CLIPTextEncode (positive)
        "21": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": pos, "clip": ["10", 1]}
        },
        # 22. CLIPTextEncode (negative)
        "22": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": NEGATIVE, "clip": ["10", 1]}
        },
        # 23. KSampler — 고품질 생성
        "23": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["10", 0],
                "seed": seed,
                "steps": 30,
                "cfg": 7.0,
                "sampler_name": "euler_ancestral",
                "scheduler": "normal",
                "positive": ["21", 0],
                "negative": ["22", 0],
                "latent_image": ["20", 0],
                "denoise": 1.0,
            }
        },
        # 24. VAEDecode (체크포인트 내장 VAE 사용)
        "24": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["23", 0], "vae": ["10", 2]}
        },
        # 25. SaveImage — 1패스 원본 (768x768)
        "25": {
            "class_type": "SaveImage",
            "inputs": {"images": ["24", 0], "filename_prefix": "guide_" + unit_key + "_768"}
        },

        # === ESRGAN 업스케일 (4x-Fatal-Anime로 디테일 복원) ===
        # 30. ImageUpscaleWithModel — 256→1024 (4x-Fatal-Anime)
        "30": {
            "class_type": "ImageUpscaleWithModel",
            "inputs": {
                "upscale_model": ["12", 0],
                "image": ["24", 0],
            }
        },

        # === 축소 + Pixelization ===
        # 40. ImageScale — 3072x4096→128x128 (center crop, 정사각형 스프라이트)
        "40": {
            "class_type": "ImageScale",
            "inputs": {
                "image": ["30", 0],
                "upscale_method": "lanczos",
                "width": GEN_SIZE,
                "height": GEN_SIZE,
                "crop": "center",
            }
        },
        # 41. SaveImage — 축소된 128x128
        "41": {
            "class_type": "SaveImage",
            "inputs": {"images": ["40", 0], "filename_prefix": "guide_" + unit_key + "_128"}
        },
        # 42. Pixelization — comfy_pixelization (가이드 핵심 픽셀화)
        "42": {
            "class_type": "Pixelization",
            "inputs": {
                "image": ["40", 0],
                "pixel_size": 4,
                "upscale_after": True,
                "copy_hue": False,
                "copy_sat": False,
                "copy_val": False,
                "restore_dark": 15,
                "restore_bright": 1,
            }
        },
        # 43. SaveImage — Pixelization 적용
        "43": {
            "class_type": "SaveImage",
            "inputs": {"images": ["42", 0], "filename_prefix": "guide_" + unit_key + "_pixelized"}
        },

        # === PixelArtDetector (GAMEBOY 팔레트) ===
        # 50. PixelArtLoadPalettes — 팔레트 로드
        "50": {
            "class_type": "PixelArtLoadPalettes",
            "inputs": {
                "image": "31-1x.png",
                "render_all_palettes_in_grid": False,
                "grid_settings": "Grid settings.",
                "paletteList_grid_font_size": 40,
                "paletteList_grid_font_color": "#f40e12",
                "paletteList_grid_background": "#fff",
                "paletteList_grid_cols": 6,
                "paletteList_grid_add_border": True,
                "paletteList_grid_border_width": 3,
            }
        },
        # 51. PixelArtDetectorConverter — GAMEBOY 팔레트 적용
        "51": {
            "class_type": "PixelArtDetectorConverter",
            "inputs": {
                "images": ["42", 0],
                "paletteList": ["50", 0],
                "palette": "GAMEBOY",
                "resize_w": GEN_SIZE,
                "resize_h": GEN_SIZE,
                "resize_type": "contain",
                "pixelize": "Image.quantize",
                "grid_pixelate_grid_scan_size": 2,
                "reduce_colors_before_palette_swap": False,
                "reduce_colors_method": "Image.quantize",
                "reduce_colors_max_colors": 128,
                "apply_pixeldetector_max_colors": False,
                "image_quantize_reduce_method": "MAXCOVERAGE",
            }
        },
        # 52. SaveImage — GAMEBOY 팔레트 최종
        "52": {
            "class_type": "SaveImage",
            "inputs": {"images": ["51", 0], "filename_prefix": "guide_" + unit_key + "_gameboy"}
        },
    }
    return api


def submit_and_wait(prompt_api, timeout_s=600):
    """API JSON을 /prompt에 제출하고 완료 대기."""
    data = json.dumps({"prompt": prompt_api}).encode("utf-8")
    req = urllib.request.Request(SERVER + "/prompt", data=data, headers={"Content-Type": "application/json"})
    resp = json.loads(urllib.request.urlopen(req, timeout=30).read())
    if "error" in resp:
        return None, resp
    pid = resp["prompt_id"]
    t0 = time.time()
    while time.time() - t0 < timeout_s:
        time.sleep(3)
        try:
            h = json.loads(urllib.request.urlopen(SERVER + "/history/" + pid, timeout=10).read())
        except Exception:
            continue
        if pid in h:
            outputs = h[pid].get("outputs", {})
            status = h[pid].get("status", {})
            imgs = []
            for o in outputs.values():
                if "images" in o:
                    imgs.extend(o["images"])
            return {"elapsed": round(time.time() - t0, 1), "status": status, "images": imgs, "prompt_id": pid}, None
    return None, {"timeout": True, "elapsed": timeout_s}


def generate_one(unit_key, seed):
    """단일 유닛 생성."""
    print("[%s] 가이드 정석 스택 생성 중... (시드 %d, 768x1024->128, MistoonPearl+FatalAnime)" % (unit_key, seed))
    sys.stdout.flush()
    api = build_api(unit_key, seed)
    result, err = submit_and_wait(api, timeout_s=600)
    if err:
        print("  실패: " + json.dumps(err, ensure_ascii=False)[:400])
        return False
    print("  완료! (%.1f초)" % result["elapsed"])
    for img in result["images"]:
        print("    -> %s (%s)" % (img["filename"], img.get("subfolder", "")))
    return True


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="DOTS 픽셀아트 가이드 스택 워크플로우 (SD 1.5)")
    ap.add_argument("--unit", choices=list(UNITS.keys()), help="생성할 유닛 (knight/archer)")
    ap.add_argument("--seed", type=int, default=None, help="시드")
    ap.add_argument("--batch", action="store_true", help="knight + archer 연속 생성")
    args = ap.parse_args()

    if args.batch:
        print("=== DOTS 가이드 스택 일괄 생성 (128x128) ===")
        ok = 0
        for key in UNITS:
            seed = args.seed if args.seed is not None else UNITS[key]["seed"]
            if generate_one(key, seed):
                ok += 1
            print()
        print("완료: %d/%d" % (ok, len(UNITS)))
    elif args.unit:
        seed = args.seed if args.seed is not None else UNITS[args.unit]["seed"]
        generate_one(args.unit, seed)
    else:
        ap.print_help()
