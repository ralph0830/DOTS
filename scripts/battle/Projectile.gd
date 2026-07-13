class_name Projectile
extends Node2D
## 원거리 유닛(궁수/마법사)의 투사체. 발사자 위치에서 target 을 직접 추적해 비행.
## 도달(거리 ≤ HIT_RANGE) 시 target.take_damage() 호출 → 점멸/데미지숫자 자동 트리거.
## target 이 사망/무효하면 데미지 없이 증발(자연스러운 빗나감).
##
## Node2D + _draw (Area2D 아님) — 단일 라인 전투라 충돌 영역이 불필요하고,
## 모바일에서 물리 공간 등록 오버헤드를 최소화한다.
## 차후 projectile_texture 할당 시 이미지로 교체 (현재는 색상 원).

const HIT_RANGE: float = 12.0   # target 에게 도달한 것으로 판정할 거리(px)

var _target: Unit = null        # 추적 대상
var _damage: int = 0
var _speed: float = 220.0
var _color: Color = Color.WHITE
var _size: float = 12.0
var _texture: Texture2D = null  # 차후 이미지 교체


func setup(damage: int, target: Unit, speed: float, color: Color, size: float, texture: Texture2D = null) -> void:
	_damage = damage
	_target = target
	_speed = speed
	_color = color
	_size = size
	_texture = texture


func _physics_process(delta: float) -> void:
	# target 이 사망/무효하면 데미지 없이 증발 (자연스러운 빗나감).
	if not is_instance_valid(_target):
		queue_free()
		return
	var to: Vector2 = _target.position - position
	if to.length() <= HIT_RANGE:
		# 도달 → 타격. 점멸 + 데미지숫자는 take_damage 안에서 자동 트리거된다.
		_target.take_damage(_damage)
		queue_free()
		return
	position += to.normalized() * _speed * delta


func _draw() -> void:
	if _texture != null:
		# 차후 이미지 교체 경로 (현재 미사용).
		var d := _size
		draw_texture_rect(_texture, Rect2(-d * 0.5, -d * 0.5, d, d), false)
		return
	# 폴백: 색상 원 (궁수=초록, 마법사=보라 등 유닛 고유색).
	draw_circle(Vector2.ZERO, _size * 0.5, _color)
