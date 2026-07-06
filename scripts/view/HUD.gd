class_name HUD
extends CanvasLayer
## HUD: 크레딧/베팅/당첨/상태 표시 + 스핀·베팅·자동스핀 버튼.
## SafeArea(노치/홈 인디케이터 대응) + 터치 친화 버튼(≥120px). EventBus 구독으로 갱신(코어 직접 참조 없음).
## Container 기반 레이아웃 — 하단은 2행(베팅·AUTO / SPIN)으로 엄지 영역을 유지하며 여유 있게 배치.

const BTN_MIN := Vector2(120.0, 120.0)   # 모바일 터치 최소 권장(88px)보다 큼
const SPIN_SIZE := Vector2(300.0, 160.0)
const MARGIN := 40.0

var _credit_label: Label
var _bet_label: Label
var _win_label: Label
var _status_label: Label
var _auto_btn: Button
var _safe_root: Control


func _ready() -> void:
	_build_ui()
	EventBus.credit_changed.connect(_on_credit)
	EventBus.bet_changed.connect(_on_bet)
	EventBus.evaluation_completed.connect(_on_eval)
	EventBus.free_spins_changed.connect(_on_free_spins)
	EventBus.free_spins_ended.connect(_on_free_spins_ended)
	EventBus.jackpot_won.connect(_on_jackpot)
	EventBus.auto_spin_changed.connect(_on_auto_changed)
	# 초기 표시
	_on_credit(WalletManager.credit)
	_on_bet(WalletManager.current_bet)


func _build_ui() -> void:
	# SafeArea 루트 — 디바이스 안전 영역만큼 inset(자식은 모두 안전 영역 내 배치).
	_safe_root = Control.new()
	_safe_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_safe_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe_root)
	call_deferred("_apply_safe_area")   # viewport/윈도우 크기 확정 후 적용

	# 외곽 여백 컨테이너
	var margin_c := MarginContainer.new()
	margin_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin_c.add_theme_constant_override("margin_left", int(MARGIN))
	margin_c.add_theme_constant_override("margin_right", int(MARGIN))
	margin_c.add_theme_constant_override("margin_top", 24)
	margin_c.add_theme_constant_override("margin_bottom", 24)
	margin_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe_root.add_child(margin_c)

	# 수직 레이아웃: 상단 정보 / 중앙 빈 공간(릴 영역) / 하단 컨트롤(2행)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin_c.add_child(vbox)

	vbox.add_child(_build_top_bar())
	_status_label = _make_label("", 40, Color(0.6, 0.85, 1.0))
	vbox.add_child(_status_label)

	# 중앙 spacer (릴 영역 확보)
	var mid := Control.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(mid)

	# 하단 행1: 베팅 ± (좌) / AUTO (우)
	vbox.add_child(_build_bet_bar())
	# 하단 행2: SPIN (우측 큼)
	vbox.add_child(_build_spin_bar())


## 상단 바: 크레딧(좌) / 당첨(우).
func _build_top_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 24)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_credit_label = _make_label("CREDIT  0", 46, Color(1.0, 0.9, 0.3))
	bar.add_child(_credit_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	_win_label = _make_label("", 54, Color(0.5, 1.0, 0.6))
	bar.add_child(_win_label)
	return bar


## 하단 행1: 베팅 감소 / BET 표시 / 베팅 증가 (좌) … (spacer) … AUTO (우).
func _build_bet_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 18)

	var bet_down := _make_button("-", BTN_MIN)
	bet_down.add_theme_font_size_override("font_size", 56)
	bet_down.pressed.connect(func() -> void: WalletManager.change_bet(-1))
	bar.add_child(bet_down)

	# BET 표시 박스(BET 캡션 + 금액)
	var bet_box := VBoxContainer.new()
	bet_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bet_box.custom_minimum_size = Vector2(150.0, 0.0)
	bet_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := _make_label("BET", 28, Color(0.85, 0.85, 0.85))
	bet_box.add_child(cap)
	_bet_label = _make_label("0", 44, Color.WHITE)
	bet_box.add_child(_bet_label)
	bar.add_child(bet_box)

	var bet_up := _make_button("+", BTN_MIN)
	bet_up.add_theme_font_size_override("font_size", 56)
	bet_up.pressed.connect(func() -> void: WalletManager.change_bet(1))
	bar.add_child(bet_up)

	# 우측으로 밀어 AUTO를 끝으로 정렬
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	# 자동스핀 토글
	_auto_btn = _make_button("AUTO", BTN_MIN)
	_auto_btn.toggle_mode = true
	_auto_btn.add_theme_font_size_override("font_size", 36)
	_auto_btn.toggled.connect(func(on: bool) -> void: EventBus.auto_spin_changed.emit(on))
	bar.add_child(_auto_btn)
	return bar


