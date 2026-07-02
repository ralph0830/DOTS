class_name JackpotFX
extends CanvasLayer
## JackpotFX — 잭팟 당첨 시 전체화면 연출 오버레이.
## EventBus.jackpot_won(tier, amount) 를 구독해 어두운 반투명 오버레이 + 대형 텍스트 +
## 다량의 파티클 폭죽을 재생한다. tier 별로 색상/크기/파티클량이 차등 적용된다.
## CanvasLayer(layer=50)로 어떤 UI 위에도 표시. 코드로 자식 노드를 생성해 씬 의존 최소화.
## 헤드리스 대응: 모든 Tween 은 TWEEN_PROCESS_PHYSICS. ParticleBudget 으로 파티클 수 캡.

# --- 티어 시각화 설정 ---
# 4티어 컬러 팔레트 — Mini(청)→Minor(녹)→Major(보라)→Grand(골드)
const TIER_COLORS: PackedColorArray = [
	Color(0.35, 0.75, 1.0),   # MINI  — 밝은 청
	Color(0.45, 1.0, 0.55),   # MINOR — 에메랄드
	Color(0.75, 0.40, 1.0),   # MAJOR — 보라
	Color(1.0, 0.85, 0.20),   # GRAND — 골드
]
# 티어명 표시용(autoload JackpotSystem.TIER_NAMES 와 동일 순서)
const TIER_NAMES: PackedStringArray = ["Mini", "Minor", "Major", "Grand"]

# --- 레이아웃(세로 1080×1920) ---
const VIEW_W: int = 1080
const VIEW_H: int = 1920
const CENTER: Vector2 = Vector2(VIEW_W * 0.5, VIEW_H * 0.5)

# --- 타이밍(초) ---
const TIME_ENTER: float = 0.45    # 등장(스케일업 + 페이드인)
const TIME_HOLD: float = 3.0      # 유지
const TIME_EXIT: float = 0.55     # 퇴장(페이드아웃)

# --- 폰트 크기(티어별 차등) ---
const FONT_TITLE: int = 140                   # "JACKPOT!" 메인 타이틀
const TIER_FONT_SIZE: PackedInt32Array = [72, 96, 120, 160]   # 티어명/금액
const AMOUNT_FONT_BONUS: int = 20             # 금액 라벨은 티어명보다 약간 작게

# --- 오버레이 색상 ---
const OVERLAY_COLOR: Color = Color(0.0, 0.0, 0.0, 0.72)  # 어두운 반투명

# --- 파티클 설정 ---
const PARTICLE_NODE_COUNT: int = 3            # 화면 전체 폭죽 노드 수
# 티어별 요청 파티클량(예산 없을 때 기본값) — Mini 작게, Grand 최대
const TIER_BASE_AMOUNT: PackedInt32Array = [40, 70, 110, 160]
# 티어별 파티클 확산 속도(폭죽 세기)
const TIER_BURST_VELOCITY: PackedFloat32Array = [260.0, 340.0, 430.0, 540.0]
const PARTICLE_LIFETIME: float = 1.6          # 방출 완료 후 예산 반환까지 대기

# --- 노드 참조 ---
var _overlay: ColorRect = null                # 어두운 배경
var _root: Control = null                     # 텍스트/라벨 컨테이너(전체 알파 트윈용)
var _title_label: Label = null                # "JACKPOT!"
var _tier_label: Label = null                 # 티어명 ("Grand" 등)
var _amount_label: Label = null               # 당첨 금액
var _particles: Array[GPUParticles2D] = []    # 폭죽 파티클 노드들

# --- 상태 ---
var _budget: Node = null                      # ParticleBudget autoload (없으면 null)
var _tween: Tween = null                      # 현재 재생 중인 연출 트윈
var _last_amount: int = 0                     # 마지막으로 요청한 파티클 예산(반환용)


func _ready() -> void:
	# 최상위 — 어느 씬에서도 가장 위에
	layer = 50
	# ParticleBudget 안전 접근 (autoload 미등록 대비)
	_budget = get_node_or_null("/root/ParticleBudget")
	# 자식 노드 구성 후 숨김
	_build()
	_set_visible(false)
	# EventBus 시그널 구독 — 잭팟 당첨 시 연출 재생 (느슨한 결합)
	EventBus.jackpot_won.connect(_play)


