# DOTS 모바일 레이아웃 — EXPAND aspect 빈 공간 함정

> **발생일**: 2026-07-10 해결
> **대상**: `autoload/Layout.gd`, `scripts/view/SlotMachineView.gd`
> 관련 메모리: `godot-mobile-export-pitfalls` 섹션 8, [[dots-slot-progress]]

---

## 1. 증상

- **폰(Android)** 에서 릴 5×5 그리드 아래·하단 버튼 위에 빈 공간 발생.
- 빈 공간은 릴 배경(slot_bg 그라데이션)과 **동일한 색** — 버튼 영역(검정 단색)과 명확히 구분됨.
- **데스크톱 에디터는 정상** (폰 전용 버그).

## 2. 근본 원인

`project.godot` 설정:
```ini
window/size/viewport_width=1080
window/size/viewport_height=1920
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
```

`expand` + `canvas_items` 조합에서 **두 좌표계가 다르다**:

| 항목 | 값 | 비고 |
|---|---|---|
| `Window.content_scale_size` | `1080×1920` (design) | project 설정값, **고정** |
| `Control.size` (런타임) | `1080×2520` (window 물리) | EXPAND 가 design 을 window 로 늘림 |

Layout autoload 가 `content_scale_size(1920)`를 `_vp`로 사용하면, **Layout 비율 기반 anchor**(slot_top_ratio 등)가 실제 `Control.size(2520)`에 어긋나서 적용된다.

**추가 함정**: anchor 비율은 `SlotMachineView._ready`(vp=1920)에서 **한 번만 설정**된다. `Layout._process`가 그 후 vp를 2520으로 갱신해도 **anchor는 재설정되지 않는다**.

### 수치 계산 (빈이 왜 337px 인가)

```
ReelArea anchor diff = slot_h / vp.y = 1080 / 1920 = 0.5625   ← 1920 기준 비율(고정)
ReelArea.size        = SlotMachineView.size(2520) × 0.5625     = 1417.5
릴 그리드            = cell_size(216) × 5                       = 1080
start_y              = (area_h - reel_grid) × 0.5              = 0   (위 정렬)
→ 아래 빈 = 1417.5 - 1080 = 337.5px
```

## 3. 진단법

레이아웃 갱신 함수에서 Layout 값과 실제 Control size 를 동시에 출력:

```gdscript
print("[REEL DIAG] vp=%s ReelArea=%s" % [str(Layout.viewport()), str(_reel_area.size)])
```

| 출력 | 판정 |
|---|---|
| `vp=(1080,1920) ReelArea=(1080,1417.5)` | ❌ 비정상 — 빈 있음 |
| `vp=(1080,2520) ReelArea=(1080,1080)` | ✅ 정상 — 릴 그리드와 일치 |

`vp.y` 와 `ReelArea.size.y` 가 `0.5625` 비율이 아니라면(= `vp.y × 0.5625 ≠ ReelArea.size.y`), 절대 좌표 강제가 정상 동작 중.

## 4. 해결 (2단계)

### 4-1. `Layout._vp = win.size` (content_scale_size 대신)

```gdscript
# autoload/Layout.gd
func _process(_delta: float) -> void:
    var win := get_window()
    if win != null:
        var s: Vector2 = win.size   # ★ Control.size 와 동일 (EXPAND)
        if s.x > 0.0 and s.y > 0.0:
            _vp = s
            return
```

`Layout._vp` 를 Control 실제 size 와 같게 만들어, 비율 계산 기준을 통일.

### 4-2. 자식 영역 절대 좌표 강제 (anchor 비율 회피)

anchor 비율은 부모 size 에 의존하므로, **anchor 0(PRESET_TOP_LEFT) + 절대 position/size** 로 전환:

```gdscript
# 생성 시
node.set_anchors_preset(Control.PRESET_TOP_LEFT)   # anchor = (0,0,0,0)
# vp 변화마다 갱신
node.position = Vector2(0.0, Layout.slot_top())
node.size = Vector2(vp.x, Layout.slot_h())
```

`SlotMachineView._apply_area_rects()` 가 이 패턴으로 `slot_bg` / `minimap` / `_reel_area` 를 Layout 절대 좌표로 강제한다.

## 5. 부가 효과

`Layout._vp` 가 1920 → 2520 로 바뀌면서 동적 분배가 실제 비율로 재계산:
- `battle_h`: 364px → **815px** 자동 확장 ("전투 영역이 작아졌다" 문제도 같이 해결).

## 6. 재발 방지 체크리스트

레이아웃 관련 코드를 수정할 때 반드시 확인:

- [ ] EXPAND aspect 모바일에서 Layout 비례 좌표는 `_vp = win.size` 기준 (`content_scale_size` 아님).
- [ ] 레이아웃 영역 노드(slot_bg/minimap/ReelArea 등)는 anchor 비율 대신 **절대 position/size**(`PRESET_TOP_LEFT` + 강제 갱신).
- [ ] vp 변화(폴드·회전·해상도) 대응은 `_process`에서 `Layout.viewport()` 변화 감지 → `_apply_area_rects()` 재실행.
- [ ] 데스크톱이 정상이어도 **폰 APK + logcat** 으로 검증 (window 비율이 design 과 달라야 버그 재현).
- [ ] 전체화면 오버레이(GameOverOverlay/LevelUpUI)는 `set_anchors_and_offsets_preset(FULL_RECT)` 유지(vp 무관, 별도 규칙 — [[godot-mobile-export-pitfalls]] 섹션 7).

## 7. 관련 파일

| 파일 | 역할 |
|---|---|
| `autoload/Layout.gd` | `_vp = win.size` 로 EXPAND 대응 |
| `scripts/view/SlotMachineView.gd` | `_apply_area_rects()` 절대 좌표 강제 + `_layout_reels()` 호출 |
| `project.godot` | `window/stretch/aspect = "expand"` 설정 원인 |
| `scenes/slot/SlotMachine.tscn` | root `SlotMachineView` FULL_RECT (size = window 물리) |
