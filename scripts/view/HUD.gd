class_name HUD
extends CanvasLayer
## HUD: 크레딧/베팅/당첨/상태 표시 + 스핀·베팅·자동스핀 버튼.
## SafeArea(노치/홈 인디케이터 대응) + 터치 친화 버튼(≥120px). EventBus 구독으로 갱신(코어 직접 참조 없음).
## Container 기반 레이아웃 — 하단은 2행(베팅·AUTO / SPIN)으로 엄지 영역을 유지하며 여유 있게 배치.

const BTN_MIN := Vector2(120.0, 120.0)   # 모바일 터치 최소 권장(88px)보다 큼
const SPIN_SIZE := Vector2(300.0, 160.0)
const MARGIN := 40.0
# DEBUG: CREDIT 탭 시 증가량 (디버그 머니 — 출시 전 제거).
const DEBUG_CREDIT_ADD := 1000

var _credit_label: Label
var _bet_label: Label
var _win_label: Label
var _status_label: Label
var _auto_btn: Button
var _reroll_btn: Button
var _mult_btn: Button   # 배수 토글 (×1/×2/×3)
var _safe_root: Control
var _settings_panel: ColorRect   # 설정 오버레이 패널 (사운드 볼륨/리셋)
# 자동스핀 ON/OFF 토글.
var _auto_on := false
var _is_spinning := false   # 코어 스핀 중 (BET 조작 차단)
var _flash_tween: Tween     # BET 버튼 붉게 점멸 트윈
var _gold_box: VBoxContainer   # GOLD 표시 칸 (부족 시 RED 점멸)
var _gold_flash_tween: Tween


func _ready() -> void:
	_build_ui()
	EventBus.credit_changed.connect(_on_credit)
	EventBus.bet_changed.connect(_on_bet)
	EventBus.evaluation_completed.connect(_on_eval)
	EventBus.free_spins_changed.connect(_on_free_spins)
	EventBus.free_spins_ended.connect(_on_free_spins_ended)
	EventBus.jackpot_won.connect(_on_jackpot)
	EventBus.auto_spin_changed.connect(_on_auto_changed)
	EventBus.state_changed.connect(_on_state_changed)
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

	# 하단 조작계 배경 — 슬롯 배경 이미지(bg_mystic) 가림. 버튼 대비 향상 (불투명 어둡게).
	var ctrl_bg := ColorRect.new()
	ctrl_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl_bg.color = Color(0.05, 0.05, 0.10, 0.92)
	ctrl_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe_root.add_child(ctrl_bg)
	# 외곽 여백 컨테이너
	var margin_c := MarginContainer.new()
	margin_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin_c.add_theme_constant_override("margin_left", int(MARGIN))
	margin_c.add_theme_constant_override("margin_right", int(MARGIN))
	margin_c.add_theme_constant_override("margin_top", 5)
	margin_c.add_theme_constant_override("margin_bottom", 8)
	margin_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe_root.add_child(margin_c)

	# 수직 레이아웃: 상단 spacer(릴 영역) / 정보 바 / 버튼 2행.
	# Phase 7: 릴은 SlotMachineView._layout_reels 가 직접 배치 (상단 540px 점유).
	# HUD 는 그 아래 정보 바(CREDIT/BET/WIN) + 버튼(SPIN/BET/AUTO)만 담당.
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin_c.add_child(vbox)

	# 상단 spacer — 릴 영역(540px)만큼 공간 확보. HUD는 릴 아래부터 시작.
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 0.0)   # 조작계 10% — 릴 공간 spacer 불필요
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_spacer)

	# 정보바 더미 라벨(조작계에 공간 집중, 표시 안 함).
	_credit_label = Label.new()
	_bet_label = Label.new()
	_win_label = Label.new()
	# 조작계 1행 — GOLD / SPIN / 배수 / AUTO / REROLL.
	vbox.add_child(_build_controls())
	# 경고 토스트는 별도 레이어(_safe_root 밖) — vbox 레이아웃 영향 없이 전체 화면 오버레이.
	_build_toast_layer()


## 경고 토스트 별도 레이어 — HUD(CanvasLayer) 직접 자식, full rect. 조작계 레이아웃에 영향 X.
func _build_toast_layer() -> void:
	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 42)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.2))
	_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_status_label.add_theme_constant_override("outline_size", 12)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.visible = false
	add_child(_status_label)   # _safe_root 가 아닌 HUD 직접 자식 = 전체 화면


