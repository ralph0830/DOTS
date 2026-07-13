class_name PaylineOverlay
extends Node2D
## 당첨 페이라인 시각화. EventBus.highlight_wins 로 결과를 받아 Line2D 로 그린다.
## 릴 영역(ReelArea) 자식으로 두어 로컬 좌표를 사용. reel_w/row_h 로 셀 중심 계산.
## 당첨 라인은 5초 후 자동 소멸(WIN_HOLD). BET 변경 시 예시 라인 얇게 3초(PREVIEW_HOLD).

const WIN_HOLD: float = 5.0       # 당첨 라인 표시 지속(초) — 이후 자동 소멸
const PREVIEW_HOLD: float = 4.0   # BET 예시 라인 표시 지속(초)
const PREVIEW_WIDTH: float = 6.0  # 예시 라인 두께
const PREVIEW_ALPHA: float = 0.8  # 예시 라인 투명도(점멸 후 유지)

var reel_w: float = 180.0   # 심볼 크기(SYMBOL_SIZE)와 동일 — SlotMachineView 가 다시 설정하지만 기본값도 일치
var row_h: float = 180.0

var _lines: Array[Line2D] = []            # 당첨 라인
var _preview_lines: Array[Line2D] = []    # BET 예시 라인
var _jackpot_flash: float = 0.0   # 잭팟 시 슬롯 테두리 번쩍


func _ready() -> void:
	EventBus.highlight_wins.connect(_on_highlight)
	EventBus.spin_started.connect(_on_spin_started)
	EventBus.jackpot_won.connect(_on_jackpot)
	EventBus.bet_level_changed.connect(_on_bet_level_changed)
	EventBus.auto_spin_changed.connect(_on_auto_spin_changed)
	set_process(true)
	# 시작 시 초기 bet_level 예시 라인 표시(bet_level_changed 는 시작 시 emit 안 됨).
	call_deferred("_show_initial_preview")


func _show_initial_preview() -> void:
	_show_preview(WalletManager.bet_level)


func _on_jackpot(_tier: int, _amount: int) -> void:
	_jackpot_flash = 1.0


func _process(delta: float) -> void:
	if _jackpot_flash > 0.0:
		_jackpot_flash = maxf(0.0, _jackpot_flash - delta * 1.5)
		queue_redraw()


func _draw() -> void:
	# 잭팟 시 슬롯 영역(5릴×3행) 외곽 테두리 번쩍.
	if _jackpot_flash > 0.0:
		var w := reel_w * 5.0
		var h := row_h * 3.0
		var col := Color(1.0, 0.9, 0.2).lerp(Color.WHITE, _jackpot_flash)
		draw_rect(Rect2(-4.0, -4.0, w + 8.0, h + 8.0), col, false, 8.0)


func _on_spin_started(_bet: int) -> void:
	clear()
	_clear_preview()


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
	# 당첨 라인/심볼 5초 후 자동 소멸(다음 스핀 전까지).
	get_tree().create_timer(WIN_HOLD).timeout.connect(clear)


## BET 변경 시 활성 페이라인 예시 얇게 표시.
func _on_bet_level_changed(level: int) -> void:
	_show_preview(level)


## AUTO 시작/종료 시 예시 라인 제거.
func _on_auto_spin_changed(_enabled: bool, _remaining: int) -> void:
	_clear_preview()


func _show_preview(level: int) -> void:
	_clear_preview()
	var count: int = WalletManager.payline_count_for(level)
	var paylines: Array = GameConfig.config.paylines
	var n: int = mini(count, paylines.size())
	for i in range(n):
		var pl: Payline = paylines[i]
		var line := Line2D.new()
		line.width = PREVIEW_WIDTH
		line.default_color = pl.debug_color
		line.modulate.a = PREVIEW_ALPHA
		line.z_index = 5
		# ★ bet_level별 활성 릴만 — 3×3=릴1,2,3 / 4×3=1,2,3,4 / 5×3=0,1,2,3,4.
		#   range(5) 로 그리면 저단계(3×3)에서도 5릴 라인이 빠져나가는 버그.
		var active_reels: Array = WalletManager.active_reels_for(level)
		for r in active_reels:
			var ri: int = int(r)
			line.add_point(_cell_center(Vector2i(ri, pl.get_row(ri))))
		add_child(line)
		_preview_lines.append(line)
		# 천천히 계속 점멸(SPIN/AUTO 전까지) — 부드러운 사인 파형, 무한 루프.
		var tw := create_tween()
		tw.set_loops(0)   # 0 = 무한
		tw.set_trans(Tween.TRANS_SINE)
		tw.tween_property(line, "modulate:a", 0.15, 0.9)
		tw.tween_property(line, "modulate:a", PREVIEW_ALPHA, 0.9)


func clear() -> void:
	for l in _lines:
		l.queue_free()
	_lines.clear()


func _clear_preview() -> void:
	for l in _preview_lines:
		l.queue_free()
	_preview_lines.clear()


func _cell_center(pos: Vector2i) -> Vector2:
	return Vector2(float(pos.x) * reel_w + reel_w * 0.5, float(pos.y) * row_h + row_h * 0.5)
