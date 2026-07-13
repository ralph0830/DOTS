"""
sprite_creator.json 워크플로우 API 제어 스크립트
DOTS 게임 캐릭터 유닛 128x128 픽셀아트 생성.

사용법:
  python3 sprite_creator_api.py --unit knight --seed 42
  python3 sprite_creator_api.py --unit archer --seed 43
  python3 sprite_creator_api.py --batch   # knight + archer 연속 생성
"""
import json, urllib.request, time, sys, argparse

SERVER = "http://localhost:8188"

# === 캐릭터별 프롬프트 (LoRA 트리거 pxlchrctrsprt 포함) ===
UNITS = {
    "knight": {
        "seed": 42,
        "positive": (
            "pixel_character_sprite, pxlchrctrsprt, sprite, sprite sheet, pixel art, "
            "single medieval knight with sword and shield, full body, facing right, "
            "vibrant colors, clean outline, white background, game asset, 16bit retro RPG, cute chibi style"
        ),
    },
    "archer": {
        "seed": 43,
        "positive": (
            "pixel_character_sprite, pxlchrctrsprt, sprite, sprite sheet, pixel art, "
            "single medieval archer with bow and quiver, full body, facing right, "
            "vibrant colors, clean outline, white background, game asset, 16bit retro RPG, cute chibi style"
        ),
    },
}

NEGATIVE = (
    "realistic, photorealistic, 3d, text, watermark, blurry, "
    "multiple characters, busy background, messy lines, nsfw"
)

GEN_SIZE = 128  # 최종 출력 해상도 (8의 배수 — latent 직접 생성 가능)


