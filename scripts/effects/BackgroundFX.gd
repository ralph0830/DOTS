# 풀스크린 배경 이펙트 — ColorRect + ShaderMaterial
# 어두운 보라/보석빛 절차적 그라데이션 배경, 스핀 시작 시 반응.
# 배경 아트(TextureRect) 오버레이 지원 — 파일 있으면 셰이더 위에 표시, 없으면 그라데이션만.
class_name BackgroundFX
extends ColorRect

# 배경 셰이더 경로
const SHADER_PATH: String = "res://assets/shaders/background.gdshader"
# 배경 아트 경로 — 파일이 있으면 로드. null이면 그라데이션만 표시.
const BG_ART_PATH: String = "res://assets/backgrounds/bg_mystic_1080x1920.png"

# 기본 유니폼 값 — 어두운 보라 / 짙은 청
const DEFAULT_COLOR_A: Color = Color(0.18, 0.08, 0.32, 1.0)
const DEFAULT_COLOR_B: Color = Color(0.05, 0.07, 0.22, 1.0)
const DEFAULT_SPEED: float = 0.3
const BOOST_SPEED: float = 1.2   # 스핀 시작 시 일시적 가속
const BOOST_DURATION: float = 0.5 # 트윈 지속 시간(초)

var _shader_mat: ShaderMaterial
var _bg_art: TextureRect


func _ready() -> void:
	# 화면 전체 채우기
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 배경 아트 로드 (있으면 셰이더 위에 오버레이)
	_load_bg_art()

	# 셰이더 로드 — 로드 실패 시 에러 로그 후 안전하게 종료
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		push_error("[BackgroundFX] 배경 셰이더 로드 실패: %s" % SHADER_PATH)
		return

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	material = _shader_mat

	# 기본 유니폼 값 설정
	_apply_default_uniforms()

	# EventBus 시그널 구독 — 스핀 시작 시 배경 반응 (느슨한 결합)
	if EventBus.spin_started.is_connected(_on_spin_started) == false:
		EventBus.spin_started.connect(_on_spin_started)


# 배경 아트 TextureRect 로드 — 파일이 있으면 셰이더와 동일한 full rect 로 배치.
func _load_bg_art() -> void:
	if not ResourceLoader.exists(BG_ART_PATH):
		return
	var tex: Texture2D = load(BG_ART_PATH)
	if tex == null:
		return
	_bg_art = TextureRect.new()
	_bg_art.texture = tex
	_bg_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# 셰이더(자기자신)보다 위에 오도록 나중에 추가 — 부모가 add_child(bg) 후 bg.add_child(_bg_art).
	# 하지만 BackgroundFX 자체가 ColorRect 이므로 자식으로 못 넣음 → sibling 으로 배치는 부모 책임.
	# 여기서는 자식 노드로 추가하지 않고 인스턴스만 보관. SlotMachineView 가 add_child.


# 기본 유니폼 값을 셰이더에 적용
func _apply_default_uniforms() -> void:
	if _shader_mat == null:
		return
	_shader_mat.set_shader_parameter("color_a", DEFAULT_COLOR_A)
	_shader_mat.set_shader_parameter("color_b", DEFAULT_COLOR_B)
	_shader_mat.set_shader_parameter("speed", DEFAULT_SPEED)


# 스핀 시작 시 배경 가속 반응 — Tween으로 speed를 잠깐 올렸다 복귀
func _on_spin_started(_bet: int) -> void:
	if _shader_mat == null:
		return

	# speed를 BOOST_SPEED에서 DEFAULT_SPEED로 복귀시키는 트윈
	var tween: Tween = create_tween()
	tween.set_parallel(false)

	# speed를 BOOST_SPEED로 올렸다가 DEFAULT_SPEED로 복귀
	tween.tween_method(_set_speed, BOOST_SPEED, DEFAULT_SPEED, BOOST_DURATION)


# speed 유니폼을 설정하는 콜백 (tween_method용)
func _set_speed(value: float) -> void:
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("speed", value)


# 배경 아트 노드 반환 (SlotMachineView 가 셰이더 위에 추가하는 용도).
func get_bg_art() -> TextureRect:
	return _bg_art

