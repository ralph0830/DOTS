"""
DOTS 유닛 스프라이트 생성기 — Illustrious-XL + LoRA + IP-Adapter (캐릭터 일관성).

★ 핵심: IP-Adapter 로 idle 프레임을 참조하여 attack/hit 프레임 생성 → 동일 캐릭터 보장.

파이프라인 (2단계):
  1단계 idle:  Checkpoint + LoRA → KSampler → MedianFixer → idle.png (기준 프레임)
  2단계 attack/hit:  위 + idle.png → LoadImage → CLIPVisionEncode → IPAdapterAdvanced
    → KSampler 가 IP-Adapter가 적용된 모델 사용 → 동일 캐릭터의 다른 모션

IP-Adapter 효과:
  - 캐릭터 디자인(갑옷 색, 투구 모양, 체형)이 idle 기준으로 고정
  - 모션(attack/hit)은 프롬프트로 제어
  - weight=0.7~0.9 로 캐릭터 일관성 vs 모션 다양성 트레이드오프 조절

사용법:
  python3 comfy_dots_units.py --unit knight --all-motions   # idle→attack→hit 순차
  python3 comfy_dots_units.py --unit knight --motion idle   # idle만
  python3 comfy_dots_units.py --all                          # 7종×3모션 일괄
"""
import json, urllib.request, time, sys, argparse, os

SERVER = "http://localhost:8188"
OUTPUT_DIR = "/opt/ComfyUI/output"

# --- 유닛 정의 ---
UNIT_PROMPTS = {
    "knight": {
        "subject": "heavy plate armor, blue tabard, helmet with plume, holding sword, human",
        "is_ally": True, "seed": 1937491775,
    },
    "archer": {
        "subject": "green hooded cloak, leather armor, quiver of arrows, holding longbow, human, elf",
        "is_ally": True, "seed": 1937491888,
    },
    "mage": {
        "subject": "purple robes, pointy hat, glowing magic circle, holding magic staff, human",
        "is_ally": True, "seed": 1937491999,
    },
    "minion": {
        "subject": "small cute goblin minion, round chubby body, simple loincloth, holding wooden club, friendly",
        "is_ally": True, "seed": 1937492111,
    },
    "goblin": {
        "subject": "sharp teeth, ragged clothing, hunched posture, holding rusty dagger, menacing, goblin",
        "is_ally": False, "seed": 1937492222,
    },
    "orc": {
        "subject": "green skin, tusks, muscular, iron armor, holding heavy axe, menacing, orc",
        "is_ally": False, "seed": 1937492333,
    },
    "boss": {
        "subject": "horns, dark armor, large wings, holding flaming weapon, intimidating, demon",
        "is_ally": False, "seed": 1937492444,
    },
}

# 모션 정의 — idle 은 기준, attack/hit 는 idle 을 IP-Adapter 로 참조.
POSES = {
    "idle":   {"pose": "standing idle pose, relaxed, breathing, neutral expression", "seed_offset": 0},
    "attack": {"pose": "mid-attack pose, swinging weapon, dynamic action, aggressive", "seed_offset": 1},
    "hit":    {"pose": "taking damage pose, recoiling backward, pain expression, stumbled", "seed_offset": 2},
}

# --- Civitai 메타데이터 ---
PROMPT_PREFIX = (
    "best quality, masterpiece, sfw, n0m0, "
    "pixel_character_sprite, pxlchrctrsprt, sprite, sprite art, "
    "pixel, (pixel art:1.5), retro game, retro, vibrant colors, pixelated, "
    "(chibi:1.5), from side, looking away, "
)
PROMPT_SUFFIX = (
    ", facing left, white background, solo, centered composition, "
    "close-up shot, view from aside, full body"
)
NEGATIVE = (
    "worst quality, lowres, text, watermark, pointy ears, mole, 3d, nipples, "
    "source_anime, nude, nsfw, skindentation, extra head, artist, patreon, koma, "
    "furry, futanari, red hair, pink hair, "
    "sprite sheet, multiple characters, grid, split screen, duplicate"
)

SAMPLER = "euler_ancestral"
CFG_SCALE = 7.0
STEPS = 31
CLIP_SKIP = -2

# --- 해상도 ---
GEN_SIZE = 768
GRID_SIZE = 12
FINAL_PX = 64

# --- IP-Adapter 설정 ---
IPADAPTER_MODEL = "ip-adapter-plus_sdxl_vit-h.safetensors"
CLIP_VISION_MODEL = "CLIP-ViT-H-14.safetensors"
IPADAPTER_WEIGHT = 0.85   # 0.0=참조없음, 1.0=완전고정. 0.85=캐릭터 고정+모션 자유.