def build_api(unit_key, seed):
    """sprite_creator.json UI 워크플로우 -> API 제출용 JSON 변환.

    핵심 변경:
      - EmptyLatentImage: 768x768 -> 128x128 (처음부터 작게 생성)
      - PixelArtDetectorConverter resize: 512 -> 128
      - PixelArtDetectorSave resize: 512 -> 128
      - ImageScale: 512 -> 128
      - 프롬프트/시드 주입
    """
    unit = UNITS[unit_key]
    pos = unit["positive"]

    api = {
        # 4. CheckpointLoaderSimple — Illustrious-XL-v2.0
        "4": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": "Illustrious-XL-v2.0.safetensors"}
        },
        # 49. LoraLoader — Game Character Sprites LoRA
        "49": {
            "class_type": "LoraLoader",
            "inputs": {
                "model": ["4", 0],
                "clip": ["4", 1],
                "lora_name": "game_character_sprites_lora.safetensors",
                "strength_model": 0.8,
                "strength_clip": 0.8,
            }
        },
        # 5. EmptyLatentImage — 128x128 (원본 768x768 에서 변경)
        "5": {
            "class_type": "EmptyLatentImage",
            "inputs": {"width": GEN_SIZE, "height": GEN_SIZE, "batch_size": 1}
        },
        # 6. CLIPTextEncode (positive)
        "6": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": pos, "clip": ["49", 1]}
        },
        # 7. CLIPTextEncode (negative)
        "7": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": NEGATIVE, "clip": ["49", 1]}
        },
        # 10. KSamplerAdvanced — BASE (원본 설정 유지, 시드만 주입)
        "10": {
            "class_type": "KSamplerAdvanced",
            "inputs": {
                "model": ["49", 0],
                "add_noise": "enable",
                "noise_seed": seed,
                "steps": 20,
                "cfg": 20,
                "sampler_name": "euler",
                "scheduler": "normal",
                "positive": ["6", 0],
                "negative": ["7", 0],
                "latent_image": ["5", 0],
                "start_at_step": 0,
                "end_at_step": 20,
                "return_with_leftover_noise": "disable",
            }
        },
        # 51. VAELoader
        "51": {
            "class_type": "VAELoader",
            "inputs": {"vae_name": "sdxl_vae.safetensors"}
        },
        # 17. VAEDecode
        "17": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["10", 0], "vae": ["51", 0]}
        },
        # 121. PixelArtDetectorToImage — 픽셀 정량화
        "121": {
            "class_type": "PixelArtDetectorToImage",
            "inputs": {
                "images": ["17", 0],
                "reduce_palette": False,
                "reduce_palette_max_colors": 128,
            }
        },
        # 111. ImageScale — 128x128 nearest-exact (원본 512)
        "111": {
            "class_type": "ImageScale",
            "inputs": {
                "image": ["121", 0],
                "upscale_method": "nearest-exact",
                "width": GEN_SIZE,
                "height": GEN_SIZE,
                "crop": "disabled",
            }
        },
        # 116. SaveImage — 스케일된 픽셀아트 원본
        "116": {
            "class_type": "SaveImage",
            "inputs": {"images": ["111", 0], "filename_prefix": "dots_" + unit_key}
        },
        # 125. PixelArtLoadPalettes — 팔레트 로드 (필수 위젯 9개 모두 포함)
        "125": {
            "class_type": "PixelArtLoadPalettes",
            "inputs": {
                "image": "31-1x.png",
                "render_all_palettes_in_grid": False,
                "grid_settings": "Grid settings. The values will be forwarded to the 'PixelArt Palette Converter to render the grid with all palettes from this node.'",
                "paletteList_grid_font_size": 40,
                "paletteList_grid_font_color": "#f40e12",
                "paletteList_grid_background": "#fff",
                "paletteList_grid_cols": 6,
                "paletteList_grid_add_border": True,
                "paletteList_grid_border_width": 3,
            }
        },
        # 126. PixelArtDetectorConverter — resize 128x128 (원본 512)
        "126": {
            "class_type": "PixelArtDetectorConverter",
            "inputs": {
                "images": ["17", 0],
                "paletteList": ["125", 0],
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
        # 118. SaveImage — GAMEBOY 팔레트 적용된 픽셀아트
        "118": {
            "class_type": "SaveImage",
            "inputs": {"images": ["126", 0], "filename_prefix": "dots_" + unit_key + "_gameboy"}
        },
        # 127. PixelArtDetectorSave — resize 128x128 (원본 512)
        "127": {
            "class_type": "PixelArtDetectorSave",
            "inputs": {
                "images": ["17", 0],
                "filename_prefix": "dots_" + unit_key + "_pixelart",
                "reduce_palette": False,
                "reduce_palette_max_colors": 128,
                "webp_mode": "lossy",
                "compression": 80,
                "save_jpg": False,
                "save_exif": True,
                "resize_w": GEN_SIZE,
                "resize_h": GEN_SIZE,
                "resize_type": "contain",
            }
        },
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


def generate_one(unit_key, seed):
    """단일 유닛 생성."""
    print("[%s] 생성 중... (시드 %d, 해상도 %dx%d)" % (unit_key, seed, GEN_SIZE, GEN_SIZE))
    sys.stdout.flush()
    api = build_api(unit_key, seed)
    result, err = submit_and_wait(api, timeout_s=300)
    if err:
        print("  실패: " + json.dumps(err, ensure_ascii=False)[:300])
        return False
    print("  완료! (%.1f초)" % result["elapsed"])
    for img in result["images"]:
        print("    -> %s (%s)" % (img["filename"], img.get("subfolder", "")))
    return True


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="DOTS 캐릭터 유닛 128x128 픽셀아트 생성")
    ap.add_argument("--unit", choices=list(UNITS.keys()), help="생성할 유닛 (knight/archer)")
    ap.add_argument("--seed", type=int, default=None, help="시드 (지정 안하면 유닛 기본값)")
    ap.add_argument("--batch", action="store_true", help="knight + archer 연속 생성")
    args = ap.parse_args()

    if args.batch:
        print("=== DOTS 유닛 일괄 생성 (128x128) ===")
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
