class_name FloatingText
extends Node2D
## 당첨 금액 플로팅 텍스트 이펙트.
## EventBus.evaluation_completed 를 구독해 total_win > 0 일 때 릴 영역 중앙 상단에
## 금액 롤업 + 상승 + 페이드 아웃 애니메이션을 표시한다.
## Label 풀(6개)을 미리 생성해 재사용 — 모바일 성능(할당 최소화).
## spin_started 수신 시 활성 텍스트를 즉시 숨기고 풀로 반환.

const POOL_SIZE: int = 6                  # 재사용할 Label 풀 크기
const SPAWN_POS: Vector2 = Vector2(450.0, 200.0)  # 릴 영역 중앙 상단 로컬 좌표
const ROLLUP_TIME: float = 0.8            # 0 → 총 당첨까지 카운트 시간(초)
const TOTAL_LIFETIME: float = 1.2         # 텍스트 총 지속 시간(초)
const RISE_DISTANCE: float = 120.0        # 위로 상승할 거리(px)

const FONT_NORMAL: int = 64               # 일반 당첨 폰트 크기
const FONT_BIG_WIN: int = 96              # 빅윈 폰트 크기
const BIG_WIN_MULTIPLIER: float = 50.0    # 빅윈 판정 배수(베팅 대비)
const BIG_WIN_LIFETIME: float = 1.8       # 빅윈 총 지속 시간(초)
const BIG_WIN_ROLLUP_TIME: float = 1.2    # 빅윈 롤업 시간(초)

var _pool: Array[Label] = []              # 대기 중인 Label 풀
var _active: Array[Label] = []            # 현재 애니메이션 중인 Label
# active → 풀 반환 매핑을 위한 메타데이터(각 Label 의 Tween 완료 콜백에서 사용)


func _ready() -> void:
	_build_pool()
	EventBus.evaluation_completed.connect(_on_evaluation_completed)
	EventBus.spin_started.connect(_on_spin_started)


func _build_pool() -> void:
	# 미리 POOL_SIZE 개의 Label 생성 — 골드/흰색, 외곽선 적용 후 비활성화
	for i in range(POOL_SIZE):
		var label := Label.new()
		label.name = "FloatingText_%d" % i
		label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))  # 골드
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 8)
		label.add_theme_font_size_override("font_size", FONT_NORMAL)
		label.position = SPAWN_POS
		label.visible = false
		label.z_index = 10
		add_child(label)
		_pool.append(label)


# --- EventBus 콜백 ---

func _on_evaluation_completed(result: SpinResult) -> void:
	# 당첨이 없으면 표시하지 않는다
	if result.total_win <= 0:
		return
	var label := _acquire()
	if label == null:
		# 풀이 가득 차면 이번 표시는 스킵 — 폭주 방지
		return
	_show_amount(label, result)


func _on_spin_started(_bet: int) -> void:
	# 새 스핀이 시작되면 활성 텍스트를 즉시 회수
	for label in _active:
		_kill_tween(label)
		_release(label)
	_active.clear()


# --- 풀 관리 ---

func _acquire() -> Label:
	# 대기 풀에서 하나 꺼내기. 없으면 null.
	if _pool.is_empty():
		return null
	var label: Label = _pool.pop_back()
	_active.append(label)
	return label


func _release(label: Label) -> void:
	# 활성 목록에서 제거 후 풀로 반환. 중복 반환 방지.
	label.visible = false
	label.text = ""
	label.modulate.a = 1.0
	label.position = SPAWN_POS
	var idx := _active.find(label)
	if idx >= 0:
		_active.remove_at(idx)
	if not _pool.has(label):
		_pool.append(label)


# --- 표시/애니메이션 ---

func _show_amount(label: Label, result: SpinResult) -> void:
	# 빅윈 여부 판정 — bet 은 평가 신호에 없으므로 현재 베팅 사용
	var bet: int = WalletManager.current_bet
	var is_big: bool = result.is_big_win(bet, BIG_WIN_MULTIPLIER)

	# 폰트/지속 시간 설정
	var font_size: int = FONT_BIG_WIN if is_big else FONT_NORMAL
	var lifetime: float = BIG_WIN_LIFETIME if is_big else TOTAL_LIFETIME
	var rollup_time: float = BIG_WIN_ROLLUP_TIME if is_big else ROLLUP_TIME

	label.add_theme_font_size_override("font_size", font_size)
	# 빅윈은 흰색, 일반은 골드
	var col: Color = Color.WHITE if is_big else Color(1.0, 0.9, 0.3)
	label.add_theme_color_override("font_color", col)
	label.position = SPAWN_POS
	label.modulate.a = 1.0
	label.visible = true
	label.text = "0"  # 롤업 시작 전 초기값

	# 금액 롤업 — tween_method 로 0 → total_win 카운트
	var tw := create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)  # 헤드리스 대응
	# 콜백에 총액을 캡처해 표시 갱신
	var total := result.total_win
	tw.tween_method(_set_amount.bind(label, total), 0.0, 1.0, rollup_time)
	# 동시에 상승 + 페이드 아웃 (롤업과 병렬)
	tw.parallel().tween_property(label, "position:y", SPAWN_POS.y - RISE_DISTANCE, lifetime)
	tw.parallel().tween_property(label, "modulate:a", 0.0, lifetime)
	# 완료 후 풀로 반환
	tw.tween_callback(_on_tween_finished.bind(label))

	# 트위 인스턴스를 label 메타에 저장 → 강제 kill 시 안전하게 free
	label.set_meta("tween", tw)


func _set_amount(progress: float, label: Label, total: int) -> void:
	# progress 0→1 에 비례해 금액 표시 (반올림, 최소 0)
	var amount: int = int(round(progress * float(total)))
	amount = clampi(amount, 0, total)
	label.text = "%d" % amount


func _on_tween_finished(label: Label) -> void:
	_release(label)


func _kill_tween(label: Label) -> void:
	# 활성 트윈이 있으면 정지 후 메타 정리
	if label.has_meta("tween"):
		var tw: Tween = label.get_meta("tween")
		tw.kill()
		label.remove_meta("tween")
