class_name SlotMachineView
extends Control
## 슬롯머신 뷰 오케스트레이터 + 이펙트 통합 지점.
## 코어 SlotMachine + ReelView[5] + PaylineOverlay + 이펙트(BackgroundFX/WinEffects/FloatingText) 를 연결.
## 코어-이펙트는 EventBus 만 사용(느슨한 결합). 빅윈 시 릴 영역 진동.

const REEL_W := 180.0
const ROW_H := 180.0
const MIN_SPIN_TIME := 0.5      # 최소 스핀 시간(감속 전)
const REEL_STOP_DELAY := 0.18   # 릴 간 정지 간격

var _core: SlotMachine
var _reel_area: Control
var _reels: Array[ReelView] = []
var _paylines: PaylineOverlay
var _reel_area_origin: Vector2 = Vector2.ZERO   # 진동 후 복원용
var _grid: Array = []
var _next_stop: int = -1
var _stop_timer: float = 0.0


func _ready() -> void:
	_build_layout()
	_setup_core()
	_setup_reels()
	WalletManager.initialize(GameConfig.config)
	JackpotSystem.initialize(GameConfig.config)
	EventBus.spin_requested.connect(_on_spin_requested)
	EventBus.highlight_wins.connect(_on_highlight)
	EventBus.big_win.connect(_on_big_win)


func _build_layout() -> void:
	# 다이내믹 배경 셰이더
	var bg := BackgroundFX.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# 릴 영역
	_reel_area = Control.new()
	_reel_area.name = "ReelArea"
	add_child(_reel_area)
	# 페이라인 오버레이(릴 영역 자식 → 로컬 좌표)
	_paylines = PaylineOverlay.new()
	_paylines.reel_w = REEL_W
	_paylines.row_h = ROW_H
	_reel_area.add_child(_paylines)
	# 당첨 파티클(릴 영역 로컬 좌표 = winning_positions 변환 기준)
	var win_fx := WinEffects.new()
	_reel_area.add_child(win_fx)
	# 당첨 금액 플로팅 텍스트
	var floating := FloatingText.new()
	_reel_area.add_child(floating)
	# 잭팟 전체화면 연출
	var jackpot_fx := preload("res://scenes/slot/JackpotOverlay.tscn").instantiate()
	add_child(jackpot_fx)
	# HUD
	var hud := preload("res://scenes/slot/HUD.tscn").instantiate()
	add_child(hud)


func _setup_core() -> void:
	_core = SlotMachine.new()
	add_child(_core)
	_core.initialize(GameConfig.config)
	_core.spin_complete.connect(_on_spin_complete)


func _setup_reels() -> void:
	var config := GameConfig.config
	for i in range(config.reel_count):
		var reel: ReelView = preload("res://scenes/slot/Reel.tscn").instantiate()
		reel.reel_index = i
		reel.configure(config.reels[i].symbols)
		reel.reel_stopped.connect(_on_reel_stopped)
		_reel_area.add_child(reel)
		_reels.append(reel)
	_layout_reels()


func _layout_reels() -> void:
	var vp := get_viewport_rect().size
	var total_w := REEL_W * float(_reels.size())
	var start_x := (vp.x - total_w) * 0.5
	var start_y := (vp.y - ROW_H * 3.0) * 0.5
	_reel_area.position = Vector2(start_x, start_y)
	_reel_area_origin = _reel_area.position
	_reel_area.size = Vector2(total_w, ROW_H * 3.0)
	for i in range(_reels.size()):
		_reels[i].position = Vector2(float(i) * REEL_W, 0.0)


# --- 스핀 흐름 ---

func _on_spin_requested() -> void:
	for reel in _reels:   # 이전 당첨 하이라이트 제거
		reel.clear_highlights()
	_core.request_spin()


func _on_spin_complete(grid: Array) -> void:
	_grid = grid
	for reel in _reels:
		reel.start_spin()
	_next_stop = 0
	_stop_timer = MIN_SPIN_TIME


func _physics_process(_delta: float) -> void:
	# 순차 정지: 스핀 중에만 동작. 타이머 만료 시 다음 릴을 stop_at.
	if _next_stop < 0 or _next_stop >= _reels.size():
		return
	_stop_timer -= _delta
	if _stop_timer <= 0.0:
		_stop_reel(_next_stop)
		_next_stop += 1
		_stop_timer = REEL_STOP_DELAY


func _stop_reel(i: int) -> void:
	var config := GameConfig.config
	var result: Array[SymbolData] = []
	for row in range(config.row_count):
		result.append(_grid[i][row])
	_reels[i].stop_at(result)


func _on_reel_stopped(reel_index: int) -> void:
	_core.on_reel_stopped(reel_index)


# --- 이펙트 훅 ---

## 당첨 심볼 하이라이트(EventBus.highlight_wins).
func _on_highlight(result: SpinResult) -> void:
	for pos in result.winning_positions:
		if pos.x >= 0 and pos.x < _reels.size():
			_reels[pos.x].set_symbol_highlight(pos.y, true)


## 빅윈 시 릴 영역 진동(EventBus.big_win).
func _on_big_win(amount: int) -> void:
	var amplitude := clampf(float(amount) / 50.0, 4.0, 18.0)
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	for i in range(5):
		var off := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amplitude
		tween.tween_property(_reel_area, "position", _reel_area_origin + off, 0.04)
	tween.tween_property(_reel_area, "position", _reel_area_origin, 0.1).set_trans(Tween.TRANS_QUAD)
