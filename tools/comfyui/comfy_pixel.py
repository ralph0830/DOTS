"""
DOTS 픽셀아트 심볼 생성기 - 사용자 워크플로우 API 제어
저장된 workflow.json (UI 형식)을 API JSON으로 변환 후 프롬프트/해상도/시드 제어.

사용법:
  python3 comfy_pixel.py --prompt "single red ruby gemstone icon..." --seed 42
  python3 comfy_pixel.py --prompt "..." --width 512 --height 512 --steps 20
"""
import json, urllib.request, time, sys, argparse

SERVER = "http://localhost:8188"
WORKFLOW_PATH = "/opt/ComfyUI/user/default/workflows/workflow.json"

# 사용자 워크플로우의 노드 ID 매핑 (분석 결과 하드코딩)
NODE_IDS = {
    "checkpoint": 4,
    "lora": 49,
    "vae_load": 51,
    "empty_latent": 5,
    "clip_pos": 6,       # CLIP positive
    "clip_neg": 7,       # CLIP negative
    "primitive_pos": 13, # Positive prompt 텍스트 원본
    "primitive_neg": 14, # Negative prompt 텍스트 원본
    "ksampler": 10,
    "primitive_steps": 45,
    "primitive_end": 47,
    "vae_decode": 17,
    "image_scale": 111,
    "save_orig": 116,    # SaveImage (스케일된 원본)
    "palette_load": 125,
    "pixelart_to_img": 121,
    "pixelart_conv": 126,
    "pixelart_save": 118,
}


