class_name MinimapView
extends Control
## 전투 필드 미니맵 뷰 (전투-슬롯 사이 얇은 가로 영역).
## 독립 노드로 관리 — 레이아웃/배경/구현을 다른 영역과 분리.
## 현재는 흰색 배경 플레이스홀더. 본진~적진 축소 표시(아군/적/보스 점)는 추후 구현.


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# 배경 white — 미니맵 구현 전 플레이스홀더 (영역 확인용).
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