## 코드로 모든 자식 노드 생성 — 씬 파일 의존 최소화.
func _build() -> void:
	# 1) 어두운 반투명 오버레이 — 전체화면
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.color = OVERLAY_COLOR
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 오버레이가 입력을 삼키지 않도록(뒤 UI 터치 가능), 단 표시 중에는 차단하고 싶으므로
	# STOP 으로 설정해 터치가 뒤로 가지 않게 한다(잭팟 연출 중 상호작용 방지).
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# 2) 텍스트 컨테이너 (Control, 중앙 정렬 — 전체 modulate.a 트윈으로 등장/퇴장)
	_root = Control.new()
	_root.name = "TextRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate.a = 0.0
	add_child(_root)

	# 3) 라벨들 — 수직 중앙 정렬
	_title_label = _make_label("TitleLabel", "JACKPOT!", FONT_TITLE, Color.WHITE)
	_title_label.position = Vector2(0.0, CENTER.y - 360.0)
	_root.add_child(_title_label)

	_tier_label = _make_label("TierLabel", "", TIER_FONT_SIZE[0], Color.WHITE)
	_tier_label.position = Vector2(0.0, CENTER.y - 150.0)
	_root.add_child(_tier_label)

	_amount_label = _make_label("AmountLabel", "", TIER_FONT_SIZE[0] - AMOUNT_FONT_BONUS, Color.WHITE)
	_amount_label.position = Vector2(0.0, CENTER.y + 40.0)
	_root.add_child(_amount_label)

	# 4) 파티클 폭죽 노드 N개 — 서로 다른 시작점에서 전체화면 방출
	for i in range(PARTICLE_NODE_COUNT):
		var p: GPUParticles2D = _create_particle_node(i)
		_root.add_child(p)
		_particles.append(p)


## 중앙 정렬 라벨 생성 헬퍼.
func _make_label(node_name: String, text: String, font_size: int, font_color: Color) -> Label:
	var lbl: Label = Label.new()
	lbl.name = node_name
	lbl.text = text
	lbl.add_theme_color_override("font_color", font_color)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 10)
	lbl.add_theme_font_size_override("font_size", font_size)
	# 정렬 — Godot 4 전역 enum(HorizontalAlignmentMode / VerticalAlignmentMode) 사용
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 전체폭으로 중앙 정렬 보장
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	return lbl


## 단일 GPUParticles2D 폭죽 노드 생성. one_shot + explosiveness=1.0 으로 단발 전량 방출.
func _create_particle_node(idx: int) -> GPUParticles2D:
	var p: GPUParticles2D = GPUParticles2D.new()
	p.name = "Firework_%d" % idx
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false  # 화면 좌표 기준 전체 방출
	# 헤드리스/물리 대응
	p.set_process_mode(Node.PROCESS_MODE_INHERIT)
	# 화면을 골고루 채우도록 시작점 분산
	var x_frac: float = (float(idx) + 0.5) / float(PARTICLE_NODE_COUNT)
	p.position = Vector2(VIEW_W * x_frac, VIEW_H * 0.5)
	p.scale = Vector2(1.4, 1.4)

	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.gravity = Vector3(0, 140, 0)   # 살짝 아래로(중력감)
	mat.initial_velocity_min = 160.0
	mat.initial_velocity_max = 320.0
	mat.scale_min = 0.5
	mat.scale_max = 1.1
	mat.color = Color.WHITE
	mat.damping_min = 1.2
	mat.damping_max = 1.2
	p.process_material = mat
	return p


## 가시성 토글 — 오버레이/루트 함께.
func _set_visible(vis: bool) -> void:
	_overlay.visible = vis
	_root.visible = vis


