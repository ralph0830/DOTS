extends Node
## WalletManager — 크레딧/베팅 관리 autoload. 영속(user://wallet.save).
## Phase 8-C: 슬롯 도박 잔재 제거 — total_won/add_win 삭제.
## 크레딧은 스핀 베팅 비용으로만 감소 (시작값 10000에서 차감).
## 크레딧 충전은 디버그(HUD 탭) 또는 향후 보상 시스템(Phase 10)만.

signal credit_changed(credit: int)
signal bet_changed(bet: int)

const SAVE_PATH := "user://wallet.save"

var credit: int = 10000
var current_bet: int = 50
var bet_steps: PackedInt32Array = []
var bet_index: int = 0
var bet_level: int = 1   # 베팅 확장 단계 (1~5) — 그리드 확장 + 베팅 비용 배수 + 소환 배수
var _initialized: bool = false

# --- bet_level별 활성 매트릭스 (static) ---
## bet_level별 활성 릴 인덱스 (x1=가운데 3릴, x2=+우, x3=전체).
static func active_reels_for(level: int) -> Array:
	match level:
		1: return [1, 2, 3]
		2: return [1, 2, 3, 4]
		_: return [0, 1, 2, 3, 4]

## bet_level별 활성 행 인덱스 (x1~3=중앙 3행, x4=+상단, x5=전체).
static func active_rows_for(level: int) -> Array:
	match level:
		4: return [0, 1, 2, 3]
		1, 2, 3: return [1, 2, 3]
		_: return [0, 1, 2, 3, 4]

## bet_level별 활성 페이라인 수.
static func payline_count_for(level: int) -> int:
	match level:
		1: return 5
		2: return 8
		3: return 15
		4: return 25
		_: return 50


func _ready() -> void:
	_load()


## SlotConfig의 베팅 스텝/기본 인덱스로 초기화. 기존 영속 크레딧은 유지.
func initialize(config: SlotConfig) -> void:
	bet_steps = PackedInt32Array()
	for step in config.base_bet_steps:
		bet_steps.append(int(step))
	if bet_steps.is_empty():
		# 모바일 직렬화 손실(PackedFloat32Array 가 빈 배열로 로드) 방어 —
		# [50] 고정이면 BET± 버튼이 무의미해지고 밸런스가 왜곡되므로 코드 기본 스텝 전체로 폴백.
		bet_steps = PackedInt32Array([10, 25, 50, 100, 250, 500])
	bet_index = clampi(config.default_bet_index, 0, bet_steps.size() - 1)
	current_bet = bet_steps[bet_index]
	if credit <= 0:
		credit = config.starting_credit
	_initialized = true
	_emit_bet(current_bet)
	_emit_credit(credit)


## 현재 크레딧으로 베팅 가능한지.
func can_bet() -> bool:
	return credit >= current_bet * bet_level


## 베팅 차감. 성공 시 true, 크레딧 부족 시 false.
func place_bet() -> bool:
	# bet_level 만큼 베팅 비용 증가 (확장 단계 = 베팅 배수).
	var cost := current_bet * bet_level
	if credit < cost:
		return false
	credit -= cost
	_emit_credit(credit)
	_save()
	return true


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
	f.save(SAVE_PATH)


func _load() -> void:
	var f := ConfigFile.new()
	if f.load(SAVE_PATH) != OK:
		return
	credit = int(f.get_value("wallet", "credit", credit))
