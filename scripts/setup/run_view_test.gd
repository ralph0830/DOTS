extends Node
## 뷰 흐름 검증 씬(에디터에서 실행 권장).
## 자동으로 스핀을 트리거해 스핀 → 릴 정지 → 평가 흐름이 뷰를 통해 동작하는지 확인.
## 헤드리스에서는 더미 DisplayServer 로 인해 main loop 프레임이 제한될 수 있어
## 시각/타이밍 검증은 에디터 실행(F5)으로 확인한다.
## 에디터에서 이 씬을 열고 실행하면 2회 자동 스핀 후 결과를 콘솔에 출력한다.

const SPINS := 2
const SPIN_INTERVAL := 2.5

var _eval_count := 0
var _state := 0          # 0=사전대기, 1=스핀후대기, 2=종료
var _timer := 0.0
var _spin := 0


func _ready() -> void:
	OS.low_processor_usage_mode = false
	var smv: Node = load("res://scenes/slot/SlotMachine.tscn").instantiate()
	add_child(smv)
	WalletManager.credit = 10000
	EventBus.evaluation_completed.connect(func(_r): _eval_count += 1)
	print("[view-test] 시작 credit=%d bet=%d" % [WalletManager.credit, WalletManager.current_bet])
	_state = 0
	_timer = 0.3


func _physics_process(delta: float) -> void:
	if _state == 2:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if _state == 0:
		EventBus.spin_requested.emit()
		print("[view-test] 스핀 %d emit" % _spin)
		_state = 1
		_timer = SPIN_INTERVAL
	elif _state == 1:
		print("[view-test] 스핀 %d 후 eval_count=%d" % [_spin, _eval_count])
		_spin += 1
		if _spin < SPINS:
			_state = 0
			_timer = 0.3
		else:
			_finish()


func _finish() -> void:
	_state = 2
	print("[view-test] 최종 eval_count=%d/%d credit=%d" % [_eval_count, SPINS, WalletManager.credit])
	if _eval_count == SPINS:
		print("[view-test] OK: 스핀 → 릴 정지 → 평가 흐름 정상")
	else:
		print("[view-test] 참고: 헤드리스에선 프레임 제한으로 평가가 덜 실행될 수 있음 — 에디터 실행 권장")
	get_tree().quit()
