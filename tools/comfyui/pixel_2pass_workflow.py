"""
DOTS 픽셀아트 2패스 워크플로우 — inzaniak 가이드 기반
128x128 타겟 해상도로 게임 캐릭터 유닛 생성.

워크플로우 구조 (가이드 핵심 원리 적용):
  1패스: 128x128 저해상도 생성 (캐릭터 형태 확립)
  알고리즘 업스케일: 128→512 (nearest-exact, 디테일 복원 작업 공간)
  2패스: 512x512 재샘플링 (denoise 0.35, 형태 유지하며 디테일 보완)
  ESRGAN 업스케일: 512→2048 (고해상도화)
  축소: 2048→128 (lanczos 고품질 다운샘플링)
  PixelArt 변환: 픽셀 정량화 + GAMEBOY 팔레트

사용법:
  python3 pixel_2pass_workflow.py --unit knight
  python3 pixel_2pass_workflow.py --unit archer
  python3 pixel_2pass_workflow.py --batch
"""
import json, urllib.request, time, sys, argparse

SERVER = "http://localhost:8188"

# === 캐릭터별 프롬프트 ===
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
    "multiple characters, busy background, messy lines, nsfw, "
    "deformed, extra limbs, bad anatomy"
)

# === 해상도 상수 ===
GEN_SIZE = 128     # 최종 타겟 해상도
PASS1_SIZE = 128   # 1패스 생성 해상도 (8의 배수)
WORK_SIZE = 512    # 2패스 작업 해상도 (업스케일 후)
DENOISE_2ND = 0.35  # 2패스 denoise (형태 유지하며 디테일 보완)


