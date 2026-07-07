class_name WaveManager
extends Node
## WAVE 시스템 — 일정 시간 간격으로 적 포탈(우단)에서 적을 스폰.
## WAVE 증가 시 적 수/강도 증가.
## Phase 8-C: 적 유닛 데이터는 UnitRegistry autoload 에서 조회 (중앙 관리).

signal wave_changed(wave_num: int)

const WAVE_DURATION := 20.0   # WAVE 1회 지속 시간 (초)
const ENEMY_BASE_COUNT := 5   # WAVE 1 적 기본 수
const ENEMY_SPAWN_INTERVAL := 2.5   # 적 스폰 간격 (초)

var _wave_num := 0
var _wave_timer := 0.0
var _spawn_timer := 0.0
var _enemies_to_spawn := 0
var _enemy_killed_in_wave := 0


func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.game_over.connect(_on_game_over)
	# 첫 WAVE 시작 (약간의 대기 후)
	_wave_timer = -5.0   # 첫 WAVE 전 5초 대기


func _physics_process(delta: float) -> void:
	_wave_timer += delta
	# WAVE 시작 조건:
	#   (a) 대기 중(_wave_num == 0, 타이머 >= 0) → 첫 WAVE 즉시 시작
	#   (b) WAVE 진행 중(타이머 >= WAVE_DURATION) → 다음 WAVE
	if _wave_num == 0 and _wave_timer >= 0.0:
		_start_next_wave()
	elif _wave_num > 0 and _wave_timer >= WAVE_DURATION:
		_start_next_wave()
	# 적 스폰 처리
	if _enemies_to_spawn > 0:
		_spawn_timer += delta
		if _spawn_timer >= ENEMY_SPAWN_INTERVAL:
			_spawn_timer = 0.0
			_spawn_enemy()
			_enemies_to_spawn -= 1


func _start_next_wave() -> void:
	_wave_num += 1
	_wave_timer = 0.0
	_spawn_timer = 0.0
	_enemy_killed_in_wave = 0
	# 적 수: WAVE 번호 비례 증가
	_enemies_to_spawn = ENEMY_BASE_COUNT + (_wave_num - 1) * 2
	# 보스 WAVE (5번째마다)
	if _wave_num % 5 == 0:
		_enemies_to_spawn += 1   # 보스 1기 추가
	print("[wave] WAVE %d 시작 — 적 %d체 예정" % [_wave_num, _enemies_to_spawn])
	EventBus.wave_started.emit(_wave_num)
	wave_changed.emit(_wave_num)


func _spawn_enemy() -> void:
	var battle := _get_battle_field()
	if battle == null:
		return
	# 보스 WAVE 마지막에 보스 스폰
	var enemy_id: StringName = &"goblin"
	if _wave_num % 5 == 0 and _enemies_to_spawn == 1:
		enemy_id = &"boss"
	elif _wave_num >= 3 and randf() < 0.3:
		enemy_id = &"orc"
	# Phase 8-C: UnitRegistry 에서 적 UnitData 조회.
	var data: UnitData = UnitRegistry.get_enemy_unit(enemy_id)
	if data != null:
		battle.spawn_enemy(data)
		EventBus.enemy_spawned.emit(enemy_id)


func _on_enemy_killed(_enemy_id: StringName, _exp_reward: int) -> void:
	_enemy_killed_in_wave += 1


func _on_game_over(_victory: bool) -> void:
	set_physics_process(false)   # 게임 종료 시 WAVE 정지


## 런 리스타트 (GameOverOverlay 에서 호출). WAVE 1부터 재개.
func restart() -> void:
	_wave_num = 0
	_wave_timer = -3.0   # 첫 WAVE 전 3초 대기
	_spawn_timer = 0.0
	_enemies_to_spawn = 0
	_enemy_killed_in_wave = 0
	set_physics_process(true)


func _get_battle_field() -> BattleField:
	var smv := get_tree().get_first_node_in_group(&"slot_machine_view") if get_tree().has_group(&"slot_machine_view") else null
	if smv != null and smv.has_node("BattleField"):
		return smv.get_node("BattleField") as BattleField
	return null
