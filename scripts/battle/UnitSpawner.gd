class_name UnitSpawner
extends Node
## 슬롯 결과 → 유닛 소환 변환기. EventBus.evaluation_completed 구독 (리스너 패턴).
## SpinResult.line_wins 순회 → 매칭 심볼의 unit_id 로 유닛 소환.
## 꽝(not has_win) 시 최소 미니언 1기 보정 (GDD 핵심).
##
## Phase 8-C: 유닛 데이터는 UnitRegistry autoload 에서 조회 (중앙 관리).
## 이 스크립트는 소환 변환 로직만 담당 — 데이터 생성/관리 책임 제거.

const MISS_MINION_ID := &"minion"


func _ready() -> void:
	EventBus.evaluation_completed.connect(_on_evaluation_completed)


## 슬롯 평가 완료 → 유닛 소환.
func _on_evaluation_completed(result: SpinResult) -> void:
	var battle := _get_battle_field()
	if battle == null:
		return
	# 꽝 보정: 매치 없으면 미니언 1기.
	# LordState.miss_compensation 강화 시 미니언 수 증가 (Phase 8-D 연동).
	var miss_count := _get_miss_compensation_count()
	if not result.has_win():
		_spawn_unit(battle, MISS_MINION_ID, miss_count)
		return
	# 라인 매칭 순회 → 심볼의 unit_id 로 소환
	var spawned: Dictionary = {}   # unit_id → 총 소환 수 (중복 누적)
	for lw in result.line_wins:
		var sym := _lookup_symbol(lw.symbol_id)
		if sym == null or sym.unit_id == &"":
			continue   # 유닛 미매핑 심볼
		# skull(꽝)은 미니언으로 소환 (3/4/5매치 관계없이 miss_count 고정).
		if sym.unit_id == &"skull":
			if not spawned.has(MISS_MINION_ID):
				spawned[MISS_MINION_ID] = miss_count
			continue
		var count := lw.match_count - 2   # 3매치=1기, 4매치=2기, 5매치=3기
		if count <= 0:
			count = 1
		if spawned.has(sym.unit_id):
			spawned[sym.unit_id] += count
		else:
			spawned[sym.unit_id] = count
	# 실제 소환
	for uid in spawned:
		_spawn_unit(battle, uid, spawned[uid])


## 꽝 보정 미니언 소환 수. LordState.miss_compensation 에 비례 (기본 1, 강화 시 +1씩).
func _get_miss_compensation_count() -> int:
	var lord := get_node_or_null("/root/LordState")
	if lord != null and lord.has_method("get_state_summary"):
		var summary: Dictionary = lord.get_state_summary()
		var comp: int = int(summary.get("miss_compensation", 0))
		return 1 + comp   # 기본 1 + 강화 레벨
	return 1


## 유닛 소환 (간격을 두고 다중 소환).
func _spawn_unit(battle: BattleField, unit_id: StringName, count: int) -> void:
	# UnitRegistry 에서 현재 LordState 티어가 반영된 UnitData 조회.
	var data: UnitData = UnitRegistry.get_ally_unit(unit_id)
	if data == null:
		return
	for i in range(count):
		var u: Unit = battle.spawn_ally(data)
		u.global_position.x -= float(i) * 20.0   # 좌측으로 20px 오프셋 (중첩 방지)
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
