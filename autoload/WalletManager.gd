extends Node
## WalletManager — 크레딧/베팅/총당첨 관리 autoload. 영속(user://wallet.save).

signal credit_changed(credit: int)
signal bet_changed(bet: int)

const SAVE_PATH := "user://wallet.save"

var credit: int = 10000
var current_bet: int = 50
var bet_steps: PackedInt32Array = []
var bet_index: int = 0
var total_won: int = 0
var _initialized: bool = false


func _ready() -> void:
	_load()


## SlotConfig의 베팅 스텝/기본 인덱스로 초기화. 기존 영속 크레딧은 유지.
func initialize(config: SlotConfig) -> void:
	bet_steps = PackedInt32Array()
	for step in config.base_bet_steps:
		bet_steps.append(int(step))
	if bet_steps.is_empty():
		bet_steps = PackedInt32Array([50])
	bet_index = clampi(config.default_bet_index, 0, bet_steps.size() - 1)
	current_bet = bet_steps[bet_index]
	if credit <= 0:
		credit = config.starting_credit
	_initialized = true
	_emit_bet(current_bet)
	_emit_credit(credit)


## 현재 크레딧으로 베팅 가능한지.
func can_bet() -> bool:
	return credit >= current_bet


## 베팅 차감. 성공 시 true, 크레딧 부족 시 false.
func place_bet() -> bool:
	if not can_bet():
		return false
	credit -= current_bet
	_emit_credit(credit)
	_save()
	return true


## 당첨 금액 적립.
func add_win(amount: int) -> void:
	if amount <= 0:
		return
	credit += amount
	total_won += amount
	_emit_credit(credit)
	_save()


## 크레딧 충전(디버그/보너스용).
func add_credit(amount: int) -> void:
	if amount == 0:
		return
	credit += amount
	_emit_credit(credit)
	_save()


## 크레딧을 지정 금액으로 리셋(시그널 발생 → HUD 즉시 갱신). 테스트/재시작용.
func reset_credit(amount: int) -> void:
	credit = amount
	total_won = 0
	_emit_credit(credit)
	_save()


## 베팅 단계 변경(direction: +1/-1). 경계에서 무시.
func change_bet(direction: int) -> void:
	if bet_steps.is_empty():
		return
	var new_index := clampi(bet_index + direction, 0, bet_steps.size() - 1)
	if new_index == bet_index:
		return
	bet_index = new_index
	current_bet = bet_steps[bet_index]
	_emit_bet(current_bet)


# --- 시그널 발행 헬퍼 ---
# 자체 시그널 + EventBus forward 를 한 곳에서 처리(2026-07-03 결합도 일원화).
# BonusManager 의 이중 emit 패턴과 동일 — HUD 가 autoload 직접 접근 없이 EventBus 만 구독 가능.
func _emit_credit(value: int) -> void:
	credit_changed.emit(value)
	EventBus.credit_changed.emit(value)


func _emit_bet(value: int) -> void:
	bet_changed.emit(value)
	EventBus.bet_changed.emit(value)


func _save() -> void:
	if not _initialized:
		return
	var f := ConfigFile.new()
	f.set_value("wallet", "credit", credit)
	f.set_value("wallet", "total_won", total_won)
	f.save(SAVE_PATH)


func _load() -> void:
	var f := ConfigFile.new()
	if f.load(SAVE_PATH) != OK:
		return
	credit = int(f.get_value("wallet", "credit", credit))
	total_won = int(f.get_value("wallet", "total_won", 0))
