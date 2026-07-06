class_name UnitSpawner
extends Node
## 슬롯 결과 → 유닛 소환 변환기. EventBus.evaluation_completed 구독 (리스너 패턴).
## SpinResult.line_wins 순회 → 매칭 심볼의 unit_id 로 유닛 소환.
## 꽝(not has_win) 시 최소 미니언 1기 보정 (GDD 핵심).
##
## 유닛 데이터(UnitData)는 resources/units/*.tres 에서 로드.
## Phase 7 임시: UnitData 인스턴스를 코드로 생성 (데이터 파일 없이).

# 심볼 ID → UnitData 매핑 (임시 생성)
var _unit_registry: Dictionary = {}
# 꽝 보정 미니언
const MISS_MINION_ID := &"minion"


func _ready() -> void:
	_build_unit_registry()
	EventBus.evaluation_completed.connect(_on_evaluation_completed)


## Phase 8 유닛 레지스트리: 기사/궁수/마법사 3종 + 꽝 보정 미니언.
## 슬롯 심볼(knight/archer/mage)과 동일 id로 매핑. skull 매칭은 unit_id="" 이므로 소환 없음.
func _build_unit_registry() -> void:
	# 기사(탱커): 높은 HP, 낮은 공격, 짧은 사거리, 방패 모양(파랑).
	_register(&"knight", _make_unit(&"knight", "Knight", UnitData.Role.TANK, 80, 8, 45.0, 55.0, UnitData.Shape.SQUARE, Color(0.25, 0.55, 0.95), 64.0))
	# 궁수(원거리 딜러): 낮은 HP, 중공격, 긴 사거리(120px), 삼각(초록).
	_register(&"archer", _make_unit(&"archer", "Archer", UnitData.Role.DEALER, 30, 12, 70.0, 120.0, UnitData.Shape.TRIANGLE, Color(0.30, 0.85, 0.45), 56.0))
	# 마법사(강력 딜러): 중간 HP, 고공격, 중사거리, 다이아(보라).
	_register(&"mage", _make_unit(&"mage", "Mage", UnitData.Role.DEALER, 40, 18, 60.0, 90.0, UnitData.Shape.DIAMOND, Color(0.70, 0.35, 0.95), 60.0))
	# 꽝 보정 미니언 (skull 매칭 없을 때/꽝일 때 1기 소환).
	_register(MISS_MINION_ID, _make_unit(MISS_MINION_ID, "Minion", UnitData.Role.MINION, 20, 5, 55.0, 50.0, UnitData.Shape.CIRCLE, Color(0.6, 0.6, 0.6), 50.0))
	# skull 심볼 매칭 → 미니언과 동일한 약한 유닛 소환 (꽝이지만 무의미하진 않게).
	_register(&"skull", _unit_registry[MISS_MINION_ID])


func _register(id: StringName, data: UnitData) -> void:
	_unit_registry[id] = data


func _make_unit(id: StringName, name: String, role: UnitData.Role, hp: int, atk: int, spd: float, rng: float, shape: UnitData.Shape, col: Color, sz: float = 60.0) -> UnitData:
	var u := UnitData.new()
	u.unit_id = id
	u.display_name = name
	u.role = role
	u.max_hp = hp
	u.attack = atk
	u.move_speed = spd
	u.attack_range = rng
	u.shape = shape
	u.color = col
	u.size = sz
	return u


## 슬롯 평가 완료 → 유닛 소환.
func _on_evaluation_completed(result: SpinResult) -> void:
	var battle := _get_battle_field()
	if battle == null:
		return
	# 꽝 보정: 매치 없으면 미니언 1기
	if not result.has_win():
		_spawn_unit(battle, MISS_MINION_ID, 1)
		return
	# 라인 매칭 순회 → 심볼의 unit_id 로 소환
	var spawned: Dictionary = {}   # unit_id → 총 소환 수 (중복 누적)
	for lw in result.line_wins:
		var sym := _lookup_symbol(lw.symbol_id)
		if sym == null or sym.unit_id == &"":
			continue   # 유닛 미매핑 심볼
		# skull(꽝)은 항상 미니언 1기만 — 3/4/5매치 관계없이 동일.
		if sym.unit_id == &"skull":
			if spawned.has(MISS_MINION_ID):
				continue   # skull 중복 매칭해도 미니언은 1기만
			spawned[MISS_MINION_ID] = 1
			continue
		var count := lw.match_count - 2   # 3매치=1기, 4매치=2기, 5매치=3기
		if count <= 0:
			count = 1
		# 동일 유닛 여러 라인 매칭 시 누적
		if spawned.has(sym.unit_id):
			spawned[sym.unit_id] += count
		else:
			spawned[sym.unit_id] = count
	# 실제 소환
	for uid in spawned:
		_spawn_unit(battle, uid, spawned[uid])


## 유닛 소환 (간격을 두고 다중 소환).
func _spawn_unit(battle: BattleField, unit_id: StringName, count: int) -> void:
	var data: UnitData = _unit_registry.get(unit_id)
	if data == null:
		return
	for i in range(count):
		# 약간의 간격으로 소환 (중첩 방지)
		var u: Unit = battle.spawn_ally(data)
		u.global_position.x -= float(i) * 20.0   # 좌측으로 20px씩 오프셋
	EventBus.unit_spawned.emit(unit_id, count)


## 심볼 ID 로 SymbolData 조회.
func _lookup_symbol(sym_id: StringName) -> SymbolData:
	var config := GameConfig.config
	if config == null:
		return null
	for sym in config.symbols:
		if sym.id == sym_id:
			return sym
	return null


## BattleField 참조 획득 (SlotMachineView 자식).
func _get_battle_field() -> BattleField:
	var smv := get_tree().get_first_node_in_group(&"slot_machine_view") if get_tree().has_group(&"slot_machine_view") else null
	if smv != null and smv.has_node("BattleField"):
		return smv.get_node("BattleField") as BattleField
	# 폴백: 씬에서 BattleField 타입 노드 검색
	for n in get_tree().get_nodes_in_group(&"battle_field"):
		return n as BattleField
	return null
