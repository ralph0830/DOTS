extends Node
## SlowMotion — 빅윈/잭팟 순간에 Engine.time_scale을 낮춰 슬로우모션 연출.
## EventBus 시그널을 구독하여 코어와 느슨하게 결합. autoload 또는 씬 노드로 배치.
## 모바일 고려: time_scale = 0.3, 총 슬로우모션 구간 0.5초 이내로 짧게 유지(어색함/멀미 방지).
## 중복 트리거 방지: 이미 진행 중이면 타이머/복귀를 재설정.

# --- 튜닝 상수 ---
## 슬로우모션 적용 시 time_scale (0.3 = 30% 속도)
const SLOW_TIME_SCALE: float = 0.3
## 정상 속도
const NORMAL_TIME_SCALE: float = 1.0
## 슬로우모션 지속(초, 실제 시간) 후 복귀 시작
const SLOW_HOLD_SECONDS: float = 0.3
## time_scale 복귀 Tween 시간(초, 실제 시간)
const RECOVER_SECONDS: float = 0.2

# --- 내부 상태 ---
## 복귀용 Tween (중복 트리거 방지/재설정용)
var _recover_tween: Tween = null
## 슬로우모션 홀드 타이머
var _hold_timer: SceneTreeTimer = null


func _ready() -> void:
	# 코어 직접 참조 없이 EventBus 시그널만 구독
	EventBus.big_win.connect(_on_big_win)
	EventBus.jackpot_won.connect(_on_jackpot_won)


func _exit_tree() -> void:
	# 시그널 누수 방지 + time_scale 반드시 정상 복원
	if EventBus:
		EventBus.big_win.disconnect(_on_big_win)
		EventBus.jackpot_won.disconnect(_on_jackpot_won)
	_reset_to_normal()


# --- EventBus 수신 핸들러 ---

## 빅윈 — 슬로우모션 트리거.
func _on_big_win(_amount: int) -> void:
	trigger()


## 잭팟 당첨 — 슬로우모션 트리거.
func _on_jackpot_won(_tier: int, _amount: int) -> void:
	trigger()


# --- 슬로우모션 제어 ---

## 슬로우모션 시작. 이미 진행 중이면 타이머를 재설정(중복 트리거 방지).
func trigger() -> void:
	if not is_inside_tree():
		return
	# 진행 중인 복귀 Tween/홀드 타이머 정리
	_cancel_pending()

	# time_scale 즉시 낮춤
	Engine.time_scale = SLOW_TIME_SCALE

	# 실제 시간 기준으로 홀드 후 복귀 예약
	# (time_scale에 영향을 받지 않는 process frame 타이머 사용 — time_timeout 기반)
	_hold_timer = get_tree().create_timer(SLOW_HOLD_SECONDS, true, false, true)
	_hold_timer.timeout.connect(_begin_recovery)


## 홀드 종료 후 time_scale을 부드럽게 1.0로 복귀.
func _begin_recovery() -> void:
	_hold_timer = null
	if not is_inside_tree():
		_reset_to_normal()
		return

	_recover_tween = create_tween()
	# 헤드리스/물리 일관성 — Tween을 물리 프레임 기반으로 처리
	_recover_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	# time_scale에 영향받지 않게 실제 시간 기준으로 복귀 (총 0.5초 이내 보장)
	_recover_tween.set_ignore_time_scale(true)
	# 부드러운 복귀(ease-in-out)
	_recover_tween.tween_method(_set_time_scale, Engine.time_scale, NORMAL_TIME_SCALE, RECOVER_SECONDS) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
	_recover_tween.tween_callback(_on_recovery_finished)


## time_scale 설정 래퍼 — Tween 메서드용.
func _set_time_scale(value: float) -> void:
	Engine.time_scale = value


## 복귀 Tween 완료 콜백 — 정상 확정 + 참조 정리.
func _on_recovery_finished() -> void:
	_recover_tween = null
	Engine.time_scale = NORMAL_TIME_SCALE


## 진행 중인 홀드 타이머/복귀 Tween 취소.
func _cancel_pending() -> void:
	if _hold_timer:
		# SceneTreeTimer는 명시적 취소 API가 없으므로, 연결된 콜백만 분리해 발화 무효화
		if _hold_timer.timeout.is_connected(_begin_recovery):
			_hold_timer.timeout.disconnect(_begin_recovery)
		_hold_timer = null
	if _recover_tween and _recover_tween.is_valid():
		_recover_tween.kill()
	_recover_tween = null


## 안전하게 정상 속도로 되돌림 (종료/정리용).
func _reset_to_normal() -> void:
	_cancel_pending()
	Engine.time_scale = NORMAL_TIME_SCALE
