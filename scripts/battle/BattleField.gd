class_name BattleField
extends Node2D
## 단일 라인 디펜스 필드. 아군 기지(좌단 x=40) / 적 포탈(우단 x=1040).
## UnitSpawner 와 WaveManager 가 여기에 유닛/적을 소환.
## 유닛들은 전투 라인(y=528, BattleFieldView.LINE_Y)에서 좌/우로 진격.

# 라인 좌표 (BattleFieldView 와 동일)
const LINE_Y := 528.0
const ALLY_BASE_X := 60.0    # 아군 소환 위치 (기지 바로 우측)
const ENEMY_PORTAL_X := 1020.0  # 적 소환 위치 (포탈 바로 좌측)
const BASE_MAX_HP := 100

var base_hp: int = BASE_MAX_HP


## 아군 유닛 소환 (좌단에서).
func spawn_ally(unit_data: UnitData) -> Unit:
	var u := Unit.new()
	u.setup(unit_data, false)
	u.global_position = Vector2(ALLY_BASE_X, LINE_Y)
	add_child(u)
	u.died.connect(_on_unit_died)
	return u


## 적 유닛 소환 (우단에서).
func spawn_enemy(unit_data: UnitData) -> Unit:
	var u := Unit.new()
	u.setup(unit_data, true)
	u.global_position = Vector2(ENEMY_PORTAL_X, LINE_Y)
	add_child(u)
	u.died.connect(_on_unit_died)
	return u


## 기지 피해 (적이 좌단 도달 시).
func damage_base(amount: int) -> void:
	base_hp = maxi(0, base_hp - amount)
	EventBus.base_damaged.emit(amount)
	if base_hp <= 0:
		EventBus.game_over.emit(false)   # 패배


func _physics_process(_delta: float) -> void:
	# 적이 아군 기지(x < 20)에 도달하면 기지 피해
	for child in get_children():
		if child is Unit and child.is_enemy and child._alive:
			if child.global_position.x < 20.0:
				damage_base(10)
				child.queue_free()
	# 아군이 적 포탈(x > 1060)에 도달하면 해당 아군은 제거 (또는 적 기지 공격)
	# Phase 7: 단순히 제거 (Phase 8에서 적 기지 체력로 확장 가능)


func _on_unit_died(unit: Unit) -> void:
	# 사망 처리는 Unit.take_damage 에서 queue_free 까지 수행. 여기선 추가 로직만.
	pass
