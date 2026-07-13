class_name WaveManager
extends Node
## 데이터 주도 웨이브 매니저. WaveData(SpawnInfo 목록) 타임라인 기반 적 스폰.
## docs/WAVE_MANAGER.md 명세. _physics_process delta 눈적 = elapsed_time (SPD time_scale 연동).
## DDA: WalletManager.bet_level × count_per_tick. 보스 웨이브 트리거(is_boss_wave).
##
## 데이터/로직 분리: wave_data_list(Array[WaveData]) 는 외부 주입 또는 _build_default_waves(MVP).
## 추후 generate_default_data 로 .tres 생성 → preload 로드(모바일 export 안전).

signal wave_changed(wave_num: int)

var wave_data_list: Array[WaveData] = []     # 웨이브 데이터(MVP: 코드 빌드)
var current_wave_idx: int = -1
var elapsed_time: float = 0.0
var active_spawns: Array[Dictionary] = []    # {info: SpawnInfo, next_spawn_time: float}
var is_wave_running: bool = false
var _is_clearing: bool = false               # 스폰 종료 → 적 0 대기
var _enemy_killed_in_wave: int = 0
var _battle: BattleField = null


func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.game_over.connect(_on_game_over)
	if wave_data_list.is_empty():
		wave_data_list = _build_default_waves()
	call_deferred("_start_first_wave_delayed")


## 첫 웨이브 전 3초 대기(준비 시간).
func _start_first_wave_delayed() -> void:
	await get_tree().create_timer(3.0).timeout
	if not is_wave_running and current_wave_idx < 0:
		start_next_wave()


## 기본 웨이브 데이터 빌드(MVP — 추후 .tres/CSV 로 교체 확장 포인트).
func _build_default_waves() -> Array[WaveData]:
	var waves: Array[WaveData] = []
	# WAVE 1: goblin 0~20초, 4초마다 1마리.
	waves.append(_make_wave(1, false, &"boss", [
		_make_spawn(&"goblin", 0.0, 20.0, 4.0, 1),
	]))
	# WAVE 2: goblin 0~20초 3초 + orc 10~25초 5초.
	waves.append(_make_wave(2, false, &"boss", [
		_make_spawn(&"goblin", 0.0, 20.0, 3.0, 1),
		_make_spawn(&"orc", 10.0, 25.0, 5.0, 1),
	]))
	# WAVE 3: goblin 물량 + orc.
	waves.append(_make_wave(3, false, &"boss", [
		_make_spawn(&"goblin", 0.0, 20.0, 2.5, 2),
		_make_spawn(&"orc", 5.0, 25.0, 4.0, 1),
	]))
	# WAVE 4: 혼합 물량 러시.
	waves.append(_make_wave(4, false, &"boss", [
		_make_spawn(&"goblin", 0.0, 25.0, 2.0, 2),
		_make_spawn(&"orc", 5.0, 25.0, 3.0, 2),
	]))
	# WAVE 5: 보스 + goblin 호위.
	waves.append(_make_wave(5, true, &"boss", [
		_make_spawn(&"goblin", 0.0, 15.0, 3.0, 1),
	]))
	return waves


func _make_spawn(mid: StringName, st: float, et: float, delay: float, cnt: int) -> SpawnInfo:
	var s := SpawnInfo.new()
	s.monster_id = mid
	s.start_time = st
	s.end_time = et
	s.spawn_delay = delay
	s.count_per_tick = cnt
	return s


func _make_wave(num: int, boss: bool, boss_id: StringName, spawns: Array) -> WaveData:
	var w := WaveData.new()
	w.wave_number = num
	w.is_boss_wave = boss
	w.boss_id = boss_id
	for s in spawns:
		w.spawn_list.append(s)
	return w


func _physics_process(_delta: float) -> void:
	if not is_wave_running:
		return
	if _is_clearing:
		_check_enemy_clear()
		return
	elapsed_time += _delta
	# 활성 스폰 그룹 순회 — 타임라인 내 주기 도달 시 스폰.
	var all_done := true
	for entry in active_spawns:
		var info: SpawnInfo = entry["info"]
		if elapsed_time >= info.start_time and elapsed_time <= info.end_time:
			all_done = false
			if elapsed_time >= entry["next_spawn_time"]:
				_execute_spawn(info)
				entry["next_spawn_time"] = elapsed_time + info.spawn_delay
		elif elapsed_time < info.end_time:
			all_done = false
	# 모든 스폰 종료 → 적 0 대기로 전환.
	if all_done and active_spawns.size() > 0:
		_is_clearing = true
		active_spawns.clear()


