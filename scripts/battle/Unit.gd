class_name Unit
extends Area2D
## 전투 필드의 유닛/적 1체. 아군(좌→우) 또는 적(우→좌) 진격.
## 렌더링: UnitData.texture 우선 (64px 픽셀 아트). 없으면 프로시저럴 도형.
## 소스 스프라이트는 모두 좌향 기준 → 아군은 우향 flip, 적은 좌향 그대로.

signal died(unit: Unit)

# 히트/감지 영역(충돌 shape) 시각화 — 테스트용. 출시/검증 완료로 false.
const DEBUG_HITBOX := false

var data: UnitData
var is_enemy: bool = false
var hp: int = 0
var _attack_cd: float = 0.0   # 공격 쿨타임 누적
var _target: Unit = null      # 현재 교전 중인 적
var _alive: bool = true
var _hit_flash: float = 0.0   # 피격 점멸 강도(0~1). _draw 에서 본체 색상을 빨강으로 lerp.

# 이동 방향 (아군 +1=우, 적 -1=좌)
var _direction: float = 1.0


func setup(unit_data: UnitData, enemy: bool) -> void:
	data = unit_data
	is_enemy = enemy
	hp = data.max_hp
	_direction = -1.0 if enemy else 1.0
	# 충돌/감지 영역: 공격 사거리 기반 (원거리 유닛은 더 일찍 교전).
	# 시각 도형(size)보다 넓게 → 사거리 내 진입 시 즉시 타겟 판정.
	# 피격/판정 영역 = 유닛 크기(size_w × size_h). 감지는 별도(_find_target 사거리).
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(data.size_w, data.size_h)
	col.shape = rect
	add_child(col)
	# 레이어/마스크: 아군=2, 적=3 (project.godot 정의)
	collision_layer = 4 if enemy else 2    # bit 2=Player, bit 3=Enemy
	collision_mask = 2 if enemy else 4     # 아군은 적(4) 감지, 적은 아군(2) 감지
	# ★ 시각 방향은 _draw() 의 draw_texture_rect(flip) 로 처리 — scale.x 반전은
	#   체력바 감소 방향까지 뒤집는 부작용이 있어 사용 안 함.
	#   소스 스프라이트는 좌향 기준 → 아군(우향) flip=true, 적(좌향) flip=false.


func _ready() -> void:
	# Unit 은 Area2D 이므로 다른 Area2D(Unit) 감지를 위해 area_* 시그널 사용.
	# body_entered 는 PhysicsBody2D 에만 반응 → Area2D 간 감지 불가(이전 전투 미동작 원인).
	monitorable = true
	monitoring = true
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _physics_process(delta: float) -> void:
	if not _alive or data == null:
		return
	# ★ 타겟을 매 프레임 가까운 적으로 갱신 — area_entered(최초 겹침 1회) 의존 시
	#   여러 적이 겹쳐도 재진입 누락으로 _target 못 잡고 통과하는 버그 방지.
	_target = _find_target()
	# 공격 쿨타임 감소
	if _attack_cd > 0.0:
		_attack_cd -= delta
	# ★ 공격 우선 — 사거리 내 유효 타겟이면 이동 로직 전에 무조건 공격(정지).
	if _target != null and _target._alive:
		var dist := absf(position.x - _target.position.x)
		if dist <= data.attack_range:
			_try_attack()
			position.y = Layout.line_y()
			return
	# 이동 — behavior 별 전진 결정.
	_advance_by_behavior(delta)
	position.y = Layout.line_y()


## 감지 영역 내 가장 가까운 적대 유닛을 찾는다 (매 프레임 갱신).
## area_entered 의존(재진입 누락) 대신 직접 거리 스캔 — 다수 적 통과 버그 방지.
func _find_target() -> Unit:
	var battle := get_parent()
	if battle == null:
		return null
	var detect := maxf(data.attack_range, data.size_w)
	var best: Unit = null
	var best_d := INF
	for child in battle.get_children():
		if not (child is Unit):
			continue
		var other: Unit = child
		if other.is_enemy == is_enemy or not other._alive:
			continue
		var d := absf(position.x - other.position.x)
		if d <= detect and d < best_d:
			best = other
			best_d = d
	return best


