extends Node
## ArtifactManager — 활성 유물 효과를 전장에 적용하는 autoload (Phase 8-E).
## DefenseArtifactEffect.apply() → register(id) 로 유물 활성화.
## 이 매니저가 실제 전장 효과(도트 데미지, 피해 흡수)를 발동.
##
## 설계 (open-structure):
##   - BattleField/Unit 를 직접 참조하지 않고 EventBus 시그널 + 그룹 노드 조회.
##   - 새 유물 효과 추가 시: _apply_tick_effect(id) / _on_base_damaged 에 케이스 추가.
##
## 알베르트 수비 유물 2종 (PRD §3.3):
##   - spike_barricade: 기지 근처(x<150) 적에게 도트 데미지 (5 dmg / 0.5초).
##   - magic_shield: 기지 피해의 50%% 흡수 (최대 50 흡수).

# 활성화된 유물 id 목록.
var _active: Array[StringName] = []

# 유물별 런타임 상태.
var _spike_tick: float = 0.0          # 가시 바리케이드 도트 데미지 타이머
var _shield_hp: float = 0.0           # 마력 보호막 잔여 흡수량
const _SHIELD_MAX: float = 50.0       # 보호막 최대 흡수량 (선택 시 충전)
const _SPIKE_RANGE_X: float = 150.0   # 가시 바리케이드 효과 범위 (기지로부터 x 거리)
const _SPIKE_DAMAGE: int = 5          # 가시 바리케이드 도트 데미지
const _SPIKE_INTERVAL: float = 0.5    # 가시 바리케이드 데미지 주기 (초)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.base_damaged.connect(_on_base_damaged)


## 런 시작 시 초기화 (SlotMachineView._initialize_all 에서 호출).
func initialize() -> void:
	_active.clear()
	_spike_tick = 0.0
	_shield_hp = 0.0


## 유물 활성화 (DefenseArtifactEffect.apply 에서 호출).
func register(id: StringName) -> void:
	if _active.has(id):
		return
	_active.append(id)
	# 유물별 초기화.
	if id == &"magic_shield":
		_shield_hp = _SHIELD_MAX
	print("[ArtifactManager] 유물 활성화: %s (활성 %d개)" % [id, _active.size()])


## 유물 비활성화 (향후 제거 기능용).
func unregister(id: StringName) -> void:
	_active.erase(id)


## 유물 보유 여부.
func has(id: StringName) -> bool:
	return _active.has(id)


func _physics_process(delta: float) -> void:
	# 가시 바리케이드: 기지 근처 적에게 도트 데미지.
	if _active.has(&"spike_barricade"):
		_spike_tick += delta
		if _spike_tick >= _SPIKE_INTERVAL:
			_spike_tick = 0.0
			_apply_spike_damage()


## 가시 바리케이드 데미지 적용 — BattleField 의 적 유닛 중 x<SPIKE_RANGE_X 에게 데미지.
func _apply_spike_damage() -> void:
	var battle := _get_battle_field()
	if battle == null:
		return
	var hit_count := 0
	for child in battle.get_children():
		if not (child is Unit) or not child._alive or not child.is_enemy:
			continue
		if child.global_position.x < _SPIKE_RANGE_X:
			child.take_damage(_SPIKE_DAMAGE)
			hit_count += 1
	if hit_count > 0:
		print("[ArtifactManager] 가시 바리케이드: 적 %d체에 %d 데미지" % [hit_count, _SPIKE_DAMAGE])


## 기지 피해 수신 — 마력 보호막이 활성 시 피해 흡수.
## 실제 피해 감소는 BattleField.damage_base 호출 전에 이루어져야 하므로,
## 여기서는 흡수량을 추적만 하고, BattleField 가 호출 시점에 이 값을 조회하도록 함.
func _on_base_damaged(amount: int) -> void:
	if not _active.has(&"magic_shield") or _shield_hp <= 0.0:
		return
	# 흡수 처리: 피해량의 일부를 보호막이 대신 받음.
	# 주의: base_damaged는 이미 피해가 반영된 후 emit 되므로,
	# 실제 흡수는 BattleField.damage_base 에서 shield_hp를 조회하는 방식이 필요.
	# Phase 8-E 프로토타입: 보호막이 피해를 대신 받은 만큼 base_hp 회복 (치료 형태).
	var absorb := minf(_shield_hp, float(amount) * 0.5)
	if absorb > 0.0:
		_shield_hp -= absorb
		var battle := _get_battle_field()
		if battle != null:
			battle.base_hp = mini(battle.BASE_MAX_HP, battle.base_hp + int(absorb))
			EventBus.base_hp_changed.emit(battle.base_hp, battle.BASE_MAX_HP, battle.enemy_base_hp, battle.BASE_MAX_HP)
		print("[ArtifactManager] 마력 보호막 흡수: %d (잔여 %d)" % [int(absorb), int(_shield_hp)])


## 현재 보호막 잔여 흡수량 (UI 표시용).
func get_shield_hp() -> float:
	return _shield_hp


## BattleField 참조 획득 (SlotMachineView 자식).
func _get_battle_field() -> Node:
	var smv := get_tree().get_first_node_in_group(&"slot_machine_view") if get_tree().has_group(&"slot_machine_view") else null
	if smv != null and smv.has_node("BattleField"):
		return smv.get_node("BattleField")
	return null
