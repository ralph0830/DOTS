extends Node
## BonusManager — 프리스핀 상태 머신 autoload.
## EventBus.evaluation_completed 를 구독해:
##   1) 프리스핀 중이면 당첨 금액에 멀티플라이어 적용
##   2) 남은 프리스핀 1 소비 (0 도달 시 종료 emit)
##   3) result.free_spins_awarded > 0 이면 재트리거 부여
## 코어 직접 참조 없이 EventBus 시그널로만 외부 통신.
## autoload 등록 예정이므로 class_name 사용 금지(이름 충돌 방지).

# --- 상태 ---
var free_spins_remaining: int = 0
var current_multiplier: float = 1.0

# --- 자체 시그널 (SlotMachineView 등 직접 연결용) ---
signal free_spins_started(count: int, multiplier: float)
signal free_spins_changed(remaining: int, multiplier: float)
signal free_spins_ended()


func _ready() -> void:
	# evaluation_completed 수신 → 프리스핀 처리.
	EventBus.evaluation_completed.connect(_on_eval)


## 현재 프리스핀 진행 중인지.
func is_free_spin() -> bool:
	return free_spins_remaining > 0


## 현재 적용할 당첨 배수. 프리스핀 중이면 current_multiplier, 아니면 1.0.
func get_multiplier() -> float:
	return current_multiplier if is_free_spin() else 1.0


## 프리스핀 부여. 최초 부여 시 free_spins_started emit.
# 카운터는 누적(재트리거), 멀티플라이어는 더 큰 값 유지.
func award(count: int, multiplier: float) -> void:
	if count <= 0:
		return
	var was_active := is_free_spin()
	free_spins_remaining += count
	# 더 큰 배수를 유지(기존이 더 크면 기존 유지).
	if multiplier > current_multiplier:
		current_multiplier = multiplier

	if not was_active:
		# 최초 부여 — 시작 알림 + EventBus forward.
		free_spins_started.emit(free_spins_remaining, current_multiplier)
		EventBus.free_spins_started.emit(free_spins_remaining, current_multiplier)
	# 카운터/배수 변화 알림 + forward.
	free_spins_changed.emit(free_spins_remaining, current_multiplier)
	EventBus.free_spins_changed.emit(free_spins_remaining, current_multiplier)


## 프리스핀 1회 소비. 0 도달 시 free_spins_ended emit. 소비 성공 여부 반환.
func consume_one() -> bool:
	if free_spins_remaining <= 0:
		return false
	free_spins_remaining -= 1
	free_spins_changed.emit(free_spins_remaining, current_multiplier)
	EventBus.free_spins_changed.emit(free_spins_remaining, current_multiplier)
	if free_spins_remaining == 0:
		# 프리스핀 종료 — 배수 초기화.
		current_multiplier = 1.0
		free_spins_ended.emit()
		EventBus.free_spins_ended.emit()
	return true


## 런 리스타트 시 상태 완전 초기화 (재시작 잔류 버그 방지).
# 남은 프리스핀/멀티플라이어가 새 런으로 넘어가는 것을 차단.
func reset() -> void:
	var was_active := is_free_spin()
	free_spins_remaining = 0
	current_multiplier = 1.0
	if was_active:
		# 종료 알림 emit — HUD 가 프리스핀 표시를 지우도록 동기화.
		free_spins_ended.emit()
		EventBus.free_spins_ended.emit()


## evaluation_completed 핸들러.
func _on_eval(result: SpinResult) -> void:
	if result == null:
		return

	# 1) 프리스핀 중이면 멀티플라이어를 결과에 정수 곱으로 적용.
	if is_free_spin():
		_apply_to_result(result, get_multiplier())

	# 2) 프리스핀 중이면 1회 소비.
	if is_free_spin():
		consume_one()

	# 3) 이번 스핀에서 프리스핀 부여(재트리거 포함)가 있으면 반영.
	if result.free_spins_awarded > 0:
		var paytable: Paytable = null
		# GameConfig 가 로드되어 있으면 paytable에서 배수 조회, 실패 시 기본 2.0.
		if GameConfig.config != null:
			paytable = GameConfig.config.paytable
		var mult: float = paytable.free_spin_multiplier if paytable != null else 2.0
		award(result.free_spins_awarded, mult)


## 결과에 멀티플라이어(정수 곱) 적용 — total/line/scatter 모두 가감.
func _apply_to_result(result: SpinResult, mult: float) -> void:
	var m: int = int(mult)
	if m <= 1:
		return
	result.total_win *= m
	for lw in result.line_wins:
		lw.amount *= m
	result.scatter_win *= m
