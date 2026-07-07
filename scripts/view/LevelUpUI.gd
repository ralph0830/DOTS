class_name LevelUpUI
extends Control
## 레벨업 3지선다 카드 UI (Phase 8-B).
## EventBus.level_up_available 수신 → 게임 일시정지 → 3장 카드 표시 → 선택 시 효과 적용 + 재개.
##
## 패턴 (GameOverOverlay 참고):
##   - Control + z_index=100 + MOUSE_FILTER_STOP (릴 아래 입력 차단)
##   - process_mode = PROCESS_MODE_WHEN_PAUSED (일시정지 중 UI만 동작)
##   - bg ColorRect (어두운 오버레이) + 중앙 카드 컨테이너

const CARD_SIZE := Vector2(280.0, 420.0)
const CARD_SEPARATION := 40.0

var _bg: ColorRect
var _card_container: HBoxContainer
var _title_label: Label
var _cards: Array = []   # 현재 표시 중인 LevelUpChoice 목록
var _lord_node: Node     # LordState autoload (선택지 적용 대상)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 100
	# 일시정지 중에도 UI 동작 — 게임은 멈추고 카드 선택만 가능.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	EventBus.level_up_available.connect(_on_level_up_available)
	_build_ui()


func _build_ui() -> void:
	# 배경 (어두운 반투명)
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color(0.02, 0.02, 0.08, 0.92)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	# 중앙 콘텐츠
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 40)
	vbox.custom_minimum_size = Vector2(960, 0)
	center.add_child(vbox)

	# 타이틀
	_title_label = Label.new()
	_title_label.text = "✦ 레벨 업 ✦"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 64)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	vbox.add_child(_title_label)

	# 카드 컨테이너 (가로 3장)
	_card_container = HBoxContainer.new()
	_card_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_container.add_theme_constant_override("separation", int(CARD_SEPARATION))
	_card_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_card_container)


## 레벨업 가능 시그널 수신 → 일시정지 + 카드 표시.
func _on_level_up_available(_level: int) -> void:
	_lord_node = get_node_or_null("/root/LordState")
	if _lord_node == null:
		push_error("[LevelUpUI] LordState autoload 없음 — 레벨업 UI 건너뜀")
		SoulGauge.complete_level_up()
		return
	# 선택지 3장 추출
	_cards = _lord_node.roll_choices(3)
	if _cards.is_empty():
		# 선택 가능한 카드가 없으면 바로 레벨업 완료
		SoulGauge.complete_level_up()
		return
	# 카드 렌더링
	_render_cards(_cards)
	# 게임 일시정지 + UI 표시
	get_tree().paused = true
	visible = true
	var names := []
	for c in _cards:
		var ch: LevelUpChoice = c
		names.append(String(ch.display_name))
	print("[LevelUpUI] 레벨업 UI 표시 — 카드 %d장: %s" % [_cards.size(), str(names)])


## 3장 카드를 HBoxContainer 에 렌더링.
func _render_cards(choices: Array) -> void:
	# 기존 카드 제거
	for child in _card_container.get_children():
		child.queue_free()
	# 새 카드 생성
	for i in range(choices.size()):
		var choice = choices[i]
		var card := _make_card(choice, i)
		_card_container.add_child(card)


## 단일 카드 Control 생성 (터치 시 _on_card_selected 호출).
func _make_card(choice_res: Resource, index: int) -> Control:
	var choice: LevelUpChoice = choice_res
	var card := Panel.new()
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	# 카드 배경 (진한 색 + 선택지 색상 테두리 느낌)
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.1, 0.1, 0.18, 1.0)
	stylebox.border_color = choice.icon_color
	stylebox.set_border_width_all(4)
	stylebox.set_corner_radius_all(12)
	stylebox.set_content_margin_all(20)
	card.add_theme_stylebox_override("panel", stylebox)
	# 터치 시 카드 인덱스 전달
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenTouch and event.pressed:
			_on_card_selected(index)
		elif event is InputEventMouseButton and event.pressed:
			_on_card_selected(index))

	# 카드 내용 (VBox: 아이콘 도형 + 제목 + 설명)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	# 아이콘 도형 (선택지 색상 원)
	var icon := _IconRect.new()
	icon.color = choice.icon_color
	icon.custom_minimum_size = Vector2(120, 120)
	vbox.add_child(icon)

	# 제목
	var title := Label.new()
	title.text = choice.display_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", choice.icon_color.lightened(0.3))
	vbox.add_child(title)

	# 설명
	var desc := Label.new()
	desc.text = choice.description
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 24)
	desc.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(CARD_SIZE.x - 60, 0)
	vbox.add_child(desc)

	return card


## 카드 선택 처리 — 효과 적용 + 게임 재개.
func _on_card_selected(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	var choice: LevelUpChoice = _cards[index]
	print("[LevelUpUI] 카드 선택: %s" % choice.display_name)
	# ChoiceEffect.apply() 실행 (duck-typing — effect는 Resource, apply 메서드 호출)
	if choice.effect != null and choice.effect.has_method("apply"):
		choice.effect.apply(_lord_node)
	# UI 숨기기 + 게임 재개
	visible = false
	get_tree().paused = false
	_cards.clear()
	# SoulGauge 레벨업 완료 처리 (다음 게이지 리셋)
	SoulGauge.complete_level_up()


# --- 내부 아이콘 도형 (단순 색상 원) ---
class _IconRect:
	extends Control
	var color: Color = Color.WHITE
	func _init() -> void:
		pass
	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		draw_circle(size * 0.5, r, color)
		# 외곽선 (밝게)
		draw_arc(size * 0.5, r, 0.0, TAU, 32, color.lightened(0.5), 3.0)
