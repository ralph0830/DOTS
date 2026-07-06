class_name PaylineOverlay
extends Node2D
## 당첨 페이라인 시각화. EventBus.highlight_wins 로 결과를 받아 Line2D 로 그린다.
## 릴 영역(ReelArea) 자식으로 두어 로컬 좌표를 사용. reel_w/row_h 로 셀 중심 계산.

var reel_w: float = 180.0   # 심볼 크기(SYMBOL_SIZE)와 동일 — SlotMachineView 가 다시 설정하지만 기본값도 일치
var row_h: float = 180.0

var _lines: Array[Line2D] = []


func _ready() -> void:
	EventBus.highlight_wins.connect(_on_highlight)
	# 스핀이 시작되면 이전 당첨 라인을 즉시 지운다.
	EventBus.spin_started.connect(_on_spin_started)


func _on_spin_started(_bet: int) -> void:
	clear()


func _on_highlight(result: SpinResult) -> void:
	clear()
	# 페이라인별 고유 색상을 써서 여러 당첨 라인이 겹쳐도 서로 구분되게 한다.
	# 특히 4·5매치의 긴 선이 3매치 짧은 선에 묻히지 않도록 두껍게 + 둥근 끝.
	var paylines: Array = GameConfig.config.paylines
	for lw in result.line_wins:
		var line := Line2D.new()
		line.width = 16.0
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.default_color = Color(1.0, 0.85, 0.25, 0.95)   # 폴백 노랑
		# 당첨 라인의 페이라인 id 에 해당하는 고유 색상 사용(식별 용이).
		if lw.payline_id >= 0 and lw.payline_id < paylines.size():
			var pl: Payline = paylines[lw.payline_id]
			line.default_color = pl.debug_color
		line.z_index = 10   # 심볼·파티클 위에 표시
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