def build_prompt(unit_key: str, motion: str = "idle") -> str:
    u = UNIT_PROMPTS[unit_key]
    p = POSES[motion]
    return f"{PROMPT_PREFIX}{u['subject']}, {p['pose']}{PROMPT_SUFFIX}"


def _common_nodes(prompt_text, negative_text, seed, steps):
    """공통 노드: Checkpoint + LoRA + CLIPSetLastLayer + Latent + CLIP±.
    반환: (api_dict, lora_model_ref, lora_clip_ref).
    lora_model_ref/clip_ref 는 KSampler/IPAdapter 입력으로 사용."""
    api = {
        "1": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": "Illustrious-XL-v2.0.safetensors"},
        },
        "2": {
            "class_type": "LoraLoader",
            "inputs": {
                "model": ["1", 0],
                "clip": ["1", 1],
                "lora_name": "game_character_sprites_lora.safetensors",
                "strength_model": 0.8,
                "strength_clip": 0.8,
            },
        },
        "10": {
            "class_type": "CLIPSetLastLayer",
            "inputs": {"clip": ["2", 1], "stop_at_clip_layer": CLIP_SKIP},
        },
        "3": {
            "class_type": "EmptyLatentImage",
            "inputs": {"width": GEN_SIZE, "height": GEN_SIZE, "batch_size": 1},
        },
        "4": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": prompt_text, "clip": ["10", 0]},
        },
        "5": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": negative_text, "clip": ["10", 0]},
        },
    }
    return api, ["2", 0], ["2", 1]


def _output_nodes(model_ref, latent_ref, positive_ref, negative_ref, seed, prefix):
    """출력 노드: KSampler → VAEDecode → GridMedianFixer → SaveImage.
    model_ref: KSampler model 입력 (IP-Adapter 적용 시 IPAdapter 노드, 아니면 LoRA 직접)."""
    out = {
        "6": {
            "class_type": "KSampler",
            "inputs": {
                "model": model_ref,
                "positive": positive_ref,
                "negative": negative_ref,
                "latent_image": latent_ref,
                "seed": seed,
                "steps": STEPS,
                "cfg": CFG_SCALE,
                "sampler_name": SAMPLER,
                "scheduler": "normal",
                "denoise": 1.0,
            },
        },
        "7": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["6", 0], "vae": ["1", 2]},
        },
        "8": {
            "class_type": "GridMedianFixer",
            "inputs": {"image": ["7", 0], "grid_size": GRID_SIZE},
        },
        "9": {
            "class_type": "SaveImage",
            "inputs": {"images": ["8", 1], "filename_prefix": prefix},
        },
    }
    return out


def build_api_idle(prompt_text, negative_text, seed, steps, prefix):
    """1단계: idle 프레임 생성 (IP-Adapter 없음). 기준 캐릭터 확립."""
    api, model_ref, _ = _common_nodes(prompt_text, negative_text, seed, steps)
    api.update(_output_nodes(model_ref, ["3", 0], ["4", 0], ["5", 0], seed, prefix))
    return api


