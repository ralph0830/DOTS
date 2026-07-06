"""
유니콘/룬 시드 탐색 — 각 8개 시드 생성, 불투명 픽셀 비율로 자동 품질 평가.
목표: 심볼이 충분히 크고 또렷하게 그려지는 시드 찾기 (불투명 픽셀 8% 이상).
"""
import subprocess, sys, os, time
from PIL import Image
import numpy as np

OUT = "/opt/ComfyUI/output"
SCRIPT = "/opt/ComfyUI/comfy_gem.py"

# 두 심볼 정의
TARGETS = {
    "unicorn": {
        "prompt": "cute baby unicorn, full body, big head with rainbow horn, chibi kawaii style, large centered, fills frame, white body with pink mane, solid pure white background, 16-bit pixel art, fantasy magical creature game icon",
        "seeds": [100, 200, 300, 400, 500, 600, 700, 800],
    },
    "rune": {
        "prompt": "large glowing magic rune stone, big purple crystal, glowing magic glyph, centered, fills frame, mystical aura, solid pure white background, 16-bit pixel art, fantasy RPG enchanted item game icon",
        "seeds": [100, 200, 300, 400, 500, 600, 700, 800],
    },
}

print("=" * 60)
print("유니콘/룬 시드 탐색 (각 8개)")
print("=" * 60)

results = {}
for sym, cfg in TARGETS.items():
    print("")
    print("--- " + sym + " ---")
    results[sym] = []
    for seed in cfg["seeds"]:
        prefix = sym + "_seed" + str(seed)
        t0 = time.time()
        r = subprocess.run(
            [sys.executable, SCRIPT,
             "--prompt", cfg["prompt"],
             "--out-size", "180", "--gen-size", "512",
             "--seed", str(seed), "--prefix", prefix, "--threshold", "235"],
            capture_output=True, text=True, timeout=200
        )
        elapsed = round(time.time() - t0, 1)
        if r.returncode != 0:
            print("  seed " + str(seed) + ": 실패 " + r.stderr[:80])
            continue
        # 투명 PNG에서 불투명 픽셀 비율 계산
        trans_path = OUT + "/" + prefix + "_transparent_180.png"
        if not os.path.exists(trans_path):
            print("  seed " + str(seed) + ": 파일 없음")
            continue
        im = Image.open(trans_path).convert("RGBA")
        arr = np.array(im)
        a = arr[:, :, 3]
        total = a.size
        opaque = (a >= 128).sum()  # 불투명 픽셀 (심볼 영역)
        ratio = opaque / total * 100
        # 색상 다양성 (심볼이 단조로운지)
        opaque_rgb = arr[a >= 128][:, :3]
        if len(opaque_rgb) > 0:
            unique_colors = len(np.unique(opaque_rgb // 32, axis=0))
        else:
            unique_colors = 0
        results[sym].append((seed, ratio, unique_colors, elapsed))
        print("  seed " + str(seed) + ": 불투명 " + str(round(ratio, 1)) + "% / 색상다양성 " + str(unique_colors) + " / " + str(elapsed) + "초")

# 최적 시드 선택 (불투명 비율 5~40% 범위에서 가장 높은 것)
print("")
print("=" * 60)
print("최적 시드 선택")
print("=" * 60)
for sym, rs in results.items():
    if not rs:
        print(sym + ": 후보 없음")
        continue
    # 불투명 5~40% 범위에서, 색상 다양성 높은 순
    valid = [r for r in rs if 5 <= r[1] <= 45]
    if valid:
        best = max(valid, key=lambda r: (r[2], r[1]))
    else:
        best = max(rs, key=lambda r: r[1])
    print(sym + " 최적: seed=" + str(best[0]) + " (불투명 " + str(round(best[1], 1)) + "%, 색상 " + str(best[2]) + ")")
    # 최적 시드를 표준 파일명으로 복사
    src = OUT + "/" + sym + "_seed" + str(best[0]) + "_transparent_180.png"
    dst = OUT + "/" + sym + "_transparent_180.png"
    import shutil
    shutil.copy(src, dst)
    print("  → 복사: " + sym + "_transparent_180.png")
