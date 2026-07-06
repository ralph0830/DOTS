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

var base_hp: int = BASE_MAX_HP        # 아군 기지(좌단) 체력
var enemy_base_hp: int = BASE_MAX_HP  # 적 기지(우단) 체력 — 아군이 우단 도달 시 타격
var _game_over: bool = false          # 게임 종료 플래그 (중복 game_over emit 방지)


func _ready() -> void:
	# 초기 HP 동기화 (UI가 리스너 붙기 전일 수 있으니 call_deferred).
	call_deferred("_emit_hp")
	EventBus.game_over.connect(_on_game_over)


## 게임 종료 수신 — 중복 emit 방지용 플래그. 리스타트는 reset_run() 으로.
func _on_game_over(_victory: bool) -> void:
	_game_over = true


## 런 리스타트 (새 게임). HP/플래그 리셋 + 필드 정리.
func reset_run() -> void:
	_game_over = false
	base_hp = BASE_MAX_HP
	enemy_base_hp = BASE_MAX_HP
	for child in get_children():
		if child is Unit:
			child.queue_free()
	_emit_hp()
	EventBus.base_hp_changed.emit(base_hp, BASE_MAX_HP, enemy_base_hp, BASE_MAX_HP)


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


## 아군 기지 피해 (적이 좌단 도달 시).
func damage_base(amount: int) -> void:
	if _game_over:
		return
	base_hp = maxi(0, base_hp - amount)
	EventBus.base_damaged.emit(amount)
	_emit_hp()
	if base_hp <= 0:
		EventBus.game_over.emit(false)   # 패배


## 적 기지 피해 (아군이 우단 도달 시). 적 기지 0 이면 승리.
func damage_enemy_base(amount: int) -> void:
	if _game_over:
		return
	enemy_base_hp = maxi(0, enemy_base_hp - amount)
	_emit_hp()
	if enemy_base_hp <= 0:
		EventBus.game_over.emit(true)   # 승리


## 양 기지 HP 동기화 (UI 갱신용).
func _emit_hp() -> void:
	EventBus.base_hp_changed.emit(base_hp, BASE_MAX_HP, enemy_base_hp, BASE_MAX_HP)


func _physics_process(_delta: float) -> void:
	if _game_over:
		return
	# 적이 아군 기지(x < 20)에 도달하면 기지 피해
	for child in get_children():
		if not (child is Unit) or not child._alive:
			continue
		if child.is_enemy and child.global_position.x < 20.0:
			damage_base(10)
			child.queue_free()
		elif not child.is_enemy and child.global_position.x > 1060.0:
			# 아군이 적 포탈 도달 → 적 기지 타격 후 제거
			damage_enemy_base(15)
			child.queue_free()


func _on_unit_died(unit: Unit) -> void:
	# 사망 처리는 Unit.take_damage 에서 queue_free 까지 수행. 여기선 추가 로직만.
	pass
