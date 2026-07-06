"""
DOTS 보석/심볼 생성기 (단순 저장 + 투명 PNG)
- PixelArt Palette Converter 생략: 원본 픽셀아트만 저장
- 100x100 등 임의 해상도: SDXL은 8의 배수만 생성 가능하므로 512x512로 생성 후 PIL 리사이즈
- 투명 배경: 흰색에 가까운 픽셀을 알파 0으로 변환 (PIL 후처리)
- 두 파일 저장: {prefix}_solid.png (흰 배경) / {prefix}_transparent.png (투명 배경)

사용법:
  python3 comfy_gem.py --prompt "red ruby gem..." --out-size 100 --seed 42
"""
import json, urllib.request, time, sys, argparse, os
from PIL import Image
import numpy as np
from collections import deque

SERVER = "http://localhost:8188"
WORKFLOW_PATH = "/opt/ComfyUI/user/default/workflows/workflow.json"
OUTPUT_DIR = "/opt/ComfyUI/output"

# 사용자 워크플로우 노드 ID (핵심만)
N_CHECKPOINT = 4
N_LORA = 49
N_VAE_LOAD = 51
N_EMPTY_LATENT = 5
N_CLIP_POS = 6
N_CLIP_NEG = 7
N_KSAMPLER = 10
N_VAE_DECODE = 17


def load_workflow():
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def build_simple_api(ui_wf, prompt_text, negative_text, width, height, seed, steps):
    """팔레트 변환/픽셀아트 노드 생략. 생성→디코드→저장만."""
    nodes = {n["id"]: n for n in ui_wf["nodes"]}

    def w(nid, idx, default=None):
        n = nodes.get(nid)
        if not n:
            return default
        wv = n.get("widgets_values", [])
        return wv[idx] if idx < len(wv) else default

    api = {}
    api[str(N_CHECKPOINT)] = {
        "class_type": "CheckpointLoaderSimple",
        "inputs": {"ckpt_name": w(N_CHECKPOINT, 0)}
    }
    api[str(N_LORA)] = {
        "class_type": "LoraLoader",
        "inputs": {
            "model": [str(N_CHECKPOINT), 0],
            "clip": [str(N_CHECKPOINT), 1],
            "lora_name": w(N_LORA, 0),
            "strength_model": w(N_LORA, 1),
            "strength_clip": w(N_LORA, 2),
        }
    }
    api[str(N_VAE_LOAD)] = {
        "class_type": "VAELoader",
        "inputs": {"vae_name": w(N_VAE_LOAD, 0)}
    }
    api[str(N_EMPTY_LATENT)] = {
        "class_type": "EmptyLatentImage",
        "inputs": {"width": width, "height": height, "batch_size": 1}
    }
    api[str(N_CLIP_POS)] = {
        "class_type": "CLIPTextEncode",
        "inputs": {"text": prompt_text, "clip": [str(N_LORA), 1]}
    }
    api[str(N_CLIP_NEG)] = {
        "class_type": "CLIPTextEncode",
        "inputs": {"text": negative_text, "clip": [str(N_LORA), 1]}
    }
    api[str(N_KSAMPLER)] = {
        "class_type": "KSamplerAdvanced",
        "inputs": {
            "model": [str(N_LORA), 0],
            "positive": [str(N_CLIP_POS), 0],
            "negative": [str(N_CLIP_NEG), 0],
            "latent_image": [str(N_EMPTY_LATENT), 0],
            "add_noise": w(N_KSAMPLER, 0, "enable"),
            "noise_seed": seed,
            "steps": steps,
            "cfg": w(N_KSAMPLER, 4, 8),
            "sampler_name": w(N_KSAMPLER, 5, "euler"),
            "scheduler": w(N_KSAMPLER, 6, "normal"),
            "start_at_step": w(N_KSAMPLER, 7, 0),
            "end_at_step": steps,
            "return_with_leftover_noise": w(N_KSAMPLER, 9, "disable"),
        }
    }
    api[str(N_VAE_DECODE)] = {
        "class_type": "VAEDecode",
        "inputs": {"samples": [str(N_KSAMPLER), 0], "vae": [str(N_VAE_LOAD), 0]}
    }
    # SaveImage 추가 (단순 저장)
    api["save"] = {
        "class_type": "SaveImage",
        "inputs": {"images": [str(N_VAE_DECODE), 0], "filename_prefix": "gem_solid"}
    }
    return api


def submit_and_wait(prompt_api, timeout_s=300):
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
            imgs = []
            for o in outputs.values():
                if "images" in o:
                    imgs.extend(o["images"])
            return {"elapsed": round(time.time() - t0, 1), "images": imgs, "prompt_id": pid}, None
    return None, {"timeout": True}