## 조작계 1행 4버튼 (동일 크기 EXPAND_FILL) — SPIN / ×1 / AUTO / REROLL.
func _build_controls() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# GOLD 표시 (SPIN 왼쪽) — 현재 보유 골드. DEBUG: 탭 시 +1000.
	_gold_box = VBoxContainer.new()
	_gold_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gold_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_gold_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_gold_box.gui_input.connect(_on_credit_clicked)
	_gold_box.add_child(_make_label("GOLD", 22, Color(0.85, 0.7, 0.3, 0.95)))
	_credit_label = _make_label("0", 38, Color(1.0, 0.85, 0.25))
	_credit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_box.add_child(_credit_label)
	bar.add_child(_gold_box)
	# SPIN
	var spin := _make_button("SPIN", BTN_MIN)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.add_theme_font_size_override("font_size", 40)
	spin.pressed.connect(_on_spin_pressed)
	bar.add_child(spin)
	# 배수 (×1/×2/×3)
	_mult_btn = _make_button("×1", BTN_MIN)
	_mult_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mult_btn.add_theme_font_size_override("font_size", 40)
	_mult_btn.pressed.connect(_on_mult_pressed)
	bar.add_child(_mult_btn)
	# AUTO
	_auto_btn = _make_button("AUTO", BTN_MIN)
	_auto_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto_btn.add_theme_font_size_override("font_size", 32)
	_auto_btn.pressed.connect(_on_auto_pressed)
	bar.add_child(_auto_btn)
	# REROLL
	_reroll_btn = _make_button("REROLL", BTN_MIN)
	_reroll_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reroll_btn.add_theme_font_size_override("font_size", 24)
	_reroll_btn.disabled = true
	_reroll_btn.pressed.connect(_on_reroll_pressed)
	bar.add_child(_reroll_btn)
	return bar


## 정보 바: CREDIT (좌) / BET (중앙) / WIN (우) — 릴 아래 한 줄 균등 배치.
func _build_info_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# CREDIT (좌) — 노란색. DEBUG: 탭 시 +1000 (디버그 머니).
	var credit_box := VBoxContainer.new()
	credit_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	credit_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credit_box.mouse_filter = Control.MOUSE_FILTER_STOP
	credit_box.gui_input.connect(_on_credit_clicked)
	credit_box.add_child(_make_label("CREDIT", 24, Color(0.7, 0.65, 0.4, 0.9)))
	_credit_label = _make_label("0", 40, Color(1.0, 0.9, 0.3))
	credit_box.add_child(_credit_label)
	bar.add_child(credit_box)

	# BET (중앙) — 흰색
	var bet_box := VBoxContainer.new()
	bet_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bet_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bet_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bet_box.add_child(_make_label("BET", 24, Color(0.7, 0.7, 0.7, 0.9)))
	_bet_label = _make_label("0", 40, Color.WHITE)
	bet_box.add_child(_bet_label)
	bar.add_child(bet_box)

	# WIN (우) — 녹색
	var win_box := VBoxContainer.new()
	win_box.alignment = BoxContainer.ALIGNMENT_END
	win_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	win_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_box.add_child(_make_label("WIN", 24, Color(0.4, 0.7, 0.5, 0.9)))
	_win_label = _make_label("0", 40, Color(0.5, 1.0, 0.6))
	win_box.add_child(_win_label)
	bar.add_child(win_box)

	# 설정 버튼(⚙) — 맨 우측 끝 (작게).
	var gear := _make_button("⚙", Vector2(70.0, 70.0))
	gear.add_theme_font_size_override("font_size", 36)
	gear.pressed.connect(_toggle_settings)
	bar.add_child(gear)
	return bar


## 설정 패널 토글(열기/닫기). 세로 중앙에 모달처럼 표시.
func _toggle_settings() -> void:
	if _settings_panel != null:
		_settings_panel.visible = not _settings_panel.visible
		return
	_build_settings_panel()


