class_name BattleFieldView
extends Control
## 상단 전투 영역 뷰 — Phase 7 임시 배경/라벨.
## 실제 유닛/적 렌더링은 BattleField(Node2D)가 담당. 여기선 영역 확보 + 시각적 분할선만.
## 레이아웃: 상단 1080×1056px (전체 1920의 55%).

const BATTLE_H := 1056.0   # 전투 영역 높이 (1920 × 0.55)
const LINE_Y := 528.0      # 전투 라인 중심 y (BATTLE_H / 2) — 유닛/적이 이 선 위에 배치됨


func _ready() -> void:
	# 상단 전투 영역 전체 채우기
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = -864.0   # 하단 864px(슬롯 영역)만큼 위로 당김 → 상단 1056px만 차지
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# 전투 영역 배경 (밝게 조정 — 파타폰 톤이지만 가독성 우선)
	draw_rect(Rect2(0.0, 0.0, 1080.0, BATTLE_H), Color(0.18, 0.15, 0.25, 1.0), true)
	# 전투 라인 (중앙 가로선 — 유닛/적이 지나다니는 줄, 더 밝게)
	draw_line(Vector2(40.0, LINE_Y), Vector2(1040.0, LINE_Y), Color(0.5, 0.45, 0.7, 0.8), 3.0)
	# 아군 기지 영역 표시 (좌단 — 초록 채우기 사각형 80×120)
	draw_rect(Rect2(20.0, LINE_Y - 60.0, 80.0, 120.0), Color(0.15, 0.5, 0.2, 0.9), false, 4.0)
	draw_rect(Rect2(24.0, LINE_Y - 56.0, 72.0, 112.0), Color(0.2, 0.6, 0.3, 0.3), true)
	# 적 포탈 영역 표시 (우단 — 빨간 채우기 사각형 80×120)
	draw_rect(Rect2(980.0, LINE_Y - 60.0, 80.0, 120.0), Color(0.6, 0.15, 0.15, 0.9), false, 4.0)
	draw_rect(Rect2(984.0, LINE_Y - 56.0, 72.0, 112.0), Color(0.7, 0.2, 0.2, 0.3), true)
	# 하단 분할선 (전투/슬롯 경계 — 밝은 네온 선으로 명확히 표시)
	draw_line(Vector2(0.0, BATTLE_H), Vector2(1080.0, BATTLE_H), Color(0.7, 0.6, 1.0, 1.0), 5.0)
	# 임시 라벨 (좌상단 — 밝게)
	_draw_label("⚔ BATTLE FIELD", Vector2(20.0, 30.0), 36, Color(0.85, 0.8, 1.0, 0.9))
	# 아군/적 라벨
	_draw_label("ALLY BASE", Vector2(15.0, LINE_Y + 80.0), 22, Color(0.3, 0.8, 0.4, 0.8))
	_draw_label("ENEMY PORTAL", Vector2(920.0, LINE_Y + 80.0), 22, Color(0.9, 0.3, 0.3, 0.8))


## 임시 텍스트 그리기 (Godot 4 draw_string 헬퍼).
func _draw_label(text: String, pos: Vector2, font_size: int, col: Color) -> void:
	var font := get_theme_default_font()
	if font != null:
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