def build_api_with_ipadapter(prompt_text, negative_text, seed, steps, prefix, ref_image_filename):
    """2단계: attack/hit 프레임 생성 — idle 이미지를 IP-Adapter 로 주입 (캐릭터 일관성).

    ★ 사용자 SpriteSheet 워크플로우 기반 — 빠진 노드 4종 추가:
      - Image Remove Background (rembg): 흰 배경 제거 → 캐릭터만 추출 (isnet-anime)
      - PrepImageForClipVision:          IP-Adapter 입력 전처리 (LANCZOS 리사이즈 + pad)
      - IPAdapterUnifiedLoader:          PLUS (high strength) 프리셋 자동 적용
      - ControlNet OpenPose:             (선택) 자세 제어 — 현재는 미사용 (스켈레톤 이미지 필요)

    노드 체인:
      20: LoadImage (idle.png)
      25: Image Remove Background (rembg) ← ★ 추가 (흰 배경 제거, isnet-anime 모델)
      21: PrepImageForClipVision (LANCZOS, pad) ← 전처리된(배경제거) 이미지
      22: IPAdapterUnifiedLoader (PLUS high strength)
      23: IPAdapterAdvanced (weight=0.85, image=전처리된 idle)
      KSampler.model = [23, 0]
    """
    api, model_ref, _ = _common_nodes(prompt_text, negative_text, seed, steps)

    # idle 이미지 로드 — ComfyUI input 디렉토리.
    api["20"] = {
        "class_type": "LoadImage",
        "inputs": {"image": ref_image_filename},
    }
    # ★ PrepImageForClipVision — IP-Adapter 입력 전처리 (사용자 SpriteSheet 노드 38 과 동일).
    #   LANCZOS 보간 + pad (비율 유지하며 패딩) → CLIP 비전에 최적화된 정사각형.
    #   배경제거(rembg)는 onnxruntime 백엔드 문제로 비활성화 — PIL 후처리로 대체 예정.
    api["21"] = {
        "class_type": "PrepImageForClipVision",
        "inputs": {
            "image": ["20", 0],            # LoadImage 직접 입력 (배경제거 생략)
            "interpolation": "LANCZOS",
            "crop_position": "pad",
            "sharpening": 0.0,
        },
    }
    # ★ IPAdapterUnifiedLoader — PLUS (high strength) 프리셋 (사용자 SpriteSheet 노드 10/43 과 동일).
    api["22"] = {
        "class_type": "IPAdapterUnifiedLoader",
        "inputs": {
            "model": model_ref,
            "preset": "PLUS (high strength)",
        },
    }
    # ★ IPAdapterAdvanced — 배경제거+전처리된 idle 이미지로 캐릭터 고정.
    api["23"] = {
        "class_type": "IPAdapterAdvanced",
        "inputs": {
            "model": ["22", 0],            # UnifiedLoader 가 반환한 모델
            "ipadapter": ["22", 1],         # UnifiedLoader 가 반환한 ipadapter
            "image": ["21", 0],             # ★ PrepImageForClipVision 전처리된 이미지
            "weight": IPADAPTER_WEIGHT,
            "weight_type": "linear",
            "combine_embeds": "concat",
            "start_at": 0.0,
            "end_at": 1.0,
            "embeds_scaling": "V only",
        },
    }
    # KSampler 의 model 을 IP-Adapter 적용 모델([23, 0])로 교체.
    api.update(_output_nodes(["23", 0], ["3", 0], ["4", 0], ["5", 0], seed, prefix))
    return api


def submit_and_wait(prompt_api: dict, timeout_s: int = 300):
    data = json.dumps({"prompt": prompt_api}).encode("utf-8")
    req = urllib.request.Request(
        SERVER + "/prompt", data=data, headers={"Content-Type": "application/json"}
    )
    try:
        resp = json.loads(urllib.request.urlopen(req, timeout=30).read())
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        return None, {"http_error": e.code, "body": body[:800]}
    if "error" in resp:
        return None, resp
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
            imgs = []
            for o in outputs.values():
                if "images" in o:
                    imgs.extend(o["images"])
            return {
                "elapsed": round(time.time() - t0, 1),
                "status": status,
                "images": imgs,
                "prompt_id": pid,
            }, None
    return None, {"timeout": True, "elapsed": timeout_s}


def generate_idle(unit_key: str, seed: int, prefix: str):
    """idle 프레임 생성 + 출력 파일명 반환 (후속 IP-Adapter 참조용)."""
    prompt_text = build_prompt(unit_key, "idle")
    api = build_api_idle(prompt_text, NEGATIVE, seed, STEPS, prefix)

    side = "아군(좌향→flip)" if UNIT_PROMPTS[unit_key]["is_ally"] else "적(좌향)"
    print(f"[{unit_key}/idle] 시드 {seed} | {side}")
    sys.stdout.flush()

    t0 = time.time()
    result, err = submit_and_wait(api, timeout_s=300)
    elapsed = round(time.time() - t0, 1)
    if err:
        print(f"  실패 ({elapsed}초): {json.dumps(err, ensure_ascii=False)[:400]}")
        return None
    print(f"  완료 ({elapsed}초)")
    # SaveImage 출력 파일명 추출 (IP-Adapter 참조용).
    if result["images"]:
        fname = result["images"][0]["filename"]
        subfolder = result["images"][0].get("subfolder", "")
        ref_path = f"{subfolder}/{fname}" if subfolder else fname
        print(f"  → {fname}")
        # ★ LoadImage 노드가 input/ 디렉토리에서만 파일을 찾음 → output/ 에서 복사.
        src = os.path.join(OUTPUT_DIR, fname)
        dst = os.path.join("/opt/ComfyUI/input", fname)
        if os.path.exists(src):
            import shutil
            shutil.copy2(src, dst)
            print(f"  → input/ 복사 완료 (IP-Adapter 참조용)")
        return ref_path
    return None