## 설정 패널 구성: 사운드 볼륨 슬라이더 + 음소거 + 크레딧 리셋 + 닫기.
func _build_settings_panel() -> void:
	_settings_panel = ColorRect.new()
	_settings_panel.color = Color(0.05, 0.05, 0.12, 0.85)
	_settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_safe_root.add_child(_settings_panel)
	# 중앙 콘텐츠 컨테이너
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.custom_minimum_size = Vector2(500, 0)
	center.add_child(vbox)
	# 제목
	vbox.add_child(_make_label("⚙ SETTINGS", 48, Color(1.0, 0.9, 0.3)))
	# 사운드 볼륨 슬라이더
	var vol_label := _make_label("SOUND", 32, Color.WHITE)
	vbox.add_child(vol_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = AudioManager.get_master_volume()
	slider.custom_minimum_size = Vector2(500, 60)
	slider.value_changed.connect(func(v: float) -> void: AudioManager.set_master_volume(v))
	vbox.add_child(slider)
	# 음소거 토글
	var mute_btn := _make_button("MUTE", BTN_MIN)
	mute_btn.toggle_mode = true
	mute_btn.button_pressed = AudioManager.master_muted
	mute_btn.toggled.connect(func(on: bool) -> void:
		AudioManager.set_muted(on))
	vbox.add_child(mute_btn)
	# 크레딧 리셋
	var reset_btn := _make_button("RESET CREDIT", BTN_MIN)
	reset_btn.add_theme_font_size_override("font_size", 28)
	reset_btn.pressed.connect(func() -> void:
		WalletManager.reset_credit(GameConfig.config.starting_credit))
	vbox.add_child(reset_btn)
	# 닫기
	var close_btn := _make_button("CLOSE", BTN_MIN)
	close_btn.add_theme_font_size_override("font_size", 32)
	close_btn.pressed.connect(_toggle_settings)
	vbox.add_child(close_btn)


## 하단 행1: 베팅 감소(-) / 베팅 증가(+) (좌) … (spacer) … AUTO (우).
## BET 금액 자체는 정보 바(_build_info_bar)에 표시됨 — 여기선 +/- 버튼만.
func _build_bet_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 18)

	# 배수 토글 (×1/×2/×3) — 베팅+소환 양쪽 배수.
	_mult_btn = _make_button("×1", BTN_MIN)
	_mult_btn.add_theme_font_size_override("font_size", 40)
	_mult_btn.pressed.connect(_on_mult_pressed)
	bar.add_child(_mult_btn)

	# 우측으로 밀어 AUTO를 끝으로 정렬
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	# 리롤 버튼 (스핀 리롤러 카드 — reroll_charges > 0 시 활성).
	_reroll_btn = _make_button("리롤", BTN_MIN)
	_reroll_btn.add_theme_font_size_override("font_size", 24)
	_reroll_btn.pressed.connect(_on_reroll_pressed)
	_reroll_btn.disabled = true
	bar.add_child(_reroll_btn)

	# 자동스핀 순환 버튼: AUTO → ×10 → ×25 → ×50 → ∞ → AUTO 반복.
	_auto_btn = _make_button("AUTO", BTN_MIN)
	_auto_btn.add_theme_font_size_override("font_size", 32)
	_auto_btn.pressed.connect(_on_auto_pressed)
	bar.add_child(_auto_btn)
	return bar


## AUTO 버튼 클릭 시 순환. AUTO(끔) → ×10 → ×25 → ×50 → ∞ → AUTO(끔).
func _on_auto_pressed() -> void:
	_auto_on = not _auto_on
	_auto_btn.text = "AUTO ON" if _auto_on else "AUTO"
	EventBus.auto_spin_changed.emit(_auto_on, -1 if _auto_on else 0)