## 스폰 실행 — DDA(bet_level × count_per_tick) 적용.
func _execute_spawn(info: SpawnInfo) -> void:
	var battle := _get_battle_field()
	if battle == null:
		return
	var data: UnitData = UnitRegistry.get_enemy_unit(info.monster_id)
	if data == null:
		return
	var final_count: int = maxi(1, info.count_per_tick * WalletManager.bet_level)
	for i in range(final_count):
		var u: Unit = battle.spawn_enemy(data)
		if u != null:
			u.global_position.x += float(i) * 20.0   # 중첩 방지 오프셋
	EventBus.enemy_spawned.emit(info.monster_id)


## 외부 다음 웨이브 시작.
func start_next_wave() -> void:
	if current_wave_idx >= wave_data_list.size() - 1:
		# 다음이 없으면 이미 마지막 이후 — stage_clear 처리는 클리어 시점에서.
		return
	current_wave_idx += 1
	_begin_wave(wave_data_list[current_wave_idx])


## 웨이브 시작 공통 — active_spawns 큐 빌드 + 보스 스폰.
func _begin_wave(wd: WaveData) -> void:
	elapsed_time = 0.0
	active_spawns.clear()
	_is_clearing = false
	is_wave_running = true
	_enemy_killed_in_wave = 0
	for info in wd.spawn_list:
		active_spawns.append({"info": info, "next_spawn_time": info.start_time})
	EventBus.wave_started.emit(wd.wave_number)
	wave_changed.emit(wd.wave_number)
	print("[wave] WAVE %d 시작%s — 스폰그룹 %d" % [wd.wave_number, " (보스전)" if wd.is_boss_wave else "", wd.spawn_list.size()])
	# 보스 웨이브 시 보스 즉시 소환(spawn_list 호위와 병행).
	if wd.is_boss_wave:
		_spawn_boss(wd.boss_id)
	# 스폰 그룹이 없으면(보스만) 즉시 적 0 대기로 전환 — 아니면 _physics_process 가 all_done 전환을 못 함.
	if wd.spawn_list.is_empty():
		_is_clearing = true


## 보스 소환.
func _spawn_boss(boss_id: StringName) -> void:
	var battle := _get_battle_field()
	if battle == null:
		return
	var data: UnitData = UnitRegistry.get_enemy_unit(boss_id)
	if data == null:
		return
	battle.spawn_enemy(data)
	EventBus.enemy_spawned.emit(boss_id)


## 적 0 체크 — BattleField 자식 중 살아있는 적 유닛.
func _check_enemy_clear() -> void:
	var battle := _get_battle_field()
	if battle == null:
		return
	for child in battle.get_children():
		if child is Unit and child.is_enemy and child._alive:
			return   # 아직 적 남음
	_on_wave_enemies_cleared()


## 웨이브 클리어 — 다음 웨이브 또는 스테이지 클리어.
func _on_wave_enemies_cleared() -> void:
	_is_clearing = false
	is_wave_running = false
	var wd: WaveData = wave_data_list[current_wave_idx]
	EventBus.wave_cleared.emit(wd.wave_number)
	print("[wave] WAVE %d 클리어 — 다음으로" % wd.wave_number)
	if current_wave_idx >= wave_data_list.size() - 1:
		_on_stage_clear()
		return
	# 뱀서식 정비 턴(2초) 후 다음 웨이브.
	await get_tree().create_timer(2.0).timeout
	start_next_wave()


func _on_stage_clear() -> void:
	EventBus.game_over.emit(true)   # 승리


func _on_enemy_killed(_enemy_id: StringName, _exp_reward: int) -> void:
	_enemy_killed_in_wave += 1


func _on_game_over(_victory: bool) -> void:
	set_physics_process(false)
	is_wave_running = false
	_is_clearing = false


## 런 리스타트(GameOverOverlay). WAVE 1부터 재개.
func restart() -> void:
	current_wave_idx = -1
	elapsed_time = 0.0
	active_spawns.clear()
	is_wave_running = false
	_is_clearing = false
	_enemy_killed_in_wave = 0
	set_physics_process(true)
	call_deferred("_start_first_wave_delayed")


## BattleField 참조(UnitSpawner._get_battle_field 패턴, 캐시).
func _get_battle_field() -> BattleField:
	if _battle != null and is_instance_valid(_battle):
		return _battle
	var tree := get_tree()
	if tree == null or not tree.has_group(&"slot_machine_view"):
		return null
	var smv: Node = tree.get_first_node_in_group(&"slot_machine_view")
	if smv != null and smv.has_node("BattleField"):
		_battle = smv.get_node("BattleField") as BattleField
	return _battle
