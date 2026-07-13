class_name BattleField
extends Node2D
## 단일 라인 디펜스 필드. 아군 기지(좌단) / 적 포탈(우단).
## UnitSpawner 와 WaveManager 가 여기에 유닛/적을 소환.
## 유닛들은 전투 라인(Layout.line_y)에서 좌/우로 진격.
## 라인/기지/판정 좌표는 Layout autoload (vp 비례) 로 통일 — 세로 해상도/비율 대응.

const BASE_MAX_HP := 100

var base_hp: int = BASE_MAX_HP        # 아군 기지(좌단) 체력
var enemy_base_hp: int = BASE_MAX_HP  # 적 기지(우단) 체력 — 아군이 우단 도달 시 타격
var _game_over: bool = false          # 게임 종료 플래그 (중복 game_over emit 방지)
var _damage_layer: DamageNumberLayer  # 데미지 숫자 이펙트 레이어 (자식)


func _ready() -> void:
	# 초기 HP 동기화 (UI가 리스너 붙기 전일 수 있으니 call_deferred).
	call_deferred("_emit_hp")
	EventBus.game_over.connect(_on_game_over)
	# 데미지 숫자 레이어 — Unit 과 동일 좌표계(Node2D).
	_damage_layer = DamageNumberLayer.new()
	_damage_layer.name = "DamageNumberLayer"
	add_child(_damage_layer)


## 게임 종료 수신 — 중복 emit 방지용 플래그. 리스타트는 reset_run() 으로.
func _on_game_over(_victory: bool) -> void:
	_game_over = true
	# ★ 자식 Unit 들의 _physics_process 도 정지 — 게임오버 연출 중 유닛이 계속
	#   이동/공격하는 것을 방지 (WaveManager 만 정지로는 부족). reset_run 에서 복원.
	#   Projectile 도 함께 정지 — 연출 중 투사체가 계속 비행하는 것 방지.
	for child in get_children():
		if child is Unit or child is Projectile:
			child.set_physics_process(false)


## 런 리스타트 (새 게임). HP/플래그 리셋 + 필드 정리.
func reset_run() -> void:
	_game_over = false
	base_hp = BASE_MAX_HP
	enemy_base_hp = BASE_MAX_HP
	for child in get_children():
		# ★ Unit + Projectile 모두 회수 — 투사체는 Unit 이 아니라 BattleField 자식이므로
		#   별도 조건 없으면 리스타트 시 잔류(다음 프레임 자연 free 되긴 하나 깔끔하지 않음).
		if child is Unit or child is Projectile:
			child.queue_free()
	# 데미지 숫자 이펙트도 회수 (활성 tween kill).
	if _damage_layer != null:
		_damage_layer.clear()
	_emit_hp()   # base_hp_changed emit (아래 중복 emit 제거됨 — _emit_hp 와 동일)


## 아군 유닛 소환 (좌단에서).
func spawn_ally(unit_data: UnitData) -> Unit:
	var u := Unit.new()
	u.setup(unit_data, false)
	u.position = Vector2(Layout.ally_base_x(), Layout.line_y())
	add_child(u)
	u.died.connect(_on_unit_died)
	return u


## 적 유닛 소환 (우단에서).
func spawn_enemy(unit_data: UnitData) -> Unit:
	var u := Unit.new()
	u.setup(unit_data, true)
	u.position = Vector2(Layout.enemy_portal_x(), Layout.line_y())
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
	# 뷰 offset — 카메라 x 반영 (전투 필드 스크롤). 유닛은 로컬 field 좌표 유지.
	position.x = -Layout.camera_x()
	# 기지 도달 판정 (field 좌표 = 로컬 position).
	for child in get_children():
		if not (child is Unit) or not child._alive:
			continue
		if child.is_enemy and child.position.x < Layout.ally_threshold_x():
			damage_base(10)
			child.queue_free()
		elif not child.is_enemy and child.position.x > Layout.enemy_threshold_x():
			# 아군이 적 포탈 도달 → 적 기지 타격 후 제거
			damage_enemy_base(15)
			child.queue_free()


func _on_unit_died(unit: Unit) -> void:
	# 사망 처리는 Unit.take_damage 에서 queue_free 까지 수행. 여기선 추가 로직만.
	pass
