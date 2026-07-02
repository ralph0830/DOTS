class_name CameraShake
extends Camera2D
## CameraShake — 당첨 규모에 비례해 카메라를 흔드는 이펙트 카메라.
## EventBus 시그널을 구독하여 코어와 느슨하게 결합. 씬 트리의 Camera2D 노드에 직접 부착한다.
## 모바일 멀미 방지: 진폭 상한(20px)과 짧은 지속(0.2~0.4초) 캡 적용.

# --- 튜닝 상수 ---
## 당첨액 → 진폭 변환 계수 (베팅 50 기준으로 50당 1px)
const WIN_TO_AMPLITUDE: float = 1.0 / 50.0
## 진폭 상한(px) — 모바일 멀미/어색함 방지
const MAX_AMPLITUDE: float = 20.0
## 빅윈일 때 진폭 배수
const BIG_WIN_AMPLITUDE_MULTIPLIER: float = 1.5
## 흔들릴 때마다 더하는 랜덤 오프셋의 간격(초)
const SHAKE_STEP: float = 0.03
## 기본 흔들림 총 지속 시간(초)
const SHAKE_DURATION: float = 0.3
## 흔들림 복귀 Tween 시간(초)
const RETURN_DURATION: float = 0.1

# --- 내부 상태 ---
## 현재 실행 중인 흔들림 Tween (중복 실행 방지/재설정용)
var _shake_tween: Tween = null


func _ready() -> void:
	# 코어 직접 참조 없이 EventBus 시그널만 구독
	EventBus.evaluation_completed.connect(_on_evaluation_completed)
	EventBus.big_win.connect(_on_big_win)


func _exit_tree() -> void:
	# 시그널 누수 방지 — 노드 제거 시 구독 해제
	if EventBus:
		EventBus.evaluation_completed.disconnect(_on_evaluation_completed)
		EventBus.big_win.disconnect(_on_big_win)
	_stop_shake()


# --- EventBus 수신 핸들러 ---

## 일반 평가 완료 — 당첨액에 비례해 진동.
func _on_evaluation_completed(result: SpinResult) -> void:
	if result == null:
		return
	# 당첨이 없으면 흔들지 않음
	if result.total_win <= 0:
		return
	var amplitude: float = _compute_amplitude(result.total_win)
	_shake(amplitude, SHAKE_DURATION)


## 빅윈 — 진폭을 더 강하게(×1.5) 적용.
func _on_big_win(amount: int) -> void:
	if amount <= 0:
		return
	var amplitude: float = _compute_amplitude(amount) * BIG_WIN_AMPLITUDE_MULTIPLIER
	_shake(amplitude, SHAKE_DURATION)


# --- 진동 구현 ---

## 당첨액을 진폭으로 변환(클램프 포함).
func _compute_amplitude(total_win: int) -> float:
	return clampf(float(total_win) * WIN_TO_AMPLITUDE, 0.0, MAX_AMPLITUDE)


## 지정 진폭으로 offset을 무작위 흔들고 원점으로 감쇠 복귀.
func _shake(amplitude: float, duration: float) -> void:
	if not is_inside_tree():
		return
	# 진폭이 0이면 흔들지 않고 종료
	if amplitude <= 0.0:
		return
	# 진행 중인 흔들림이 있으면 정리 후 재시작
	_stop_shake()

	_shake_tween = create_tween()
	# 헤드리스/물리 일관성 — Tween을 물리 프레임 기반으로 처리
	_shake_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)

	var step_count: int = max(1, int(round(duration / SHAKE_STEP)))
	# 각 스텝마다 offset을 랜덤하게 배치하되, 마지막엔 (0,0)으로 ease-out 감쇠
	for i in range(step_count):
		# 진행도에 따라 진폭 선형 감소(감쇠)
		var progress: float = float(i) / float(step_count)
		var decay: float = 1.0 - progress
		var cur_amp: float = amplitude * decay
		var target_offset: Vector2 = _random_offset(cur_amp)
		_shake_tween.tween_property(self, "offset", target_offset, SHAKE_STEP)

	# 마지막: 원점으로 부드럽게 복귀(ease-out)
	_shake_tween.tween_property(self, "offset", Vector2.ZERO, RETURN_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_shake_tween.tween_callback(_on_shake_finished)


## 진폭 범위 내에서 무작위 오프셋 반환.
func _random_offset(amplitude: float) -> Vector2:
	if amplitude <= 0.0:
		return Vector2.ZERO
	var x: float = randf_range(-amplitude, amplitude)
	var y: float = randf_range(-amplitude, amplitude)
	return Vector2(x, y)


## 진행 중인 흔들림 정지 + offset 원점 복원.
func _stop_shake() -> void:
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = null
	offset = Vector2.ZERO


## 흔들림 Tween 완료 콜백 — 참조 정리.
func _on_shake_finished() -> void:
	_shake_tween = null