## 공격 (쿨타임 시). RANGED=투사체, MELEE/SUPPORT=근접 타격.
func _try_attack() -> void:
	if _attack_cd > 0.0 or _target == null:
		return
	if data.is_ranged_unit():
		_fire_projectile(_target)
	else:
		_target.take_damage(data.attack)
	_attack_cd = data.attack_interval


## behavior 별 전진.
## MELEE=타겟 방향(없으면 진행 방향) 돌격, RANGED/SUPPORT=간격 유지하며 타겟 방향 접근.
## 타겟 방향 이동으로 적과 교차(통과) 방지.
func _advance_by_behavior(delta: float) -> void:
	var behav: int = data.behavior
	if data.is_ranged:
		behav = UnitData.Behavior.RANGED
	# 이동 방향 — 타겟이 있으면 타겟 방향(교차 방지), 없으면 진행 방향.
	var dir := _direction
	if _target != null:
		dir = signf(_target.position.x - position.x)
	# 중력 왜곡석 — 적이 화면 중앙 근처면 이동속도 25% 감소.
	var speed_mult := 1.0
	if is_enemy:
		var am := get_node_or_null("/root/ArtifactManager")
		if am != null and am.has_method("has") and am.has(&"gravity_field"):
			var vp := get_viewport_rect().size
			if absf(global_position.x - vp.x * 0.5) < vp.x * 0.2:
				speed_mult = 0.75
	match behav:
		UnitData.Behavior.MELEE:
			position.x += dir * data.move_speed * delta * 0.5 * speed_mult
		UnitData.Behavior.RANGED, UnitData.Behavior.SUPPORT:
			# 간격 유지 — 전방 같은 진영 교전 유닛이 있으면 정지, 아니면 타겟/진행 방향.
			if not _is_blocked_ahead():
				position.x += dir * data.move_speed * delta * 0.5 * speed_mult


## 데미지 받기. 사망 시 died 시그널 emit + queue_free.
func take_damage(amount: int) -> void:
	if not _alive:
		return
	hp -= amount
	# 피격 점멸 + 데미지 숫자 (사망 여부와 무관하게 항상 표시).
	_flash_hit()
	EventBus.damage_dealt.emit(position, amount, is_enemy)
	# 보스 HP 실시간 — BattleFieldView 보스 게이지 갱신.
	if is_enemy and data.unit_id == &"boss":
		EventBus.boss_hp_changed.emit(hp, data.max_hp)
	if hp <= 0:
		_alive = false
		monitoring = false   # 추가 area_* 콜백 차단 (free 전 경쟁 방지)
		_target = null       # dangling 참조 제거 — 다른 유닛의 타겟 판정이 막히지 않도록
		died.emit(self)
		if is_enemy:
			# Phase 8-A: exp_reward 를 페이로드로 추가 — SoulGauge 가 게이지 충전에 사용.
			EventBus.enemy_killed.emit(data.unit_id, data.exp_reward)
			# Phase 9: credit_reward → CREDIT 즉시 지급 (적 처치 보상).
			if data.credit_reward > 0:
				WalletManager.add_credit(data.credit_reward)
		else:
			EventBus.unit_died.emit(data.unit_id)
		queue_free()


## 피격 점멸 시작 — _hit_flash 를 1.0 으로 리셋하고 tween 으로 0으로 감소.
## 연속/동시 타격 시 매번 1.0 리셋으로 점멸이 꺼지지 않게 유지.
func _flash_hit() -> void:
	if data == null:
		return
	_hit_flash = 1.0
	queue_redraw()
	var tw := create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_method(_set_flash, 1.0, 0.0, 0.15)
	tw.tween_callback(queue_redraw)


## _hit_flash 값 설정 + redraw (tween_method 콜백).
func _set_flash(v: float) -> void:
	_hit_flash = v
	queue_redraw()


