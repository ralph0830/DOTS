class_name Unit
extends Area2D
## 전투 필드의 유닛/적 1체. 아군(좌→우) 또는 적(우→좌) 진격.
## 임시 렌더링: UnitData.shape/color/size 로 프로시저럴 도형 (_draw).
## 사이즈는 UnitData.size (기본 60px) — Phase 9에서 texture 교체.

signal died(unit: Unit)

var data: UnitData
var is_enemy: bool = false
var hp: int = 0
var _attack_cd: float = 0.0   # 공격 쿨타임 누적
var _target: Unit = null      # 현재 교전 중인 적
var _alive: bool = true

# 이동 방향 (아군 +1=우, 적 -1=좌)
var _direction: float = 1.0


func setup(unit_data: UnitData, enemy: bool) -> void:
	data = unit_data
	is_enemy = enemy
	hp = data.max_hp
	_direction = -1.0 if enemy else 1.0
	# 충돌 영역 설정 (도형 size 기반)
	var s := data.size
	# Area2D 콜리전: size 에 맞춘 사각형 shape
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(s * 0.7, s * 0.7)   # 시각보다 약간 작게 (자연스러운 접촉)
	col.shape = rect
	add_child(col)
	# 레이어/마스크: 아군=2, 적=3 (project.godot 정의)
	collision_layer = 4 if enemy else 2    # bit 2=Player, bit 3=Enemy
	collision_mask = 2 if enemy else 4     # 아군은 적(4) 감지, 적은 아군(2) 감지


func _ready() -> void:
	# body_entered (적 접촉) → 타겟 설정
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	if not _alive or data == null:
		return
	# 공격 쿨타임 감소
	if _attack_cd > 0.0:
		_attack_cd -= delta
	# 타겟이 사거리 내에 있으면 공격, 없으면 이동
	if _target != null and is_instance_valid(_target) and _target._alive:
		var dist := absf(global_position.x - _target.global_position.x)
		if dist <= data.attack_range:
			# 공격
			if _attack_cd <= 0.0:
				_target.take_damage(data.attack)
				_attack_cd = data.attack_interval
		else:
			# 사거리 밖이면 다시 접근
			global_position.x += _direction * data.move_speed * delta
	else:
		# 타겟 없으면 전진
		global_position.x += _direction * data.move_speed * delta
	# y는 전투 라인(BattleFieldView.LINE_Y=528)으로 고정
	global_position.y = 528.0


## 데미지 받기. 사망 시 died 시그널 emit + queue_free.
func take_damage(amount: int) -> void:
	if not _alive:
		return
	hp -= amount
	if hp <= 0:
		_alive = false
		died.emit(self)
		if is_enemy:
			EventBus.enemy_killed.emit(data.unit_id)
		else:
			EventBus.unit_died.emit(data.unit_id)
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body is Unit and body.is_enemy != is_enemy:
		_target = body


func _on_body_exited(body: Node) -> void:
	if body == _target:
		_target = null


## 임시 렌더링: 프로시저럴 도형. 텍스처가 있으면 텍스처 우선.
func _draw() -> void:
	if data == null:
		return
	if data.texture != null:
		# Phase 9: 실제 아트 텍스처 (중앙 정렬)
		var s := data.size
		draw_texture_rect(data.texture, Rect2(-s * 0.5, -s * 0.5, s, s), false)
		return
	# 임시 도형 (Phase 7)
	var s := data.size
	var col := data.color
	match data.shape:
		UnitData.Shape.CIRCLE:
			draw_circle(Vector2.ZERO, s * 0.5, col)
		UnitData.Shape.SQUARE:
			draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), col)
		UnitData.Shape.TRIANGLE:
			draw_colored_polygon(_triangle_pts(s), col)
		UnitData.Shape.DIAMOND:
			draw_colored_polygon(_diamond_pts(s), col)
	# 체력바 (도형 위에 얇은 막대) — 임시 시각 피드백
	var hp_ratio := float(hp) / float(data.max_hp) if data.max_hp > 0 else 0.0
	var bar_w := s * 0.8
	var bar_h := 4.0
	draw_rect(Rect2(-bar_w * 0.5, -s * 0.5 - 12.0, bar_w, bar_h), Color(0.2, 0.1, 0.1), true)
	draw_rect(Rect2(-bar_w * 0.5, -s * 0.5 - 12.0, bar_w * hp_ratio, bar_h), Color(0.2, 0.8, 0.3), true)


func _triangle_pts(s: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, -s * 0.5), Vector2(s * 0.5, s * 0.5), Vector2(-s * 0.5, s * 0.5)])


func _diamond_pts(s: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, -s * 0.5), Vector2(s * 0.5, 0), Vector2(0, s * 0.5), Vector2(-s * 0.5, 0)])