def build_api(unit_key, seed):
    """2패스 픽셀아트 워크플로우 API JSON 생성.

    노드 ID 체계:
      1x: 로더 (체크포인트, LoRA, VAE, 업스케일 모델)
      2x: 1패스 (프롬프트, latent, KSampler, VAE 디코드)
      3x: 알고리즘 업스케일 (ImageScale 512)
      4x: 2패스 (VAE 인코드, KSampler 2차, VAE 디코드)
      5x: ESRGAN 업스케일 (UpscaleModelLoader, ImageUpscaleWithModel)
      6x: 최종 축소 + PixelArt 변환
    """
    unit = UNITS[unit_key]
    pos = unit["positive"]

    api = {
        # === 로더 그룹 ===
        # 10. CheckpointLoaderSimple — Illustrious-XL-v2.0
        "10": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": "Illustrious-XL-v2.0.safetensors"}
        },
        # 11. LoraLoader — Game Character Sprites LoRA
        "11": {
            "class_type": "LoraLoader",
            "inputs": {
                "model": ["10", 0],
                "clip": ["10", 1],
                "lora_name": "game_character_sprites_lora.safetensors",
                "strength_model": 0.8,
                "strength_clip": 0.8,
            }
        },
        # 12. VAELoader
        "12": {
            "class_type": "VAELoader",
            "inputs": {"vae_name": "sdxl_vae.safetensors"}
        },
        # 13. UpscaleModelLoader — RealESRGAN 4x
        "13": {
            "class_type": "UpscaleModelLoader",
            "inputs": {"model_name": "RealESRGAN_x4plus.pth"}
        },

        # === 1패스: 저해상도 생성 ===
        # 20. EmptyLatentImage — 128x128
        "20": {
            "class_type": "EmptyLatentImage",
            "inputs": {"width": PASS1_SIZE, "height": PASS1_SIZE, "batch_size": 1}
        },
        # 21. CLIPTextEncode (positive)
        "21": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": pos, "clip": ["11", 1]}
        },
        # 22. CLIPTextEncode (negative)
        "22": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": NEGATIVE, "clip": ["11", 1]}
        },
        # 23. KSampler — 1패스 (캐릭터 형태 생성)
        "23": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["11", 0],
                "seed": seed,
                "steps": 25,
                "cfg": 7.0,
                "sampler_name": "euler_ancestral",
                "scheduler": "normal",
                "positive": ["21", 0],
                "negative": ["22", 0],
                "latent_image": ["20", 0],
                "denoise": 1.0,
            }
        },
        # 24. VAEDecode — 1패스 결과
        "24": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["23", 0], "vae": ["12", 0]}
        },

        # === 알고리즘 업스케일 ===
        # 30. ImageScale — 128→512 nearest-exact (픽셀 늘리기, 부드럽게)
        "30": {
            "class_type": "ImageScale",
            "inputs": {
                "image": ["24", 0],
                "upscale_method": "nearest-exact",
                "width": WORK_SIZE,
                "height": WORK_SIZE,
                "crop": "disabled",
            }
        },
        # 31. VAEEncode — 512 이미지를 latent로 변환 (2패스 입력)
        "31": {
            "class_type": "VAEEncode",
            "inputs": {"pixels": ["30", 0], "vae": ["12", 0]}
        },

        # === 2패스: 디테일 보완 ===
        # 40. KSampler — 2패스 (denoise 0.35, 형태 유지하며 디테일 복원)
        "40": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["11", 0],
                "seed": seed + 1,  # 살짝 다른 시드로 변형
                "steps": 20,
                "cfg": 7.0,
                "sampler_name": "euler_ancestral",
                "scheduler": "normal",
                "positive": ["21", 0],
                "negative": ["22", 0],
                "latent_image": ["31", 0],
                "denoise": DENOISE_2ND,
            }
        },
        # 41. VAEDecode — 2패스 결과
        "41": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["40", 0], "vae": ["12", 0]}
        },

        # === ESRGAN 업스케일 ===
        # 50. ImageUpscaleWithModel — 512→2048 (RealESRGAN 4x)
        "50": {
            "class_type": "ImageUpscaleWithModel",
            "inputs": {
                "upscale_model": ["13", 0],
                "image": ["41", 0],
            }
        },

        # === 최종 축소 + PixelArt 변환 ===
        # 60. ImageScale — 2048→128 lanczos (고품질 다운샘플링)
        "60": {
            "class_type": "ImageScale",
            "inputs": {
                "image": ["50", 0],
                "upscale_method": "lanczos",
                "width": GEN_SIZE,
                "height": GEN_SIZE,
                "crop": "disabled",
            }
        },
        # 61. SaveImage — 최종 128x128 이미지 (팔레트 미적용)
        "61": {
            "class_type": "SaveImage",
            "inputs": {"images": ["60", 0], "filename_prefix": "dots2p_" + unit_key}
        },
        # 62. PixelArtDetectorToImage — 픽셀 정량화
        "62": {
            "class_type": "PixelArtDetectorToImage",
            "inputs": {
                "images": ["60", 0],
                "reduce_palette": False,
                "reduce_palette_max_colors": 128,
            }
        },
        # 63. PixelArtLoadPalettes — 팔레트 로드 (필수 위젯 9개 모두 포함)
        "63": {
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
        # 64. PixelArtDetectorConverter — GAMEBOY 팔레트 적용
        "64": {
            "class_type": "PixelArtDetectorConverter",
            "inputs": {
                "images": ["60", 0],
                "paletteList": ["63", 0],
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
        # 65. SaveImage — GAMEBOY 팔레트 적용된 최종 픽셀아트
        "65": {
            "class_type": "SaveImage",
            "inputs": {"images": ["64", 0], "filename_prefix": "dots2p_" + unit_key + "_gameboy"}
        },
        # 66. PixelArtDetectorSave — webp 저장 (resize 128x128)
        "66": {
            "class_type": "PixelArtDetectorSave",
            "inputs": {
                "images": ["60", 0],
                "filename_prefix": "dots2p_" + unit_key + "_pixelart",
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
    """단일 유닛 2패스 생성."""
    print("[%s] 2패스 생성 중... (시드 %d→%d, 타겟 %dx%d)" % (
        unit_key, seed, seed + 1, GEN_SIZE, GEN_SIZE))
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
    ap = argparse.ArgumentParser(description="DOTS 픽셀아트 2패스 워크플로우 (inzaniak 가이드 기반)")
    ap.add_argument("--unit", choices=list(UNITS.keys()), help="생성할 유닛 (knight/archer)")
    ap.add_argument("--seed", type=int, default=None, help="시드")
    ap.add_argument("--batch", action="store_true", help="knight + archer 연속 생성")
    args = ap.parse_args()

    if args.batch:
        print("=== DOTS 2패스 일괄 생성 (128x128) ===")
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