## EventBus.jackpot_won 수신 — 연출 재생.
func _play(tier: int, amount: int) -> void:
	# tier 범위 가드
	if tier < 0 or tier >= TIER_NAMES.size():
		push_warning("[JackpotFX] 잘못된 tier 수신: %d" % tier)
		return

	# 기존 연출이 있으면 kill 후 재시작(중복 트리거 대응)
	_kill_tween()
	# 이전 예산이 남아있으면 먼저 반환
	_release_pending_budget()

	# 티어별 색상/폰트 적용
	var tier_color: Color = TIER_COLORS[tier]
	var tier_font: int = TIER_FONT_SIZE[tier]

	# 텍스트/색상 갱신
	_tier_label.text = TIER_NAMES[tier].to_upper()
	_tier_label.add_theme_color_override("font_color", tier_color)
	_tier_label.add_theme_font_size_override("font_size", tier_font)

	_amount_label.text = "%s" % _format_amount(amount)
	_amount_label.add_theme_color_override("font_color", Color.WHITE)
	_amount_label.add_theme_font_size_override("font_size", max(40, tier_font - AMOUNT_FONT_BONUS))

	# 파티클 색상/속도/량 적용
	_apply_particles(tier)

	# 등장 시작 스케일/알파 초기화
	_root.modulate.a = 0.0
	_root.scale = Vector2(0.6, 0.6)
	_root.pivot_offset = CENTER
	_set_visible(true)

	# 트윈 시퀀스: 등장(스케일업+페이드인) → 유지 → 퇴장(페이드아웃)
	var tw: Tween = create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)  # 헤드리스 대응
	# 등장: 알파 0→1, 스케일 0.6→1.0 (병렬)
	tw.parallel().tween_property(_root, "modulate:a", 1.0, TIME_ENTER)
	tw.parallel().tween_property(_root, "scale", Vector2.ONE, TIME_ENTER).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 유지
	tw.tween_interval(TIME_HOLD)
	# 퇴장: 알파 1→0
	tw.tween_property(_root, "modulate:a", 0.0, TIME_EXIT)
	# 종료 처리
	tw.tween_callback(_on_finished)

	_tween = tw

	# 파티클 방출 시작 (emitting 토글로 재트리거 보장)
	for p in _particles:
		if is_instance_valid(p):
			p.emitting = false
			p.emitting = true

	# 파티클 수명 후 예산 반환 예약
	_schedule_release(PARTICLE_LIFETIME)


## 티어 설정을 파티클 노드들에 반영 + 예산 request.
func _apply_particles(tier: int) -> void:
	var base_amount: int = TIER_BASE_AMOUNT[tier]
	var velocity: float = TIER_BURST_VELOCITY[tier]
	var color: Color = TIER_COLORS[tier]

	# 예산에서 허용량 획득 — 노드별로 분배
	var per_node_target: int = int(ceil(float(base_amount) / float(PARTICLE_NODE_COUNT)))
	var granted_total: int = 0

	for p in _particles:
		if not is_instance_valid(p):
			continue
		var granted: int = per_node_target
		if _budget != null:
			granted = _budget.request(per_node_target)
		# 최소 의미있는 양 보장 (완전 0이면 폭죽이 안 나옴)
		granted = max(8, granted)
		p.amount = granted
		granted_total += granted

		var mat: ParticleProcessMaterial = p.process_material
		if mat != null:
			mat.color = color
			mat.initial_velocity_min = velocity * 0.5
			mat.initial_velocity_max = velocity

	_last_amount = granted_total


## 금액을 천 단위 구분자로 포맷팅.
func _format_amount(amount: int) -> String:
	# 음수 방지
	var v: int = max(0, amount)
	var s: String = "%d" % v
	var out: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "," + out
		out = s[i] + out
		count += 1
	return out


## 연출 종료 — 숨기고 예산 정리.
func _on_finished() -> void:
	_set_visible(false)
	_tween = null
	# 파티클 방출 중지
	for p in _particles:
		if is_instance_valid(p):
			p.emitting = false


## 현재 트윈 kill.
func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


## 파티클 수명 후 예산 반환 예약 — SceneTreeTimer 사용(노드 추가 부담 없음).
func _schedule_release(delay: float) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var timer: SceneTreeTimer = tree.create_timer(delay)
	var amount_snap: int = _last_amount
	timer.timeout.connect(
		func() -> void:
			if _budget != null and amount_snap > 0:
				_budget.release(amount_snap)
			_last_amount = 0
	)


## 재시작 시 남아있는 예산을 즉시 반환.
func _release_pending_budget() -> void:
	if _budget != null and _last_amount > 0:
		_budget.release(_last_amount)
	_last_amount = 0


func _exit_tree() -> void:
	# 노드 제거 시 예산 누수 방지
	_release_pending_budget()
