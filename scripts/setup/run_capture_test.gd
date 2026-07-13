extends Node
## 각 bet_level(1~5)별로 활성 매트릭스 + 회색 처리 + 평가 도착을 캡처 검증 (GUI 모드).
## 세이브 bet_level 영향 회피 — 각 레벨 강제 설정 + bet_level_changed emit.
## 결과: captures/level_N.png (N=1..5)
const CAPTURE_PATH := "C:/Project/DOTS/captures/"
const LEVELS := [1, 2, 3, 4, 5]

var _smv: Node
var _level_idx := 0
var _busy := false
var _spin_timeout := 0.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CAPTURE_PATH)
	_smv = load("res://scenes/slot/SlotMachine.tscn").instantiate()
	add_child(_smv)
	WalletManager.reset_credit(10000)
	EventBus.evaluation_completed.connect(_on_eval)
	set_process(true)
	print("[capture] 시작 — 각 bet_level(1~5) 캡처")
	await get_tree().create_timer(1.0).timeout   # SlotMachineView _ready 완료 대기
	_dump_layout()
	_start_level()


## Layout 값 진단 출력 (빈 공간/비율 디버깅용).
func _dump_layout() -> void:
	var v: Vector2 = Layout.viewport()
	var top_px := Layout.TOP_MARGIN * v.y
	var bot_px := Layout.BOTTOM_MARGIN * v.y
	var total := top_px + Layout.battle_h() + Layout.minimap_h() + Layout.slot_h() + Layout.control_h() + bot_px
	print("=== LAYOUT 진단 vp=%.0fx%.0f ===" % [v.x, v.y])
	print("  TOP=%.0f battle=%.0f minimap=%.0f slot=%.0f control=%.0f BOTTOM=%.0f" % [top_px, Layout.battle_h(), Layout.minimap_h(), Layout.slot_h(), Layout.control_h(), bot_px])
	print("  minimap_top=%.0f slot_top=%.0f control_top=%.0f" % [Layout.minimap_top(), Layout.slot_top(), Layout.control_top()])
	var cell: float = Layout.cell_size()
	print("  cell=%.0f reel_grid=%.0f reel_area_h=%.0f" % [cell, cell * 5.0, Layout.control_top() - Layout.slot_top()])
	print("  TOTAL=%.0f (vp.y=%.0f, 차=%.0f)" % [total, v.y, v.y - total])
	# ReelArea / ReelView 실제 size (릴 아래 빈 공간 원인 파악)
	var smv: Node = _smv
	if smv != null and smv.get("_reel_area") != null:
		var ra: Control = smv._reel_area
		print("  ReelArea size=%s pos=%s" % [str(ra.size), str(ra.position)])
		if smv._reels.size() > 0:
			var r0: ReelView = smv._reels[0]
			print("  Reel0 size=%s cmin=%s pos=%s scale=%s SYMBOL=%s" % [str(r0.size), str(r0.custom_minimum_size), str(r0.position), str(r0.scale), str(r0.SYMBOL_SIZE)])



func _process(_delta: float) -> void:
	# 평가 미도착 안전 타임아웃 — 레벨별 6초 초과 시 강제 다음
	if _busy:
		_spin_timeout += _delta
		if _spin_timeout > 6.0:
			print("[capture] L%d ★ EVAL 타임아웃 — 강제 다음" % LEVELS[_level_idx])
			_busy = false
			_spin_timeout = 0.0
			_level_idx += 1
			_start_level()


func _start_level() -> void:
	if _level_idx >= LEVELS.size():
		print("[capture] 완료 — captures/level_*.png 확인")
		await get_tree().create_timer(0.3).timeout
		get_tree().quit()
		return
	var level: int = LEVELS[_level_idx]
	WalletManager.bet_level = level
	EventBus.bet_level_changed.emit(level)
	_dump(level)
	await get_tree().create_timer(0.5).timeout
	EventBus.spin_requested.emit()


func _on_eval(r: SpinResult) -> void:
	if _busy:
		return
	_busy = true
	_spin_timeout = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	var level: int = LEVELS[_level_idx]
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(CAPTURE_PATH + "level_%d.png" % level)
	print("[capture] L%d 저장 err=%d win=%d lines=%d max_match=%d" % [level, err, r.total_win, r.line_wins.size(), _max_match(r)])
	_busy = false
	_level_idx += 1
	await get_tree().create_timer(0.5).timeout
	_start_level()


func _max_match(r: SpinResult) -> int:
	var m := 0
	for lw in r.line_wins:
		m = maxi(m, lw.match_count)
	return m


func _dump(level: int) -> void:
	var smv := _smv
	print("=== L%d active_reels=%s active_rows=%s paylines=%d ===" % [level,
		str(WalletManager.active_reels_for(level)),
		str(WalletManager.active_rows_for(level)),
		WalletManager.payline_count_for(level)])
