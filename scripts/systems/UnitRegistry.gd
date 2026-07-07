extends Node
## UnitRegistry — 모든 유닛(아군/적) UnitData 의 중앙 관리 autoload (Phase 8-C/D).
## UnitSpawner(아군 소환)와 WaveManager(적 스폰)가 각자 하드코딩하던 데이터를 통합.
##
## 설계 (open-structure):
##   - 데이터 생성은 이곳에 집중 — 향후 resources/units/*.tres 로 점진적 전환.
##   - UnitSpawner/WaveManager는 조회만 (결합도 감소).
##   - LordState 티어업 연동점: get_ally_unit() 호출 시 LordState.unit_tier를 반영.
##
## 아군 4종 (슬롯 심볼 매칭으로 소환): knight/archer/mage/minion(꽝 보정).
## 적 3종 (WAVE 스폰): goblin/orc/boss.

var _allies: Dictionary = {}   # StringName → UnitData
var _enemies: Dictionary = {}  # StringName → UnitData
var _initialized: bool = false


func _ready() -> void:
	initialize()


## 모든 유닛 데이터 생성. 향후 .tres 로딩으로 대체 가능.
func initialize() -> void:
	_allies.clear()
	_enemies.clear()
	# --- 아군 4종 ---
	# 기사(탱커): 높은 HP, 낮은 공격, 짧은 사거리, 방패 모양(파랑).
	_register_ally(&"knight", _make(&"knight", "Knight", UnitData.Role.TANK,
		80, 8, 1.0, 45.0, 55.0, UnitData.Shape.SQUARE, Color(0.25, 0.55, 0.95), 64.0, 0))
	# 궁수(원거리 딜러): 낮은 HP, 중공격, 긴 사거리(120px), 삼각(초록).
	_register_ally(&"archer", _make(&"archer", "Archer", UnitData.Role.DEALER,
		30, 12, 0.9, 70.0, 120.0, UnitData.Shape.TRIANGLE, Color(0.30, 0.85, 0.45), 56.0, 0))
	# 마법사(강력 딜러): 중간 HP, 고공격, 중사거리, 다이아(보라).
	_register_ally(&"mage", _make(&"mage", "Mage", UnitData.Role.DEALER,
		40, 18, 1.1, 60.0, 90.0, UnitData.Shape.DIAMOND, Color(0.70, 0.35, 0.95), 60.0, 0))
	# 꽝 보정 미니언 (skull 매칭/꽝일 때 1기 소환).
	_register_ally(&"minion", _make(&"minion", "Minion", UnitData.Role.MINION,
		20, 5, 1.0, 55.0, 50.0, UnitData.Shape.CIRCLE, Color(0.6, 0.6, 0.6), 50.0, 0))
	# skull 심볼 매칭 → 미니언과 동일 (꽝이지만 약한 유닛 1기).
	_allies[&"skull"] = _allies[&"minion"]

	# --- 적 3종 ---
	# goblin: 기본 적. exp_reward=1.
	_register_enemy(&"goblin", _make(&"goblin", "Goblin", UnitData.Role.ENEMY,
		20, 6, 1.0, 50.0, 50.0, UnitData.Shape.CIRCLE, Color(0.8, 0.2, 0.2), 60.0, 1))
	# orc: 중간 적. exp_reward=3.
	_register_enemy(&"orc", _make(&"orc", "Orc", UnitData.Role.ENEMY,
		40, 10, 1.0, 40.0, 60.0, UnitData.Shape.SQUARE, Color(0.7, 0.3, 0.1), 60.0, 3))
	# boss: 보스. 대형, 강함. exp_reward=10.
	_register_enemy(&"boss", _make(&"boss", "Boss", UnitData.Role.ENEMY,
		150, 20, 1.2, 35.0, 80.0, UnitData.Shape.DIAMOND, Color(0.9, 0.1, 0.3), 80.0, 10))

	_initialized = true


## 아군 UnitData 조회. LordState.unit_tier를 반영한 강화 사본 반환 (원본 훼손 방지).
func get_ally_unit(id: StringName) -> UnitData:
	var base: UnitData = _allies.get(id)
	if base == null:
		return null
	# Phase 8-D 연동: LordState.unit_tier 에 비례해 스탯 강화.
	# 현재는 기본 스탯 사본 반환 (tier=0). tier > 0 시 스탯 배수 적용 예정.
	var tier := 0
	var lord := get_node_or_null("/root/LordState")
	if lord != null and lord.has_method("get_state_summary"):
		var summary: Dictionary = lord.get_state_summary()
		tier = int(summary.get("unit_tier", 0))
	var copy := _clone_unit(base)
	if tier > 0:
		# 티어당 HP +30%, 공격 +20% (알베르트 유닛 진화 효과).
		var mult_hp := 1.0 + 0.3 * float(tier)
		var mult_atk := 1.0 + 0.2 * float(tier)
		copy.max_hp = int(float(copy.max_hp) * mult_hp)
		copy.attack = int(float(copy.attack) * mult_atk)
	return copy


## 적 UnitData 조회. 사본 반환 (원본 훼손 방지).
func get_enemy_unit(id: StringName) -> UnitData:
	var base: UnitData = _enemies.get(id)
	if base == null:
		return null
	return _clone_unit(base)


## 적의 EXP 보상 조회.
func get_exp_reward(enemy_id: StringName) -> int:
	var data: UnitData = _enemies.get(enemy_id)
	if data == null:
		return 0
	return data.exp_reward


func _register_ally(id: StringName, data: UnitData) -> void:
	_allies[id] = data


func _register_enemy(id: StringName, data: UnitData) -> void:
	_enemies[id] = data


## UnitData 인스턴스 생성 헬퍼.
func _make(id: StringName, name: String, role: UnitData.Role, hp: int, atk: int,
		interval: float, spd: float, rng: float, shape: UnitData.Shape,
		col: Color, sz: float, exp: int) -> UnitData:
	var u := UnitData.new()
	u.unit_id = id
	u.display_name = name
	u.role = role
	u.max_hp = hp
	u.attack = atk
	u.attack_interval = interval
	u.move_speed = spd
	u.attack_range = rng
	u.shape = shape
	u.color = col
	u.size = sz
	u.exp_reward = exp
	return u


## UnitData 얕은 복사 (동일 스탯의 새 인스턴스 — 강화 적용해도 원본 보존).
func _clone_unit(base: UnitData) -> UnitData:
	var c := UnitData.new()
	c.unit_id = base.unit_id
	c.display_name = base.display_name
	c.role = base.role
	c.max_hp = base.max_hp
	c.attack = base.attack
	c.attack_interval = base.attack_interval
	c.move_speed = base.move_speed
	c.attack_range = base.attack_range
	c.shape = base.shape
	c.color = base.color
	c.size = base.size
	c.exp_reward = base.exp_reward
	return c
