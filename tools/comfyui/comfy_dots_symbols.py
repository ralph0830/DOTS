"""
DOTS 심볼 7종 일괄 생성 — 귀엽고 아기자기한 도트 그래픽
comfy_gem.py 를 반복 호출하여 180x180 투명 PNG 7장 생성.
"""
import subprocess, sys, time

# DOTS 심볼별 프롬프트 (귀엽고 아기자기한 도트 스타일 통일)
SYMBOLS = [
    ("ruby", 42,
     "single red ruby gemstone, faceted crystal, glossy shine, sparkly highlight, centered composition, solid pure white background, 16-bit pixel art, cute kawaii game icon, fantasy RPG asset"),
    ("sapphire", 43,
     "single blue sapphire gem, faceted crystal, glossy shine, sparkly highlight, centered, solid pure white background, 16-bit pixel art, cute kawaii game icon, fantasy RPG asset"),
    ("emerald", 44,
     "single green emerald gemstone, hexagonal cut, glossy shine, sparkly, centered, solid pure white background, 16-bit pixel art, cute kawaii game icon, fantasy RPG asset"),
    ("dragon", 45,
     "cute baby dragon head, purple scales, big friendly eyes, chibi kawaii style, centered, solid pure white background, 16-bit pixel art, fantasy RPG creature icon"),
    ("unicorn", 500,
     "cute baby unicorn, full body, big head with rainbow horn, chibi kawaii style, large centered, fills frame, white body with pink mane, solid pure white background, 16-bit pixel art, fantasy magical creature game icon"),
    ("chest", 47,
     "small treasure chest, golden gold coins spilling, cute chibi style, centered, solid pure white background, 16-bit pixel art, fantasy RPG item icon"),
    ("rune", 300,
     "large glowing magic rune stone, big purple crystal, glowing magic glyph, centered, fills frame, mystical aura, solid pure white background, 16-bit pixel art, fantasy RPG enchanted item game icon"),
]

SCRIPT = "/opt/ComfyUI/comfy_gem.py"
OUT_SIZE = 180  # DOTS 심볼 셀 크기

print("=" * 60)
print("DOTS 심볼 7종 일괄 생성 (180x180 투명 PNG)")
print("=" * 60)
print("")

results = []
t_start = time.time()
for i, (name, seed, prompt) in enumerate(SYMBOLS, 1):
    print("[" + str(i) + "/7] " + name + " (시드 " + str(seed) + ") 생성 중...")
    sys.stdout.flush()
    t0 = time.time()
    r = subprocess.run(
        [sys.executable, SCRIPT,
         "--prompt", prompt,
         "--out-size", str(OUT_SIZE),
         "--seed", str(seed),
         "--prefix", name,
         "--threshold", "235"],
        capture_output=True, text=True, timeout=300
    )
    elapsed = time.time() - t0
    if r.returncode == 0:
        # 마지막 두 줄에서 파일 경로 추출
        last_lines = r.stdout.strip().split("\n")[-3:]
        ok = "투명" in (" ".join(last_lines))
        print("  완료 (" + str(round(elapsed, 1)) + "초)")
        results.append((name, True, round(elapsed, 1)))
    else:
        print("  실패: " + r.stderr[:150])
        print("  stdout: " + r.stdout[-200:])
        results.append((name, False, round(elapsed, 1)))
    print("")

total = time.time() - t_start
print("=" * 60)
print("전체 완료: " + str(round(total, 1)) + "초")
print("=" * 60)
ok = sum(1 for _, s, _ in results if s)
print("성공 " + str(ok) + "/7")
for name, success, t in results:
    mark = "OK" if success else "FAIL"
    print("  " + name + ": " + mark + " (" + str(t) + "초)")