def load_workflow():
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def build_api_prompt(ui_wf, prompt_text, negative_text, width, height, seed, steps, palette, filename_prefix):
    """UI 워크플로우 JSON -> API 제출용 JSON 변환 + 파라미터 주입."""
    nodes = {n["id"]: n for n in ui_wf["nodes"]}
    links = {l[0]: l for l in ui_wf["links"]}  # link_id -> [id, from_node, from_slot, to_node, to_slot, type]

    def w(nid, idx, default=None):
        """노드의 widgets_values[idx] 반환."""
        n = nodes.get(nid)
        if not n:
            return default
        wv = n.get("widgets_values", [])
        if idx < len(wv):
            return wv[idx]
        return default

    def conn(to_nid, input_name):
        """to_nid 노드의 input_name 입력이 어디서 오는지 (from_node, from_slot) 반환 또는 None."""
        n = nodes.get(to_nid)
        if not n:
            return None
        for inp in n.get("inputs", []):
            if inp.get("name") == input_name:
                link_id = inp.get("link")
                if link_id is None:
                    return None
                l = links.get(link_id)
                if l:
                    return [str(l[1]), l[2]]  # [from_node_id_str, from_slot]
        return None

    N = NODE_IDS
    api = {}

    # 4. CheckpointLoaderSimple
    api[str(N["checkpoint"])] = {
        "class_type": "CheckpointLoaderSimple",
        "inputs": {"ckpt_name": w(N["checkpoint"], 0)}
    }
    # 49. LoraLoader (model/clip from checkpoint)
    api[str(N["lora"])] = {
        "class_type": "LoraLoader",
        "inputs": {
            "model": [str(N["checkpoint"]), 0],
            "clip": [str(N["checkpoint"]), 1],
            "lora_name": w(N["lora"], 0),
            "strength_model": w(N["lora"], 1),
            "strength_clip": w(N["lora"], 2),
        }
    }
    # 51. VAELoader
    api[str(N["vae_load"])] = {
        "class_type": "VAELoader",
        "inputs": {"vae_name": w(N["vae_load"], 0)}
    }
    # 5. EmptyLatentImage (파라미터 주입)
    api[str(N["empty_latent"])] = {
        "class_type": "EmptyLatentImage",
        "inputs": {"width": width, "height": height, "batch_size": 1}
    }
    # 6. CLIP positive (프롬프트 주입)
    api[str(N["clip_pos"])] = {
        "class_type": "CLIPTextEncode",
        "inputs": {"text": prompt_text, "clip": [str(N["lora"]), 1]}
    }
    # 7. CLIP negative
    api[str(N["clip_neg"])] = {
        "class_type": "CLIPTextEncode",
        "inputs": {"text": negative_text, "clip": [str(N["lora"]), 1]}
    }
    # 10. KSamplerAdvanced
    api[str(N["ksampler"])] = {
        "class_type": "KSamplerAdvanced",
        "inputs": {
            "model": [str(N["lora"]), 0],
            "positive": [str(N["clip_pos"]), 0],
            "negative": [str(N["clip_neg"]), 0],
            "latent_image": [str(N["empty_latent"]), 0],
            "add_noise": w(N["ksampler"], 0, "enable"),
            "noise_seed": seed,
            "steps": steps,
            "cfg": w(N["ksampler"], 4, 8),
            "sampler_name": w(N["ksampler"], 5, "euler"),
            "scheduler": w(N["ksampler"], 6, "normal"),
            "start_at_step": w(N["ksampler"], 7, 0),
            "end_at_step": steps,
            "return_with_leftover_noise": w(N["ksampler"], 9, "disable"),
        }
    }
    # 17. VAEDecode
    api[str(N["vae_decode"])] = {
        "class_type": "VAEDecode",
        "inputs": {"samples": [str(N["ksampler"]), 0], "vae": [str(N["vae_load"]), 0]}
    }
    # 121. PixelArtDetectorToImage (VAEDecode 출력 -> 픽셀 정량화 이미지)
    api[str(N["pixelart_to_img"])] = {
        "class_type": "PixelArtDetectorToImage",
        "inputs": {
            "images": [str(N["vae_decode"]), 0],
            "reduce_palette": w(N["pixelart_to_img"], 0, False),
            "reduce_palette_max_colors": w(N["pixelart_to_img"], 1, 128),
        }
    }
    # 111. ImageScale (pixelart_to_img -> 512x512 nearest-exact)
    api[str(N["image_scale"])] = {
        "class_type": "ImageScale",
        "inputs": {
            "image": [str(N["pixelart_to_img"]), 0],
            "upscale_method": w(N["image_scale"], 0, "nearest-exact"),
            "width": w(N["image_scale"], 1, 512),
            "height": w(N["image_scale"], 2, 512),
            "crop": w(N["image_scale"], 3, "disabled"),
        }
    }
    # 116. SaveImage (스케일된 픽셀아트 원본 저장)
    api[str(N["save_orig"])] = {
        "class_type": "SaveImage",
        "inputs": {"images": [str(N["image_scale"]), 0], "filename_prefix": filename_prefix + "_raw"}
    }
    # 125. PixelArtLoadPalettes
    api[str(N["palette_load"])] = {
        "class_type": "PixelArtLoadPalettes",
        "inputs": {
            "image": palette if palette else w(N["palette_load"], 0, "31-1x.png"),
            "render_all_palettes_in_grid": w(N["palette_load"], 1, False),
            "grid_settings": w(N["palette_load"], 2, ""),
            "paletteList_grid_font_size": w(N["palette_load"], 3, 40),
            "paletteList_grid_font_color": w(N["palette_load"], 4, "#f40e12"),
            "paletteList_grid_background": w(N["palette_load"], 5, "#fff"),
            "paletteList_grid_cols": w(N["palette_load"], 6, 6),
            "paletteList_grid_add_border": w(N["palette_load"], 7, True),
            "paletteList_grid_border_width": w(N["palette_load"], 8, 3),
        }
    }
    # 126. PixelArtDetectorConverter (VAEDecode 원본 + 팔레트 -> GAMEBOY 변환)
    api[str(N["pixelart_conv"])] = {
        "class_type": "PixelArtDetectorConverter",
        "inputs": {
            "images": [str(N["vae_decode"]), 0],
            "paletteList": [str(N["palette_load"]), 0],
            "palette": w(N["pixelart_conv"], 0, "GAMEBOY"),
            "resize_w": w(N["pixelart_conv"], 1, 512),
            "resize_h": w(N["pixelart_conv"], 2, 512),
            "resize_type": w(N["pixelart_conv"], 3, "contain"),
            "pixelize": w(N["pixelart_conv"], 4, "Image.quantize"),
            "grid_pixelate_grid_scan_size": w(N["pixelart_conv"], 5, 2),
            "reduce_colors_before_palette_swap": w(N["pixelart_conv"], 6, True),
            "reduce_colors_method": w(N["pixelart_conv"], 7, "Image.quantize"),
            "reduce_colors_max_colors": w(N["pixelart_conv"], 8, 128),
            "apply_pixeldetector_max_colors": w(N["pixelart_conv"], 9, False),
            "image_quantize_reduce_method": w(N["pixelart_conv"], 10, "MAXCOVERAGE"),
            "opencv_settings": w(N["pixelart_conv"], 11, ""),
            "opencv_kmeans_centers": w(N["pixelart_conv"], 12, "RANDOM_CENTERS"),
            "opencv_kmeans_attempts": w(N["pixelart_conv"], 13, 10),
            "opencv_criteria_max_iterations": w(N["pixelart_conv"], 14, 10),
            "pycluster_kmeans_metrics": w(N["pixelart_conv"], 15, "EUCLIDEAN_SQUARE"),
            "cleanup": w(N["pixelart_conv"], 16, ""),
            "cleanup_colors": w(N["pixelart_conv"], 17, True),
            "cleanup_pixels_threshold": w(N["pixelart_conv"], 18, 0.02),
            "dither": w(N["pixelart_conv"], 19, "none"),
        }
    }
    # 118. SaveImage (팔레트 적용된 최종 픽셀아트)
    api[str(N["pixelart_save"])] = {
        "class_type": "SaveImage",
        "inputs": {"images": [str(N["pixelart_conv"]), 0], "filename_prefix": filename_prefix + "_pixel"}
    }
    return api


def submit_and_wait(prompt_api, timeout_s=300):
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


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", default="single red ruby gemstone icon, centered, solid white background, 16-bit pixel art, game asset, cute")
    ap.add_argument("--negative", default="realistic, photorealistic, 3d, text, watermark, blurry")
    ap.add_argument("--width", type=int, default=1024)
    ap.add_argument("--height", type=int, default=1024)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--steps", type=int, default=20)
    ap.add_argument("--palette", default="31-1x.png")
    ap.add_argument("--prefix", default="dots_ruby")
    args = ap.parse_args()

    ui = load_workflow()
    api = build_api_prompt(ui, args.prompt, args.negative, args.width, args.height, args.seed, args.steps, args.palette, args.prefix)

    print("=== 워크플로우 변환 완료, API 제출 ===")
    print("프롬프트: " + args.prompt[:80] + ("..." if len(args.prompt) > 80 else ""))
    print("해상도: " + str(args.width) + "x" + str(args.height) + " / 시드: " + str(args.seed) + " / 스텝: " + str(args.steps))
    print("노드 수: " + str(len(api)))
    print("")

    result, err = submit_and_wait(api, timeout_s=300)
    if err:
        print("오류: " + json.dumps(err, ensure_ascii=False)[:300])
        sys.exit(1)
    print("성공! 소요 " + str(result["elapsed"]) + "초")
    for img in result["images"]:
        print("이미지: " + img["filename"] + " (" + img.get("subfolder", "") + ")")
