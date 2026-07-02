extends Node
## 4~5매치 당첨 라인이 나올 때까지 스핀하며 스크린샷을 저장(GUI 모드 실행).
## 목적: 4·5매치 시 당첨 선이 실제로 4·5개 심볼을 가로지르는지 시각 확인.
## 실행: godot --path <project> res://scenes/setup/CaptureTest.tscn
## 결과: captures/match_4.png, captures/match_5.png

const CAPTURE_PATH := "C:/Project/DOTS/captures/"
const MAX_SPINS := 80   # 4매치≈3스핀당 1개, 5매치≈5스핀당 1개 → 80회면 둘 다 포착 충분

var _smv: Node
var _spin := 0
var _busy := false
var _got4 := false
var _got5 := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CAPTURE_PATH)
	_smv = load("res://scenes/slot/SlotMachine.tscn").instantiate()
	add_child(_smv)
	WalletManager.reset_credit(1_000_000)   # 자금 고갈 방지
	EventBus.evaluation_completed.connect(_on_eval)
	print("[capture] 4·5매치 캡처 시작 (최대 %d스핀)" % MAX_SPINS)
	_trigger_spin()


func _trigger_spin() -> void:
	await get_tree().create_timer(0.45).timeout
	EventBus.spin_requested.emit()


func _on_eval(r: SpinResult) -> void:
	if _busy:
		return
	var max_match := 0
	for lw in r.line_wins:
		max_match = maxi(max_match, lw.match_count)
	_spin += 1
	print("[capture] spin %d: win=%d lines=%d max_match=%d" % [_spin, r.total_win, r.line_wins.size(), max_match])
	# 4매치 이상일 때만 캡처(각 매치수별 1장씩).
	if max_match >= 4:
		_busy = true
		await get_tree().process_frame
		await get_tree().process_frame   # 라인이 그려진 후 캡처
		var img := get_viewport().get_texture().get_image()
		var fname := "match_%d.png" % max_match
		var err := img.save_png(CAPTURE_PATH + fname)
		print("[capture] 저장 %s (err=%d)" % [fname, err])
		if max_match >= 5:
			_got5 = true
		else:
			_got4 = true
		_busy = false
	# 4·5매치 모두 포착했거나 한도 도달 시 종료.
	if (_got4 and _got5) or _spin >= MAX_SPINS:
		print("[capture] 완료 — 4매치=%s 5매치=%s" % [_got4, _got5])
		await get_tree().create_timer(0.3).timeout
		get_tree().quit()
	else:
		await get_tree().create_timer(0.4).timeout
		EventBus.spin_requested.emit()
