extends Node
## 자동 스핀 후 스크린샷을 파일로 저장(GUI 모드 실행).
## HUD/레이아웃/당첨 라인 시각 검증용. 결과: captures/spin_N.png
## 실행: godot --path <project> res://scenes/setup/CaptureTest.tscn

const CAPTURE_PATH := "C:/Project/DOTS/captures/"
const SPINS := 2

var _smv: Node
var _spin := 0
var _busy := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CAPTURE_PATH)
	_smv = load("res://scenes/slot/SlotMachine.tscn").instantiate()
	add_child(_smv)
	WalletManager.reset_credit(10000)   # 시그널 emit → HUD 즉시 갱신
	EventBus.evaluation_completed.connect(_on_eval)
	print("[capture] 시작 — %d회 스핀 후 캡처" % SPINS)
	_trigger_spin()


func _trigger_spin() -> void:
	await get_tree().create_timer(0.8).timeout
	EventBus.spin_requested.emit()


func _on_eval(r: SpinResult) -> void:
	if _busy:
		return
	_busy = true
	_spin += 1
	var max_match := 0
	for lw in r.line_wins:
		max_match = maxi(max_match, lw.match_count)
	print("[capture] 스핀 %d: win=%d lines=%d max_match=%d credit=%d" % [_spin, r.total_win, r.line_wins.size(), max_match, WalletManager.credit])
	# 당첨 라인이 그려진 후 캡처(2프레임 대기)
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(CAPTURE_PATH + "spin_%d.png" % _spin)
	print("[capture]   저장 spin_%d.png (err=%d)" % [_spin, err])
	_busy = false
	if _spin >= SPINS:
		print("[capture] 완료 — captures/ 폴더 확인")
		await get_tree().create_timer(0.3).timeout
		get_tree().quit()
	else:
		await get_tree().create_timer(0.5).timeout
		EventBus.spin_requested.emit()