## 전방(진행 방향) 짧은 거리 내에 같은 진영 유닛이 "교전 중"인지 — 디펜스 정렬(통과 방지).
## ★ 교전 중(_target 있음)인 전방 유닛이 가까우면 그 뒤에서 멈춰 줄지어 선다.
##   전진 중인 유닛(_target 없음)은 무시 → 이동 흐름 유지(전진 중 겹침은 허용, 교전 시에만 정렬).
##   단순 "전방 유닛 있으면 멈춤"은 기지 근처 뭉침에서 전원 영구 멈춤 버그를 낳음.
func _is_blocked_ahead() -> bool:
	var battle := get_parent()
	if battle == null or data == null:
		return false
	var my_x := position.x
	var block_dist := data.size_w * 1.2
	for child in battle.get_children():
		if child == self or not (child is Unit):
			continue
		var other: Unit = child
		# 같은 진영 + 살아있는 유닛만 (적대 진영은 교전 대상이므로 제외).
		if other.is_enemy != is_enemy or not other._alive:
			continue
		var dx := other.global_position.x - my_x
		# 진행 방향 전방이고 가까우면 — 추가로 상대가 교전 중일 때만 차단.
		if dx * _direction >= 0.0 and absf(dx) < block_dist and other._target != null:
			return true
	return false


## 원거리 투사체 발사 — Projectile 을 BattleField 자식으로 생성해 target 추적.
func _fire_projectile(target: Unit) -> void:
	var battle := get_parent()
	if battle == null:
		return
	var p := Projectile.new()
	# 발사 위치 — 전방 size_w, 라인 높이(y=0). target 도 같은 라인이라 직선 비행.
	p.position = position + Vector2(_direction * data.size_w, 0.0)
	battle.add_child(p)
	p.setup(data.attack, target, data.projectile_speed, data.projectile_color, data.projectile_size, data.projectile_texture)


func _on_area_entered(other: Area2D) -> void:
	# 적대 관계(아군↔적)인 경우에만 타겟 지정. 이미 타겟 있으면 유지.
	if other is Unit and other.is_enemy != is_enemy and _target == null:
		_target = other


func _on_area_exited(other: Area2D) -> void:
	if other == _target:
		_target = null


## 렌더링: texture 우선 (64px 픽셀 아트). 없으면 프로시저럴 도형 폴백.
func _draw() -> void:
	if data == null:
		return
	# 판정박스(충돌 shape) 시각화 — size_w × size_h (유닛 크기와 정확히 일치). 아군=초록/적=빨강.
	if DEBUG_HITBOX:
		var box_col := Color(0.3, 1.0, 0.3, 0.7) if not is_enemy else Color(1.0, 0.3, 0.3, 0.7)
		draw_rect(Rect2(-data.size_w * 0.5, -data.size_h * 0.5, data.size_w, data.size_h), box_col, false, 2.0)
	# 체력바 공통 (머리 위) — 도형 중심 위. 크기 고정(50~100px).
	var hp_ratio := float(hp) / float(data.max_hp) if data.max_hp > 0 else 0.0
	var bar_w := clampf(data.size_w * 1.6, 50.0, 100.0)
	var bar_y := -data.size_h * 1.2 - 12.0
	draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, 5.0), Color(0.2, 0.1, 0.1), true)
	draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * hp_ratio, 5.0), Color(0.2, 0.8, 0.3), true)
	# 본체 — texture 있으면 이미지(size_w/h 스케일), 없으면 도형. 점멸 tint 적용.
	var flash := _hit_flash
	if data.texture != null:
		var tint := Color.WHITE.lerp(Color.RED, flash)
		draw_texture_rect(data.texture, Rect2(-data.size_w * 0.5, -data.size_h * 0.5, data.size_w, data.size_h), false, tint)
		return
	var w := data.size_w
	var h := data.size_h
	var col := data.color.lerp(Color.RED, flash)
	match data.shape:
		UnitData.Shape.CIRCLE:
			draw_circle(Vector2.ZERO, minf(w, h) * 0.5, col)
		UnitData.Shape.SQUARE:
			draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), col)
		UnitData.Shape.TRIANGLE:
			draw_colored_polygon(_triangle_pts(w, h), col)
		UnitData.Shape.DIAMOND:
			draw_colored_polygon(_diamond_pts(w, h), col)


func _triangle_pts(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, -h * 0.5), Vector2(w * 0.5, h * 0.5), Vector2(-w * 0.5, h * 0.5)])


func _diamond_pts(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, -h * 0.5), Vector2(w * 0.5, 0), Vector2(0, h * 0.5), Vector2(-w * 0.5, 0)])