## 하단 행2: (spacer) … SPIN (우측, 큼).
func _build_spin_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 18)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	var spin := _make_button("SPIN", SPIN_SIZE)
	spin.add_theme_font_size_override("font_size", 54)
	spin.pressed.connect(func() -> void: EventBus.spin_requested.emit())
	bar.add_child(spin)
	return bar


## 디스플레이 안전 영역(노치/홈 인디케이터 제외)을 design 해상도 좌표로 변환해 루트 offset 적용.
## 데스크톱(노치 없음)에서는 offset 0 — 모바일에서만 창 내부 기준으로 안전하게 계산.
## (이전 구현이 모니터 전체 safe area 를 창 크기로 환산해 작은 창에서 offset 이 폭주하여
##  HUD 전체가 화면 밖으로 밀려 보이지 않던 버그 수정 — 2026-07-03.)
func _apply_safe_area() -> void:
	_safe_root.offset_left = 0.0
	_safe_root.offset_top = 0.0
	_safe_root.offset_right = 0.0
	_safe_root.offset_bottom = 0.0
	# 데스크톱 플랫폼은 노치/홈 인디케이터가 없으므로 SafeArea 무시.
	var platform := OS.get_name()
	if platform != "Android" and platform != "iOS":
		return
	var safe := DisplayServer.get_display_safe_area()   # 윈도우 픽셀 좌표
	var win := get_window().get_size()
	if win.x <= 0 or win.y <= 0:
		return
	# safe area 가 창 영역 밖이면(의미 없는 값) 무시.
	if safe.end.x <= safe.position.x or safe.end.y <= safe.position.y:
		return
	if safe.end.x > win.x or safe.end.y > win.y:
		return
	# design 해상도(1080×1920) 기준 비율로 환산. stretch 모드에서도 일관 동작.
	var design := get_window().content_scale_size
	var sx := float(design.x) / float(win.x)
	var sy := float(design.y) / float(win.y)
	_safe_root.offset_left = float(safe.position.x) * sx
	_safe_root.offset_top = float(safe.position.y) * sy
	_safe_root.offset_right = -float(win.x - safe.end.x) * sx
	_safe_root.offset_bottom = -float(win.y - safe.end.y) * sy


func _make_label(text: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_button(text: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.size = min_size
	return b


# --- 시그널 핸들러 ---

func _on_credit(c: int) -> void:
	_credit_label.text = "CREDIT  %d" % c


func _on_bet(b: int) -> void:
	_bet_label.text = "%d" % b


func _on_eval(r: SpinResult) -> void:
	_win_label.text = ("WIN  %d" % r.total_win) if r.total_win > 0 else ""


func _on_free_spins(remaining: int, multiplier: float) -> void:
	_status_label.text = "프리스핀 %d회  (×%.1f)" % [remaining, multiplier]


func _on_free_spins_ended() -> void:
	_status_label.text = ""


func _on_jackpot(_tier: int, _amount: int) -> void:
	_status_label.text = "★ JACKPOT ★"


## 자동스핀 상태 동기화(자금 부족 등으로 코어가 강제 해제할 수 있음 → 버튼 반영).
func _on_auto_changed(enabled: bool) -> void:
	if _auto_btn.button_pressed != enabled:
		_auto_btn.set_pressed_no_signal(enabled)   # toggled 재발행 방지
