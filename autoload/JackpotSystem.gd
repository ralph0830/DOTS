extends Node
## JackpotSystem — Mini/Minor/Major/Grand 4티어 누적 잭팟 풀 autoload. 영속(user://jackpot.save).
## Phase 1: 풀 누적/영속/지급 구조만 구현. 트리거 평가는 Phase 4에서 연결.

enum Tier { MINI, MINOR, MAJOR, GRAND }

const SAVE_PATH := "user://jackpot.save"
const TIER_NAMES: PackedStringArray = ["Mini", "Minor", "Major", "Grand"]
# 기여금 4티어 분배 비율 (합 = 1.0)
const TIER_SHARE: PackedFloat32Array = [0.40, 0.30, 0.20, 0.10]

signal pool_changed(tier: int, amount: int)
signal jackpot_won(tier: int, amount: int)

var pools: PackedInt64Array = [0, 0, 0, 0]
var _seeds: PackedInt64Array = [0, 0, 0, 0]
var _initialized: bool = false


func _ready() -> void:
	_load()


## SlotConfig 시드로 풀 초기화. 이미 저장된(누적 중인) 풀은 유지.
func initialize(config: SlotConfig) -> void:
	_seeds = PackedInt64Array([
		config.jackpot_seed_mini,
		config.jackpot_seed_minor,
		config.jackpot_seed_major,
		config.jackpot_seed_grand,
	])
	for i in range(4):
		if pools[i] < _seeds[i]:
			pools[i] = _seeds[i]
			pool_changed.emit(i, pools[i])
	_initialized = true
	_save()


## 매 스핀마다 베팅의 rate% 를 4티어에 비율 배분해 누적.
func contribute(bet: int, rate: float) -> void:
	var contribution := int(float(bet) * rate)
	if contribution <= 0 or not _initialized:
		return
	for i in range(4):
		pools[i] += int(float(contribution) * TIER_SHARE[i])
		pool_changed.emit(i, pools[i])
	_save()


## 해당 티어 잭팟 지급: 금액 반환 후 풀을 시드로 리셋.
func award(tier: int) -> int:
	if tier < 0 or tier >= 4:
		return 0
	var amount := pools[tier]
	pools[tier] = _seeds[tier]
	jackpot_won.emit(tier, amount)
	pool_changed.emit(tier, pools[tier])
	_save()
	return amount


func get_pool(tier: int) -> int:
	if tier < 0 or tier >= 4:
		return 0
	return pools[tier]


func _save() -> void:
	if not _initialized:
		return
	var f := ConfigFile.new()
	for i in range(4):
		f.set_value("pools", TIER_NAMES[i].to_lower(), pools[i])
	f.save(SAVE_PATH)


func _load() -> void:
	var f := ConfigFile.new()
	if f.load(SAVE_PATH) != OK:
		return
	var loaded := PackedInt64Array([0, 0, 0, 0])
	for i in range(4):
		loaded[i] = int(f.get_value("pools", TIER_NAMES[i].to_lower(), 0))
	pools = loaded
