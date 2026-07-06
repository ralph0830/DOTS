"""
새 투명변환 알고리즘 검증 — flood-fill 기반 배경 검출 (순수 numpy, scipy 무의존).
배경(순백) 영역만 투명화, 심볼 내부 하이라이트는 불투명 유지.
"""
import numpy as np
from PIL import Image
from collections import deque
import os, glob


def make_transparent_floodfill(solid_path, out_path, bg_threshold=235, feather=2):
    img = Image.open(solid_path).convert("RGB")
    arr = np.array(img).astype(np.float32)
    h, w = arr.shape[:2]
    is_bg_color = np.all(arr >= bg_threshold, axis=2)

    # BFS flood-fill: 4모서리에서 시작
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

    # 순수 numpy 페더링: bg_mask를 N번 팽창 → 경계 영역 구하고 부분 투명
    alpha = np.where(bg_mask, 0.0, 255.0)
    if feather > 0:
        # 반복 팽창으로 경계 영역 계산
        cur = bg_mask.copy()
        edge_levels = []
        for i in range(feather):
            # 4방향 팽창 (numpy roll 기반)
            dil = cur.copy()
            dil[1:, :] |= cur[:-1, :]; dil[:-1, :] |= cur[1:, :]
            dil[:, 1:] |= cur[:, :-1]; dil[:, :-1] |= cur[:, 1:]
            new_edge = dil & ~cur  # 새로 추가된 픽셀
            edge_levels.append(new_edge)
            cur = dil
        # 각 페더 레벨: 레벨 0(가장 바깥)=가장 투명, 증가할수록 불투명
        for i, edge in enumerate(edge_levels):
            ys, xs = np.where(edge)
            if len(ys) == 0:
                continue
            t = (i + 1) / (feather + 1)  # 0~1
            # 경계 픽셀 밝기 고려: 밝을수록 더 투명
            brightness = arr[ys, xs].min(axis=1)
            # bg_threshold~255 범위를 알파 0~255*t 로 매핑
            ratio = np.clip((255.0 - brightness) / (255.0 - bg_threshold), 0, 1)
            alpha[ys, xs] = 255.0 * t * ratio

    rgba = np.dstack([arr, alpha]).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(out_path)
    return bg_mask.sum(), int((alpha == 0).sum()), int(((alpha > 0) & (alpha < 255)).sum()), int((alpha == 255).sum())


print("=== 새 알고리즘(flood-fill) 검증 ===")
print("")
solids = sorted(glob.glob("/opt/ComfyUI/output/*_solid_180.png"))
for s in solids:
    name = os.path.basename(s).replace("_solid_180.png", "")
    out = "/tmp/newtrans_" + name + ".png"
    bg, t0, tmid, t255 = make_transparent_floodfill(s, out, bg_threshold=235, feather=2)
    total = t0 + tmid + t255
    print(name + ":")
    print("  배경=" + str(bg) + " / 투명=" + str(t0) + " / 중간=" + str(tmid) + " (" + str(round(tmid/total*100, 1)) + "%) / 불투명=" + str(t255))
print("")
print("그리드 비교용 저장...")
# 새 변환 결과 7종을 그리드로
sym_order = ["ruby", "sapphire", "emerald", "dragon", "unicorn", "chest", "rune"]
cell = 180; cols = 4; rows = 2
grid = Image.new("RGBA", (cols * cell, rows * cell), (40, 40, 40, 255))
for i, s in enumerate(sym_order):
    p = "/tmp/newtrans_" + s + ".png"
    if os.path.exists(p):
        im = Image.open(p).convert("RGBA")
        grid.paste(im, ((i % cols) * cell, (i // cols) * cell), im)
grid.save("/tmp/newtrans_grid.png")
print("그리드 저장: /tmp/newtrans_grid.png " + str(grid.size))
