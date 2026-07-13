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
var _game_over: bool = false   # 게임 종료 중 스핀 금지 플래그 (AUTO 가 새 유닛을 계속 생산하지 않도록)

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
	# EventBus 구독 — 뷰가 코어를 직접 호출하지 않고 시그널로 통신(느슨한 결합).
	EventBus.spin_requested.connect(request_spin)
	EventBus.reel_stopped.connect(on_reel_stopped)
	EventBus.reroll_requested.connect(reroll)
	EventBus.game_over.connect(_on_game_over)   # 게임오버 시 스핀 거부 위해 구독


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
	if _game_over:   # ★ 게임오버 중 스핀 금지 — AUTO 루프가 새 유닛을 계속 생산하지 않도록.
		return
	if state != State.IDLE:
		return
	# 올 인 — 보유 CREDIT 100% 베팅 (프리스핀 제외).
	var lord := get_node_or_null("/root/LordState")
	if lord != null and bool(lord.get("all_in_enabled")) and not _is_free_spin():
		WalletManager.current_bet = WalletManager.credit
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


## 게임오버 수신 — 스핀 금지 플래그 설정. 리스타트 시 reset_game_over() 로 해제.
func _on_game_over(_victory: bool) -> void:
	_game_over = true


## 런 리스타트 시 스핀 금지 해제 (재시작 후 정상 스핀 허용).
func reset_game_over() -> void:
	_game_over = false


## 릴 1개 정지 보고(뷰 또는 테스트가 호출). 활성 릴 수만큼 누적 시 평가로 전이.
## bet_level별 활성 릴 수 기준 (비활성 릴은 스핀하지 않으므로 보고되지 않음).
func on_reel_stopped(_reel_index: int) -> void:
	if state == State.SPINNING:
		_set_state(State.STOPPING)
	if state != State.STOPPING:
		return
	_stopped_reels += 1
	var needed := WalletManager.active_reels_for(WalletManager.bet_level).size()
	if _stopped_reels >= needed:
		_evaluate()


## 평가 실행. 모디파이어 → evaluation_completed(BonusManager 가공) → 하이라이트/잭팟 emit.
## Phase 8-C: add_win(지갑 반영) 제거 — 슬롯은 유닛 생산 수단, CREDIT는 베팅 비용만.
## total_win 은 여전히 SpinResult 에 존재 (UI 표시/빅윈 연출용) but 지갑에 반영 안 함.
func _evaluate() -> void:
	_set_state(State.EVALUATING)
	var result := WinCalculator.evaluate(
		_pending_grid, config.paylines, config.paytable, WalletManager.current_bet, 1.0,
		WalletManager.payline_count_for(WalletManager.bet_level),
		WalletManager.active_reels_for(WalletManager.bet_level)
	)
	# 확장 훅: 결과 모디파이어.
	for cb in _result_modifiers:
		cb.call(result)
	# evaluation_completed emit → UnitSpawner(리스너)가 매칭 결과를 유닛 소환으로 변환.
	# BonusManager 도 리스너로 프리스핀 배수 가공 (total_win 자체는 연출용).
	evaluation_completed.emit(result)
	EventBus.evaluation_completed.emit(result)
	if result.has_win():
		# WalletManager.add_win() 제거 (Phase 8-C) — 슬롯=유닛 생산 수단, 도박 아님.
		EventBus.highlight_wins.emit(result)
		_judgment_day_if_triggered(result)   # 심판의 날 — 5매칭 시 전적 피해.
		if result.is_big_win(WalletManager.current_bet):
			EventBus.big_win.emit(result.total_win)
	if result.jackpot_tier >= 0:
		EventBus.jackpot_won.emit(result.jackpot_tier, result.jackpot_amount)
	_set_state(State.IDLE)


## 각 릴의 무작위 정지 위치에서 row_count행짜리 결과 생성. grid[reel][row].
func _generate_grid() -> Array:
	var grid: Array = []
	# 비활성 행은 null — 매칭에서 제외 (bet_level별 활성 행만 심볼 할당).
	var active_rows := WalletManager.active_rows_for(WalletManager.bet_level)
	for r in range(config.reel_count):
		var strip: ReelStrip = config.reels[r]
		var start := strip.random_start_index(rng)
		var col: Array = []
		for row in range(config.row_count):
			if active_rows.has(row):
				col.append(strip.at(start + row))
			else:
				col.append(null)   # 비활성 행 — 매칭/당첨라인 영향 X
		grid.append(col)
	return grid


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	var old := state
	state = new_state
	state_changed.emit(old, new_state)
	EventBus.state_changed.emit(old, new_state)


## 리롤 — 무료로 결과 grid 재생성(베팅 차감 없음). reroll_requested 수신.
func reroll() -> void:
	if _game_over or state != State.IDLE:
		return
	var lord := get_node_or_null("/root/LordState")
	if lord == null or int(lord.get("reroll_charges")) <= 0:
		return
	lord.reroll_charges -= 1
	_pending_grid = _generate_grid()
	_stopped_reels = 0
	_set_state(State.SPINNING)
	var bet := WalletManager.current_bet
	spin_started.emit(bet)
	EventBus.spin_started.emit(bet)
	spin_complete.emit(_pending_grid)
	EventBus.spin_complete.emit(_pending_grid)


## 심판의 날 — 5매칭 시 활성화되어 있으면 전적 50% 피해.
func _judgment_day_if_triggered(result: SpinResult) -> void:
	var lord := get_node_or_null("/root/LordState")
	if lord == null or not bool(lord.get("judgment_day_enabled")):
		return
	for lw in result.line_wins:
		if lw.match_count >= 5:
			_apply_judgment_day()
			return


func _apply_judgment_day() -> void:
	var smv := get_tree().get_first_node_in_group(&"slot_machine_view") if get_tree().has_group(&"slot_machine_view") else null
	if smv == null or not smv.has_node("BattleField"):
		return
	var battle := smv.get_node("BattleField")
	for child in battle.get_children():
		if child is Unit and child.is_enemy and child._alive:
			child.take_damage(int(float(child.hp) * 0.5))
	print("[SlotMachine] 심판의 날 발동 — 필드 모든 적 현재체력 50% 피해")
