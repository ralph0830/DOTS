class_name PaylineOverlay
extends Node2D
## 당첨 페이라인 시각화. EventBus.highlight_wins 로 결과를 받아 Line2D 로 그린다.
## 릴 영역(ReelArea) 자식으로 두어 로컬 좌표를 사용. reel_w/row_h 로 셀 중심 계산.

var reel_w: float = 140.0
var row_h: float = 140.0

var _lines: Array[Line2D] = []


func _ready() -> void:
	EventBus.highlight_wins.connect(_on_highlight)
	EventBus.clear_highlights.connect(clear)
	# 스핀이 시작되면 이전 당첨 라인을 즉시 지운다.
	EventBus.spin_started.connect(_on_spin_started)


func _on_spin_started(_bet: int) -> void:
	clear()


func _on_highlight(result: SpinResult) -> void:
	clear()
	for lw in result.line_wins:
		var line := Line2D.new()
		line.width = 9.0
		line.default_color = Color(1.0, 0.85, 0.25, 0.92)
		line.z_index = 5
		for pos in lw.positions:
			line.add_point(_cell_center(pos))
		add_child(line)
		_lines.append(line)


func clear() -> void:
	for l in _lines:
		l.queue_free()
	_lines.clear()


func _cell_center(pos: Vector2i) -> Vector2:
	return Vector2(float(pos.x) * reel_w + reel_w * 0.5, float(pos.y) * row_h + row_h * 0.5)
