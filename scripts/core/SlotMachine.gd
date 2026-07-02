class_name SlotMachine
extends Node
## 슬롯머신 코어 상태머신.
## 스핀 요청 → 결과 그리드 생성 → (뷰 정지 대기) → 평가 흐름을 오케스트레이션.
## Phase 4: 프리스핀(베팅 우회) + 잭팟(jackpot_won emit).
## evaluation_completed 를 add_win 전에 emit 해서 BonusManager(리스너)가
## 멀티플라이어를 가공한 뒤 지갑에 반영하도록 순서를 잡는다.

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
## 결과 모디파이어 체인(Phase 4 결과 후처리 확장점).
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


## 스핀 가능 상태인지. 프리스핀 중이면 베팅 불필요.
func can_spin() -> bool:
	if state != State.IDLE:
		return false
	if _is_free_spin():
		return true
	return WalletManager.can_bet()


## 스핀 요청. 프리스핀이면 베팅 우회, 아니면 베팅 차감 + 잭팟 기여 → 결과 생성 → 뷰에 통지.
func request_spin() -> void:
	if state != State.IDLE:
		return
	if _is_free_spin():
		pass   # 무료 스핀(베팅/기여 없음)
	elif not WalletManager.place_bet():
		return
	else:
		JackpotSystem.contribute(WalletManager.current_bet, config.jackpot_contribution_rate)

	_pending_grid = _generate_grid()
	_stopped_reels = 0
	_set_state(State.SPINNING)
	var bet := WalletManager.current_bet
	spin_started.emit(bet)
	EventBus.spin_started.emit(bet)
	spin_complete.emit(_pending_grid)
	EventBus.spin_complete.emit(_pending_grid)


## 프리스핀 중인지(BonusManager autoload 확인).
func _is_free_spin() -> bool:
	var bm := get_node_or_null("/root/BonusManager")
	return bm != null and bm.is_free_spin()


## 릴 1개 정지 보고(뷰 또는 테스트가 호출). 5개 누적 시 평가로 전이.
func on_reel_stopped(_reel_index: int) -> void:
	if state == State.SPINNING:
		_set_state(State.STOPPING)
	if state != State.STOPPING:
		return
	_stopped_reels += 1
	if _stopped_reels >= config.reel_count:
		_evaluate()


## 평가 실행. 모디파이어 → evaluation_completed(BonusManager 가공) → 지갑 반영 → 하이라이트/잭팟 emit.
func _evaluate() -> void:
	_set_state(State.EVALUATING)
	var result := WinCalculator.evaluate(
		_pending_grid, config.paylines, config.paytable, WalletManager.current_bet, 1.0, config.payline_count
	)
	# 확장 훅: 결과 모디파이어.
	for cb in _result_modifiers:
		cb.call(result)
	# evaluation_completed 를 먼저 emit → BonusManager(리스너)가 프리스핀 배수 등을 가공.
	# 가공된 total_win 을 그 다음 add_win 으로 지갑에 반영.
	evaluation_completed.emit(result)
	EventBus.evaluation_completed.emit(result)
	if result.has_win():
		WalletManager.add_win(result.total_win)
		EventBus.highlight_wins.emit(result)
		if result.is_big_win(WalletManager.current_bet):
			EventBus.big_win.emit(result.total_win)
	if result.jackpot_tier >= 0:
		EventBus.jackpot_won.emit(result.jackpot_tier, result.jackpot_amount)
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