def make_transparent(solid_path, out_path, bg_threshold=235, feather=2):
    """배경(순백) 영역만 투명화 — flood-fill 기반.
    핵심: 모서리에서 준백 픽셀을 따라 BFS 탐색하여 '외부 배경 영역'만 식별.
    심볼 내부의 밝은 하이라이트(분홍/연노랑 등)는 모서리와 연결되지 않으므로
    불투명하게 유지 → 심볼 자체가 반투명해지는 번짐 방지.

    bg_threshold: R,G,B 모두 이值 이상이면 배경색 후보 (0~255).
    feather: 경계 안티앨리어싱 페더링 폭 (픽셀)."""
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

    # 알파: 배경=0, 심볼=255. 페더링으로 경계 안티앨리어싱.
    alpha = np.where(bg_mask, 0.0, 255.0)
    if feather > 0:
        cur = bg_mask.copy()
        for i in range(feather):
            # 4방향 팽창 (numpy roll 기반)
            dil = cur.copy()
            dil[1:, :] |= cur[:-1, :]; dil[:-1, :] |= cur[1:, :]
            dil[:, 1:] |= cur[:, :-1]; dil[:, :-1] |= cur[:, 1:]
            edge = dil & ~cur  # 새로 추가된 픽셀 (심볼쪽으로 확장)
            ys, xs = np.where(edge)
            if len(ys) > 0:
                # 밝을수록 더 투명 (배경에 가까운 경계)
                brightness = arr[ys, xs].min(axis=1)
                ratio = np.clip((255.0 - brightness) / max(1.0, 255.0 - bg_threshold), 0, 1)
                t = (i + 1) / (feather + 1)
                alpha[ys, xs] = 255.0 * t * ratio
            cur = dil

    rgba = np.dstack([arr, alpha]).astype(np.uint8)
    result = Image.fromarray(rgba, "RGBA")
    result.save(out_path)
    return result.size


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", default="single red ruby gemstone, faceted crystal, glossy, centered, solid pure white background, 16-bit pixel art, game icon")
    ap.add_argument("--negative", default="realistic, photorealistic, 3d, text, watermark, blurry, multiple objects, border, frame")
    ap.add_argument("--gen-size", type=int, default=512, help="SDXL 생성 해상도 (8의 배수, 기본 512)")
    ap.add_argument("--out-size", type=int, default=100, help="최종 출력 해상도 (PIL 리사이즈, 기본 100)")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--steps", type=int, default=20)
    ap.add_argument("--prefix", default="gem")
    ap.add_argument("--threshold", type=int, default=235, help="배경색 임계값 (R,G,B 모두 이值 이상=배경, 230~245 권장)")
    args = ap.parse_args()

    # SDXL은 8의 배수 강제
    gen = args.gen_size
    if gen % 8 != 0:
        gen = (gen // 8) * 8
        print("[주의] gen-size를 8의 배수로 조정: " + str(gen))

    ui = load_workflow()
    api = build_simple_api(ui, args.prompt, args.negative, gen, gen, args.seed, args.steps)

    print("=" * 55)
    print("보석 생성 (단순 저장 + 투명변환)")
    print("=" * 55)
    print("프롬프트: " + args.prompt[:70] + ("..." if len(args.prompt) > 70 else ""))
    print("생성해상도: " + str(gen) + "x" + str(gen) + " / 출력: " + str(args.out_size) + "x" + str(args.out_size))
    print("시드: " + str(args.seed) + " / 스텝: " + str(args.steps))
    print("")

    # 1) ComfyUI 생성
    result, err = submit_and_wait(api, timeout_s=300)
    if err:
        print("[실패] " + json.dumps(err, ensure_ascii=False)[:200])
        sys.exit(1)
    print("[1/3] ComfyUI 생성 완료 (" + str(result["elapsed"]) + "초)")
    src_img = result["images"][0]
    src_path = os.path.join(OUTPUT_DIR, src_img["filename"])

    # 2) out-size 리사이즈 (nearest-exact 로 픽셀 보존)
    solid_out = os.path.join(OUTPUT_DIR, args.prefix + "_solid_" + str(args.out_size) + ".png")
    im = Image.open(src_path).convert("RGB")
    if args.out_size != gen:
        im = im.resize((args.out_size, args.out_size), Image.NEAREST)
    im.save(solid_out)
    print("[2/3] 흰배경 저장: " + os.path.basename(solid_out) + " (" + str(im.size[0]) + "x" + str(im.size[1]) + ")")

    # 3) 투명 배경 변환
    trans_out = os.path.join(OUTPUT_DIR, args.prefix + "_transparent_" + str(args.out_size) + ".png")
    sz = make_transparent(solid_out, trans_out, bg_threshold=args.threshold)
    print("[3/3] 투명배경 저장: " + os.path.basename(trans_out) + " (" + str(sz[0]) + "x" + str(sz[1]) + ")")
    print("")
    print("완료. 최종 파일:")
    print("  " + solid_out)
    print("  " + trans_out)
