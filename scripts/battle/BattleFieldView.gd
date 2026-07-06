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
	# 전투 영역 배경 (어두운 배경 — 파타폰 톤)
	draw_rect(Rect2(0.0, 0.0, 1080.0, BATTLE_H), Color(0.08, 0.06, 0.12, 1.0), true)
	# 전투 라인 (중앙 가로선 — 유닛/적이 지나다니는 줄)
	draw_line(Vector2(40.0, LINE_Y), Vector2(1040.0, LINE_Y), Color(0.3, 0.25, 0.4, 0.6), 2.0)
	# 아군 기지 영역 표시 (좌단 — 초록 테두리 사각형 80×120)
	draw_rect(Rect2(20.0, LINE_Y - 60.0, 80.0, 120.0), Color(0.2, 0.6, 0.3, 0.5), false, 3.0)
	# 적 포탈 영역 표시 (우단 — 빨간 테두리 사각형 80×120)
	draw_rect(Rect2(980.0, LINE_Y - 60.0, 80.0, 120.0), Color(0.7, 0.2, 0.2, 0.5), false, 3.0)
	# 하단 분할선 (전투/슬롯 경계 — 밝은 선으로 명확히 표시)
	draw_line(Vector2(0.0, BATTLE_H), Vector2(1080.0, BATTLE_H), Color(0.6, 0.5, 0.8, 0.8), 4.0)
	# 임시 라벨 (좌상단)
	_draw_label("BATTLE FIELD", Vector2(20.0, 20.0), 32, Color(0.7, 0.65, 0.85, 0.8))


## 임시 텍스트 그리기 (Godot 4 draw_string 헬퍼).
func _draw_label(text: String, pos: Vector2, font_size: int, col: Color) -> void:
	var font := get_theme_default_font()
	if font != null:
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
