extends Node
## UnitRegistry — 모든 유닛(아군/적) UnitData 의 중앙 관리 autoload (Phase 8-C/D).
## UnitSpawner(아군 소환)와 WaveManager(적 스폰)가 각자 하드코딩하던 데이터를 통합.
##
## 설계 (open-structure):
##   - 데이터는 resources/units/{ally,enemy}/*.tres 에서 로드 (에디터 인스펙터로 튜닝).
##   - .tres 가 없으면 코드 생성 폴백 (안전망 — generate_default_data.gd 미실행 시).
##   - UnitSpawner/WaveManager는 조회만 (결합도 감소).
##   - LordState 티어업 연동점: get_ally_unit() 호출 시 LordState.unit_tier를 반영.
##
## 아군 4종 (슬롯 심볼 매칭으로 소환): knight/archer/mage/minion(꽝 보정).
## 적 3종 (WAVE 스폰): goblin/orc/boss.

const UNIT_ALLY_DIR := "res://resources/units/ally/"
const UNIT_ENEMY_DIR := "res://resources/units/enemy/"

# ★ 컴파일 타임 의존성 강제 참조 (export 포함 보장).
# Godot export 는 의존성 그래프상 도달 가능한 리소스만 PCK/APK 에 포함한다.
# 런타임 DirAccess + load() 만으로는 참조로 인식되지 않아 .tres 가 제외되고, .remap
# 파일만 남아 실제 .res 가 APK 에 누락되는 버그가 발생한다 (문제 2).
# preload 상수는 컴파일 타임에 평가되어 의존성 엣지를 생성 → export 에 확정 포함.
# 새 유닛 .tres 추가 시 이 목록에 한 줄을 추가할 것 (에디터 인스펙터 튜닝과 병행).
const _REQUIRED_ALLIES: Array = [
	preload("res://resources/units/ally/knight.tres"),
	preload("res://resources/units/ally/archer.tres"),
	preload("res://resources/units/ally/mage.tres"),
	preload("res://resources/units/ally/minion.tres"),
]
const _REQUIRED_ENEMIES: Array = [
	preload("res://resources/units/enemy/goblin.tres"),
	preload("res://resources/units/enemy/orc.tres"),
	preload("res://resources/units/enemy/boss.tres"),
]

var _allies: Dictionary = {}   # StringName → UnitData
var _enemies: Dictionary = {}  # StringName → UnitData
var _initialized: bool = false


func _ready() -> void:
	initialize()


## 유닛 데이터 로드. preload 확정 멤버 → DirAccess 보완 → 코드 생성 폴백 순.
func initialize() -> void:
	_allies.clear()
	_enemies.clear()
	# 1. preload 확정 멤버 우선 등록 — 의존성 보장 + 결정론적 로드 (DirAccess 순서 비결정성 제거).
	for entry in _REQUIRED_ALLIES:
		var data_a := entry as UnitData
		if data_a != null and data_a.unit_id != &"":
			_allies[data_a.unit_id] = data_a
	for entry in _REQUIRED_ENEMIES:
		var data_e := entry as UnitData
		if data_e != null and data_e.unit_id != &"":
			_enemies[data_e.unit_id] = data_e
	# 2. DirAccess 보완 — 추가 .tres 발견 (open-structure 확장 포인트, preload 목록 외 신규 유닛).
	_load_from_dir(UNIT_ALLY_DIR, true)
	_load_from_dir(UNIT_ENEMY_DIR, false)
	# 3. 폴백: preload + DirAccess 모두 비었으면 코드 생성 (안전망 — .tres 자체가 없을 때).
	if _allies.is_empty():
		print("[UnitRegistry] 아군 .tres 없음 — 코드 생성 폴백")
		_build_ally_fallback()
	if _enemies.is_empty():
		print("[UnitRegistry] 적 .tres 없음 — 코드 생성 폴백")
		_build_enemy_fallback()
	# skull 심볼 매칭 → 미니언 alias (별도 .tres 없이).
	if _allies.has(&"minion") and not _allies.has(&"skull"):
		_allies[&"skull"] = _allies[&"minion"]
	_initialized = true