## DEBUG: CREDIT 영역 탭/클릭 시 디버그 머니 증가 (+1000). 출시 전 제거.
func _on_credit_clicked(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		WalletManager.add_credit(DEBUG_CREDIT_ADD)
	elif event is InputEventMouseButton and event.pressed:
		WalletManager.add_credit(DEBUG_CREDIT_ADD)


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
	spin.pressed.connect(func() -> void:
		EventBus.spin_requested.emit())
	bar.add_child(spin)
	return bar


## 디스플레이 안전 영역(노치/홈 인디케이터 제외)을 design 해상도 좌표로 변환해 루트 offset 적용.
## 데스크톱(노치 없음)에서는 offset 0 — 모바일에서만 창 내부 기준으로 안전하게 계산.
## (이전 구현이 모니터 전체 safe area 를 창 크기로 환산해 작은 창에서 offset 이 폭주하여
##  HUD 전체가 화면 밖으로 밀려 보이지 않던 버그 수정 — 2026-07-03.)
# Phase 7: 상하 분할 — 전투(Layout.battle_h) / 슬롯(Layout.slot_h). HUD는 하단 슬롯 영역만 차지.


func _apply_safe_area() -> void:
	# Phase 7: HUD를 하단 슬롯 영역(전투 영역 아래 ~ 화면 끝)으로 제한.
	# _safe_root anchors 를 명시적으로 하단 영역으로 설정 (FULL_RECT 대신 커스텀).
	# anchor_top=전투 비율(Layout.BATTLE_RATIO=0.55), anchor_bottom=1.0 (하단 끝).
	var design := get_window().content_scale_size
	if design.y > 0.0:
		# 조작계 영역 — 상단 margin + 전투+슬롯 아래 ~ 하단 margin 위.
		var ratio := Layout.control_top_ratio()
		_safe_root.anchor_top = ratio
		_safe_root.anchor_bottom = 1.0 - Layout.BOTTOM_MARGIN
		_safe_root.anchor_left = 0.0
		_safe_root.anchor_right = 1.0
		_safe_root.offset_left = 0.0
		_safe_root.offset_top = 0.0
		_safe_root.offset_right = 0.0
		_safe_root.offset_bottom = 0.0
	# 모바일 SafeArea 추가 보정.
	var platform := OS.get_name()
	if platform != "Android" and platform != "iOS":
		return
	var safe := DisplayServer.get_display_safe_area()
	var win := get_window().get_size()
	if win.x <= 0 or win.y <= 0:
		return
	if safe.end.x <= safe.position.x or safe.end.y <= safe.position.y:
		return
	if safe.end.x > win.x or safe.end.y > win.y:
		return
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
	_credit_label.text = "%d" % c


func _on_bet(b: int) -> void:
	_bet_label.text = "%d" % b


func _on_eval(r: SpinResult) -> void:
	_win_label.text = ("WIN  %d" % r.total_win) if r.total_win > 0 else ""
	_update_reroll_btn()


func _on_free_spins(remaining: int, multiplier: float) -> void:
	_status_label.text = "프리스핀 %d회  (×%.1f)" % [remaining, multiplier]


func _on_free_spins_ended() -> void:
	_status_label.text = ""


func _on_jackpot(_tier: int, _amount: int) -> void:
	_status_label.text = "★ JACKPOT ★"


## 자동스핀 상태 동기화(자금 부족/손실한도/횟수 소진으로 코어가 강제 해제 → 버튼 반영).
func _on_auto_changed(enabled: bool, _remaining: int) -> void:
	if not enabled:
		_auto_on = false
		_auto_btn.text = "AUTO"   # OFF 로 복귀


## bet_level 토글 — ×1 → ×3 → ×5 → ×1 3단계 순환(x2/x4 제거). SPIN 중/AUTO ON 중은 조작 불가.
func _on_mult_pressed() -> void:
	if _is_spinning:
		_show_toast("스핀 중 — BET 조작 불가")
		_flash_bet_button()
		return
	if _auto_on:
		_show_toast("AUTO ON 중 — BET 조작 불가")
		_flash_bet_button()
		return
	# ×1 → ×3 → ×5 → ×1 (불연속 단계).
	match WalletManager.bet_level:
		1: WalletManager.bet_level = 3
		3: WalletManager.bet_level = 5
		_: WalletManager.bet_level = 1
	if _mult_btn != null:
		_mult_btn.text = "×%d" % WalletManager.bet_level
	EventBus.bet_level_changed.emit(WalletManager.bet_level)


## BET 버튼 붉게 점멸 (SPIN/AUTO 중 조작 시도 시 강제 피드백).
func _flash_bet_button() -> void:
	if _mult_btn == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_mult_btn.modulate = Color(1.0, 0.25, 0.25)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_mult_btn, "modulate", Color.WHITE, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## SPIN 버튼 — GOLD 부족 시 경고 토스트 + GOLD 칸 RED 점멸. 아니면 스핀 요청.
func _on_spin_pressed() -> void:
	if not WalletManager.can_bet():
		_show_toast("GOLD가 부족합니다")
		_flash_gold()
		return
	EventBus.spin_requested.emit()


## GOLD 표시 칸 붉게 점멸 (GOLD 부족 시 강제 피드백).
func _flash_gold() -> void:
	if _gold_box == null:
		return
	if _gold_flash_tween != null and _gold_flash_tween.is_valid():
		_gold_flash_tween.kill()
	_gold_box.modulate = Color(1.0, 0.2, 0.2)
	_gold_flash_tween = create_tween()
	_gold_flash_tween.tween_property(_gold_box, "modulate", Color.WHITE, 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 코어 상태 전이 수신 — SPIN 중 여부 추적 (BET 조작 차단용).
func _on_state_changed(_from: int, to: int) -> void:
	_is_spinning = (to != SlotMachine.State.IDLE)


var _toast_timer: float = 0.0

## 경고 토스트 — 2초간 중앙에 표시 후 자동 숨김.
func _show_toast(msg: String) -> void:
	if _status_label == null:
		return
	_status_label.text = msg
	_status_label.visible = true
	_toast_timer = 2.0
	set_process(true)


func _process(_delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= _delta
		if _toast_timer <= 0.0 and _status_label != null:
			_status_label.visible = false
			set_process(false)


## 리롤 버튼 — reroll_requested emit (SlotMachine 이 무료 재스핀).
func _on_reroll_pressed() -> void:
	EventBus.reroll_requested.emit()


## 리롤 버튼 상태 갱신 — reroll_charges 표시/활성화.
func _update_reroll_btn() -> void:
	if _reroll_btn == null:
		return
	var lord := get_node_or_null("/root/LordState")
	var charges := 0
	if lord != null:
		charges = int(lord.get("reroll_charges"))
	_reroll_btn.text = ("리롤 %d" % charges) if charges > 0 else "리롤"
	_reroll_btn.disabled = charges <= 0
