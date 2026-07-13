class_name WinEffects
extends Node2D
## WinEffects — 당첨 셀에 보석빛 파티클 폭발을 재생하는 이펙트 노드.
## 릴 영역의 자식으로 부착되어 로컬 좌표를 사용.
## EventBus.evaluation_completed 구독 → total_win > 0 시 winning_positions 각 위치에 폭발.
## GPUParticles2D 8개 풀로 재사용(부하 최소화). ParticleBudget(autoload)으로 양 조절.

# --- 튜닝 ---
const POOL_SIZE: int = 8                # 미리 생성할 파티클 노드 수
const CELL_SIZE: int = 180              # 심볼 셀 크기(px)
const COLOR_NORMAL: Color = Color(1.0, 0.85, 0.2)   # 기본 보석빛(골드/노랑)
const COLOR_BIG_WIN: Color = Color(1.0, 0.95, 0.4)  # 빅윈용 더 밝은 골드
const BIG_WIN_MULTIPLIER: float = 50.0  # 빅윈 판정 배수(베팅 기준)

# --- 기본 파티클량(예산 없을 때 폴백) ---
const BASE_AMOUNT_NORMAL: int = 40
const BASE_AMOUNT_BIG_WIN: int = 90
# --- 기본 파티클 크기 ---
const SCALE_NORMAL: float = 1.0
const SCALE_BIG_WIN: float = 1.6

# --- 풀 ---
var _pool: Array[GPUParticles2D] = []
var _pool_index: int = 0

# ParticleBudget autoload 노드 (없으면 null)
var _budget: Node = null


func _ready() -> void:
	# ParticleBudget 안전 접근 — autoload에 등록되어 있지 않을 수도 있음
	_budget = get_node_or_null("/root/ParticleBudget")

	# 파티클 풀 미리 생성
	_build_pool()

	# EventBus 시그널 구독
	EventBus.evaluation_completed.connect(_on_evaluation_completed)
	EventBus.spin_started.connect(_on_spin_started)


## 파티클 풀 빌드 — 미리 POOL_SIZE개 생성해 숨겨둠.
func _build_pool() -> void:
	for i in POOL_SIZE:
		var particles: GPUParticles2D = _create_particle_node(i)
		add_child(particles)
		_pool.append(particles)


## 단일 GPUParticles2D 노드 생성 (one_shot + explosiveness=1.0 = 단발 폭발).
func _create_particle_node(idx: int) -> GPUParticles2D:
	var p: GPUParticles2D = GPUParticles2D.new()
	p.name = "ParticleBurst_%d" % idx
	p.emitting = false            # 수동 emit
	p.one_shot = true             # 한 번만 방출
	p.explosiveness = 1.0         # 단발 폭발(즉시 전량)
	p.local_coords = true
	# 헤드리스 대응 — 물리 기반 처리 보장
	p.set_process_mode(Node.PROCESS_MODE_INHERIT)
	# 골드/노랑 기본 색 (ProcessMaterial에서 덮어씀)
	p.modulate = COLOR_NORMAL

	# ProcessMaterial 생성
	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)       # 360도 전 방향
	mat.spread = 180.0
	mat.gravity = Vector3(0, 120, 0)       # 살짝 아래로 떨어지는 느낌
	mat.initial_velocity_min = 120.0
	mat.initial_velocity_max = 320.0
	mat.scale_min = 0.4
	mat.scale_max = 1.0
	mat.color = COLOR_NORMAL
	# 감속(마찰) — 퍼지고 천천히 멈춤. Godot 4는 damping 사용(linear_drag 아님).
	mat.damping_min = 1.5
	mat.damping_max = 1.5
	p.process_material = mat
	return p


## evaluation_completed 수신 — 당첨 위치마다 폭발.
func _on_evaluation_completed(result: SpinResult) -> void:
	# 당첨이 없으면 무시
	if result == null:
		return
	if result.total_win <= 0:
		return

	var positions: Array[Vector2i] = result.winning_positions
	if positions.is_empty():
		return

	# 빅윈 여부 — bet 정보가 없으므로 total_win 기준(750 = bet50의 15배)
	var is_big: bool = result.total_win >= 750

	# 각 당첨 위치에 폭발
	for pos in positions:
		_spawn_burst(pos, is_big)


## 단일 위치에 파티클 폭발 생성.
func _spawn_burst(pos: Vector2i, is_big: bool) -> void:
	# 좌표 변환: (reel, row) → 셀 중심 로컬 좌표
	var center: Vector2 = _cell_center(pos)

	# 풀에서 다음 노드 획득 (라운드 로빈)
	var particles: GPUParticles2D = _pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE

	# 위치·색·크기 적용
	particles.position = center
	particles.modulate = COLOR_BIG_WIN if is_big else COLOR_NORMAL
	var scale_factor: float = SCALE_BIG_WIN if is_big else SCALE_NORMAL
	particles.scale = Vector2(scale_factor, scale_factor)
	# ProcessMaterial 색도 동기화
	var mat: ParticleProcessMaterial = particles.process_material
	if mat != null:
		mat.color = COLOR_BIG_WIN if is_big else COLOR_NORMAL

	# 예산에서 허용량 받아오기 — 초과 시 비례 축소
	var base_amount: int = BASE_AMOUNT_BIG_WIN if is_big else BASE_AMOUNT_NORMAL
	var amount: int = base_amount
	if _budget != null:
		# 예산 노드가 있으면 request로 실제 허용량 획득
		var granted: int = _budget.request(base_amount)
		amount = max(8, granted)  # 최소 의미있는 양 보장

	particles.amount = amount

	# 방출 시작 (emitting을 끄고 켜서 재트리거 보장)
	particles.emitting = false
	particles.emitting = true

	# 방출 종료 후 예산 반환 + 정리 — 타이머로 예약
	var lifetime_s: float = 1.2
	_schedule_release(particles, amount, lifetime_s)


## 셀 좌표 (reel, row) → 로컬 픽셀 중심. 셀 크기는 Layout.reel_w()/reel_h() (비정사형 동기화).
func _cell_center(pos: Vector2i) -> Vector2:
	var reel: int = pos.x
	var row: int = pos.y
	var csw := Layout.reel_w()
	var csh := Layout.reel_h()
	return Vector2(reel * csw + csw / 2, row * csh + csh / 2)


## 일정 시간 후 예산 release + emitting 정지 예약.
func _schedule_release(particles: GPUParticles2D, amount: int, delay: float) -> void:
	# SceneTreeTimer 사용 — 노드 트리에 타이머 노드 추가 부담 없음
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var timer: SceneTreeTimer = tree.create_timer(delay)
	timer.timeout.connect(
		func() -> void:
			if is_instance_valid(particles):
				particles.emitting = false
			if _budget != null:
				_budget.release(amount)
	)


## spin_started 수신 — 잔여 파티클 정리(새 스핀 시작 시 깔끔하게).
func _on_spin_started(_bet: int) -> void:
	for particles in _pool:
		if is_instance_valid(particles):
			particles.emitting = false