## 디렉토리 내 모든 .tres 로드. 하나라도 로드되면 true.
func _load_from_dir(dir_path: String, is_ally: bool) -> bool:
	if not DirAccess.dir_exists_absolute(dir_path):
		return false
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return false
	var loaded_any := false
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res_path := dir_path + fname
			var data: UnitData = load(res_path)
			if data != null and data.unit_id != &"":
				if is_ally:
					_allies[data.unit_id] = data
				else:
					_enemies[data.unit_id] = data
				loaded_any = true
		fname = dir.get_next()
	dir.list_dir_end()
	return loaded_any


# --- 코드 생성 폴백 (.tres 미존재 시 안전망) ---

func _build_ally_fallback() -> void:
	_register_ally(&"knight", _make(&"knight", "Knight", UnitData.Role.TANK,
		80, 8, 1.0, 45.0, 55.0, UnitData.Shape.SQUARE, Color(0.25, 0.55, 0.95), 64.0, 0))
	_register_ally(&"archer", _make(&"archer", "Archer", UnitData.Role.DEALER,
		30, 12, 0.9, 70.0, 120.0, UnitData.Shape.TRIANGLE, Color(0.30, 0.85, 0.45), 56.0, 0, 0,
		true, 260.0, 10.0, Color(0.30, 0.85, 0.45)))
	_register_ally(&"mage", _make(&"mage", "Mage", UnitData.Role.DEALER,
		40, 18, 1.1, 60.0, 90.0, UnitData.Shape.DIAMOND, Color(0.70, 0.35, 0.95), 60.0, 0, 0,
		true, 200.0, 14.0, Color(0.70, 0.35, 0.95)))
	_register_ally(&"minion", _make(&"minion", "Minion", UnitData.Role.MINION,
		20, 5, 1.0, 55.0, 50.0, UnitData.Shape.CIRCLE, Color(0.6, 0.6, 0.6), 50.0, 0))


func _build_enemy_fallback() -> void:
	_register_enemy(&"goblin", _make(&"goblin", "Goblin", UnitData.Role.ENEMY,
		20, 6, 1.0, 50.0, 50.0, UnitData.Shape.CIRCLE, Color(0.8, 0.2, 0.2), 60.0, 1, 5))
	_register_enemy(&"orc", _make(&"orc", "Orc", UnitData.Role.ENEMY,
		40, 10, 1.0, 40.0, 60.0, UnitData.Shape.SQUARE, Color(0.7, 0.3, 0.1), 60.0, 3, 15))
	_register_enemy(&"boss", _make(&"boss", "Boss", UnitData.Role.ENEMY,
		150, 20, 1.2, 35.0, 80.0, UnitData.Shape.DIAMOND, Color(0.9, 0.1, 0.3), 80.0, 10, 100))


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
		col: Color, sz: float, exp: int, credit: int = 0,
		is_ranged: bool = false, proj_speed: float = 220.0,
		proj_size: float = 12.0, proj_color: Color = Color.WHITE) -> UnitData:
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
	u.size_w = sz
	u.size_h = sz
	u.exp_reward = exp
	u.credit_reward = credit
	u.is_ranged = is_ranged
	u.behavior = UnitData.Behavior.RANGED if is_ranged else UnitData.Behavior.MELEE
	u.projectile_speed = proj_speed
	u.projectile_size = proj_size
	u.projectile_color = proj_color
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
	c.size_w = base.size_w
	c.size_h = base.size_h
	c.exp_reward = base.exp_reward
	c.credit_reward = base.credit_reward
	c.texture = base.texture   # ★ 스프라이트 복사 — 누락 시 도형 폴백 (이전 "도형으로 나옴" 버그 원인)
	# 투사체 속성 복사 — 누락 시 폴백 경로 유닛이 근접으로 변신 (texture 복사 누락과 동일 패턴).
	c.is_ranged = base.is_ranged
	c.behavior = base.behavior
	c.projectile_speed = base.projectile_speed
	c.projectile_size = base.projectile_size
	c.projectile_color = base.projectile_color
	c.projectile_texture = base.projectile_texture
	return c
