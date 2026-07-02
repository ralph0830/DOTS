class_name SlotMachine
extends Node
## 슬롯머신 코어 상태머신.
## 스핀 요청 → 결과 그리드 생성 → (뷰 정지 대기) → 평가 흐름을 오케스트레이션.
## 평가 후에는 당첨 여부와 무관하게 항상 IDLE 로 복귀한다.
## celebration 연출은 뷰가 EventBus 의 결과 시그널을 보고 자율적으로 재생한다
## (뷰-코어 타이밍 결합을 피하고 헤드리스 단독 동작을 보장하기 위함).

enum State { IDLE, SPINNING, STOPPING, EVALUATING }

signal state_changed(from: int, to: int)
signal spin_started(bet: int)
signal spin_complete(grid: Array)              # 결과 그리드 확정 — 뷰가 정지 애니메이션에 사용
signal evaluation_completed(result: SpinResult)

var config: SlotConfig
var rng: RandomNumberGenerator
var state: int = State.IDLE

var _pending_grid: Array = []
var _stopped_reels: int = 0
var _free_multiplier: float = 1.0               # TODO Phase 4: 결과 모디파이어로 대체
## 결과 모디파이어 체인(Phase 4 BonusManager 가 프리스핀 배수·잭팟 반영 등을 위해 등록).
var _result_modifiers: Array[Callable] = []


## 설정으로 초기화. RNG 시드는 config.rng_seed(0=무작위).
func initialize(cfg: SlotConfig) -> void:
	config = cfg
	rng = RandomNumberGenerator.new()
	rng.seed = cfg.rng_seed if cfg.rng_seed != 0 else randi()
	_set_state(State.IDLE)


## 결과 모디파이어 등록(Phase 4). Callable 은 SpinResult 를 받아 in-place 수정한다.
func add_result_modifier(cb: Callable) -> void:
	_result_modifiers.append(cb)


## 스핀 가능 상태인지.
func can_spin() -> bool:
	return state == State.IDLE and WalletManager.can_bet()


## 스핀 요청. 크레딧 차감 → 잭팟 기여 → 결과 생성 → 뷰에 통지.
## 실제 정지 타이밍은 뷰(또는 헤드리스 드라이버)가 on_reel_stopped로 보고.
func request_spin() -> void:
	if state != State.IDLE:
		return
	if not WalletManager.place_bet():
		return

	# 참고: spin_requested(요청) 는 뷰(HUD 버튼)가 emit 한다. 코어는 시작 사실을 알리기만 한다.
	JackpotSystem.contribute(WalletManager.current_bet, config.jackpot_contribution_rate)

	_pending_grid = _generate_grid()
	_stopped_reels = 0
	_set_state(State.SPINNING)
	var bet := WalletManager.current_bet
	spin_started.emit(bet)
	EventBus.spin_started.emit(bet)
	spin_complete.emit(_pending_grid)
	EventBus.spin_complete.emit(_pending_grid)


## 릴 1개 정지 보고(뷰 또는 테스트가 호출). 5개 누적 시 평가로 전이.
func on_reel_stopped(_reel_index: int) -> void:
	if state == State.SPINNING:
		_set_state(State.STOPPING)
	if state != State.STOPPING:
		return
	_stopped_reels += 1
	if _stopped_reels >= config.reel_count:
		_evaluate()


## 평가 실행. 당첨 시 지갑에 반영하고 결과를 발행한 뒤 IDLE 로 복귀.
func _evaluate() -> void:
	_set_state(State.EVALUATING)
	var result := WinCalculator.evaluate(
		_pending_grid, config.paylines, config.paytable, WalletManager.current_bet, _free_multiplier, config.payline_count
	)
	# 확장 훅: 결과 모디파이어(Phase 4 프리스핀 배수 등)를 적용한다.
	for cb in _result_modifiers:
		cb.call(result)
	if result.has_win():
		WalletManager.add_win(result.total_win)
	evaluation_completed.emit(result)
	EventBus.evaluation_completed.emit(result)
	if result.has_win():
		EventBus.highlight_wins.emit(result)
		if result.is_big_win(WalletManager.current_bet):
			EventBus.big_win.emit(result.total_win)
	_set_state(State.IDLE)


## 각 릴의 무작위 정지 위치에서 row_count행짜리 결과 생성. grid[reel][row].
func _generate_grid() -> Array:
	var grid: Array = []
	for r in range(config.reel_count):
		var strip: ReelStrip = config.reels[r]
		var start := strip.random_start_index(rng)
		var col: Array = []
		for row in range(config.row_count):
			col.append(strip.at(start + row))
		grid.append(col)
	return grid


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	var old := state
	state = new_state
	state_changed.emit(old, new_state)
