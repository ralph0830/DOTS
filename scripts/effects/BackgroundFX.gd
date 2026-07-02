# 풀스크린 배경 이펙트 — ColorRect + ShaderMaterial
# 어두운 보라/보석빛 절차적 그라데이션 배경, 스핀 시작 시 반응
class_name BackgroundFX
extends ColorRect

# 배경 셰이더 경로
const SHADER_PATH: String = "res://assets/shaders/background.gdshader"

# 기본 유니폼 값 — 어두운 보라 / 짙은 청
const DEFAULT_COLOR_A: Color = Color(0.18, 0.08, 0.32, 1.0)
const DEFAULT_COLOR_B: Color = Color(0.05, 0.07, 0.22, 1.0)
const DEFAULT_SPEED: float = 0.3
const BOOST_SPEED: float = 1.2   # 스핀 시작 시 일시적 가속
const BOOST_DURATION: float = 0.5 # 트윈 지속 시간(초)

var _shader_mat: ShaderMaterial


func _ready() -> void:
	# 화면 전체 채우기
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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
