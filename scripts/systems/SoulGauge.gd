extends Node
## SoulGauge — 영혼 게이지(레벨업 재화) autoload.
## 적 처치 시 영혼(EXP) 획득 → 게이지 충전 → 100% 도달 시 level_up_available emit.
## Phase 8-B 의 LevelUpUI 가 이 시그널을 받아 3지선다 카드를 표시한다.
##
## 설계 (open-structure):
##   - 코어(SlotMachine)를 직접 수정하지 않고 EventBus.enemy_killed 리스너로만 통합.
##   - GameManager/WaveManager 의 기존 enemy_killed 구독에 영향 0 (3번째 구독자).
##   - 일시정지/해제는 Phase 8-B 의 LevelUpUI 가 담당 (여기선 시그널만 emit).
##
## 패턴 참고:
##   - 상태/이중 emit: WalletManager (_emit_* 헬퍼)
##   - initialize/reset: JackpotSystem (명시적 reset 으로 BonusManager 약점 보완)

# --- 자체 시그널 (직접 연결용) + EventBus forward (이중 emit) ---
signal soul_changed(value: int, maximum: int, level: int)
signal level_up_available(level: int)
signal level_up_completed(new_level: int)

# --- 상태 ---
var soul: int = 0          # 현재 충전된 영혼
var soul_max: int = 15     # 다음 레벨업 임계값 (level=1 → 15)
var level: int = 1         # 현재 레벨
var _initialized: bool = false
# 레벨업 대기 중 플래그 — true 인 동안 추가 EXP 획득 무시 (중복 레벨업 방지).
# LevelUpUI 선택 → complete_level_up() 호출로 해제.
var _level_up_pending: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.enemy_killed.connect(_on_enemy_killed)


## 임계값 계산: 10 + level*5 (Lv1=15, Lv2=20, Lv3=25, ...).
## PRD/GDD 합의: 로그라이크 표준 레벨 비례 곡선.
func _threshold() -> int:
	return 10 + level * 5


## 초기화 (게임 시작 시). soul_max 를 레벨에 맞게 세팅.
func initialize() -> void:
	level = 1
	soul = 0
	soul_max = _threshold()
	_level_up_pending = false
	_initialized = true
	_emit_soul()


## 런 리스타트용 완전 리셋 (BonusManager 약점 보완 — 명시적 reset).
func reset() -> void:
	initialize()


## 적 처치 시 영혼 획득. 게이지가 100% 도달하면 level_up_available emit + 가드 설정.
func _on_enemy_killed(_enemy_id: StringName, exp_reward: int) -> void:
	if not _initialized or _level_up_pending:
		return
	if exp_reward <= 0:
		return
	soul += exp_reward
	# 임계치 도달 시 레벨업 트리거 (초과분은 이월하지 않고 정확히 임계치에서 발화).
	if soul >= soul_max:
		soul = soul_max   # 게이지 표시를 100%로 고정
		_level_up_pending = true
		print("[SoulGauge] 레벨업 가능! 레벨 %d → %d (soul %d/%d)" % [level, level + 1, soul, soul_max])
		level_up_available.emit(level)
		EventBus.level_up_available.emit(level)
	_emit_soul()


## 레벨업 완료 처리. LevelUpUI(Phase 8-B)가 선택지 적용 후 호출.
## 레벨 +1, soul 0으로 리셋, soul_max 재계산, 가드 해제.
func complete_level_up() -> void:
	if not _level_up_pending:
		push_warning("[SoulGauge] complete_level_up() 호출되었으나 대기 중인 레벨업 없음. 무시.")
		return
	level += 1
	soul = 0
	soul_max = _threshold()
	_level_up_pending = false
	print("[SoulGauge] 레벨업 완료 → 레벨 %d (다음 임계치 %d)" % [level, soul_max])
	level_up_completed.emit(level)
	EventBus.level_up_completed.emit(level)
	_emit_soul()


## 레벨업 대기 중인지 (LevelUpUI 표시 여부 판별용).
func is_level_up_pending() -> bool:
	return _level_up_pending


## 이중 emit 헬퍼 (WalletManager 스타일) — 자체 signal + EventBus 동시 emit.
func _emit_soul() -> void:
	soul_changed.emit(soul, soul_max, level)
	EventBus.soul_changed.emit(soul, soul_max, level)