def generate_motion_with_ref(unit_key: str, motion: str, seed: int, prefix: str, ref_image: str):
    """attack/hit 프레임 생성 — idle 이미지를 IP-Adapter 로 참조하여 캐릭터 일관성 확보."""
    prompt_text = build_prompt(unit_key, motion)
    api = build_api_with_ipadapter(prompt_text, NEGATIVE, seed, STEPS, prefix, ref_image)

    print(f"[{unit_key}/{motion}] 시드 {seed} | IP-Adapter 참조: {ref_image}")
    sys.stdout.flush()

    t0 = time.time()
    result, err = submit_and_wait(api, timeout_s=300)
    elapsed = round(time.time() - t0, 1)
    if err:
        print(f"  실패 ({elapsed}초): {json.dumps(err, ensure_ascii=False)[:400]}")
        return False
    print(f"  완료 ({elapsed}초)")
    for img in result["images"]:
        print(f"  → {img['filename']}")
    return True


def generate_unit_all_motions(unit_key: str):
    """유닛 1종의 3모션 생성: idle 먼저 → attack/hit 는 idle 참조."""
    u = UNIT_PROMPTS[unit_key]
    print(f"\n=== {unit_key}: idle → attack → hit (IP-Adapter 일관성) ===")

    # 1단계: idle 생성 (기준 프레임).
    idle_prefix = f"dots_unit_{unit_key}_idle"
    idle_seed = u["seed"]
    ref_image = generate_idle(unit_key, idle_seed, idle_prefix)
    if ref_image is None:
        print(f"  idle 실패 — {unit_key} 중단")
        return [("idle", False), ("attack", False), ("hit", False)]

    # 2단계: attack 생성 (idle 참조).
    attack_prefix = f"dots_unit_{unit_key}_attack"
    attack_seed = u["seed"] + POSES["attack"]["seed_offset"]
    attack_ok = generate_motion_with_ref(unit_key, "attack", attack_seed, attack_prefix, ref_image)

    # 3단계: hit 생성 (idle 참조).
    hit_prefix = f"dots_unit_{unit_key}_hit"
    hit_seed = u["seed"] + POSES["hit"]["seed_offset"]
    hit_ok = generate_motion_with_ref(unit_key, "hit", hit_seed, hit_prefix, ref_image)

    return [("idle", True), ("attack", attack_ok), ("hit", hit_ok)]


def main():
    ap = argparse.ArgumentParser(
        description="DOTS 유닛 스프라이트 — IP-Adapter 캐릭터 일관성 파이프라인"
    )
    ap.add_argument("--unit", help="단일 유닛 (knight/archer/mage/minion/goblin/orc/boss)")
    ap.add_argument("--motion", default="idle", help="모션 (idle/attack/hit) — --unit 과 함께, IP-Adapter 없이 단독 생성")
    ap.add_argument("--all-motions", action="store_true", help="유닛 1종 idle→attack→hit (IP-Adapter 일관성)")
    ap.add_argument("--all", action="store_true", help="7종 × 3모션 전체 일괄")
    args = ap.parse_args()

    if args.all:
        print("=" * 60)
        print("DOTS 유닛 7종 × 3모션 — IP-Adapter 일관성 파이프라인")
        print("=" * 60)
        all_results = []
        for i, key in enumerate(UNIT_PROMPTS, 1):
            print(f"\n[{i}/7] {key}")
            motions = generate_unit_all_motions(key)
            all_results.append((key, motions))
        print("\n" + "=" * 60)
        total_ok = sum(1 for _, ms in all_results for _, ok in ms if ok)
        total = sum(len(ms) for _, ms in all_results)
        print(f"전체: {total_ok}/{total} 프레임")
        for key, ms in all_results:
            motions_str = " ".join(f"{m}:{'OK' if ok else 'X'}" for m, ok in ms)
            print(f"  {key}: {motions_str}")
        return

    if args.all_motions and args.unit:
        generate_unit_all_motions(args.unit)
        return

    if args.unit and args.motion:
        # 단일 모션 단독 생성 (IP-Adapter 없음 — idle 전용 또는 테스트용).
        u = UNIT_PROMPTS[args.unit]
        p = POSES[args.motion]
        seed = u["seed"] + p["seed_offset"]
        prefix = f"dots_unit_{args.unit}_{args.motion}"
        prompt_text = build_prompt(args.unit, args.motion)
        api = build_api_idle(prompt_text, NEGATIVE, seed, STEPS, prefix)
        print(f"[{args.unit}/{args.motion}] 시드 {seed} (단독, IP-Adapter 없음)")
        result, err = submit_and_wait(api, timeout_s=300)
        if err:
            print(f"실패: {json.dumps(err, ensure_ascii=False)[:400]}")
        else:
            print(f"완료 ({result['elapsed']}초)")
            for img in result["images"]:
                print(f"  → {img['filename']}")
        return

    ap.print_help()


if __name__ == "__main__":
    main()
