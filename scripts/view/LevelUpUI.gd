class_name LevelUpUI
extends Control
## 레벨업 3지선다 카드 UI (Phase 8-B).
## EventBus.level_up_available 수신 → 게임 일시정지 → 3장 카드 표시 → 선택 시 효과 적용 + 재개.
##
## 레이아웃 주의 (GameOverOverlay 와 동일): 오버레이 자체(visible)를 끄면 Godot 가 layout 을
## 계산하지 않아 size 가 0 이 되고, CenterContainer 가 좌상단에 minimum size 만큼만 표시되는 버그.
## 따라서 오버레이는 항상 visible + full rect 로 두고, 표시/숨김은 내부(_bg/_center)의 visible
## 토글 + mouse_filter 토글로 제어한다.

const CARD_W := 800.0
const CARD_H := 190.0
const CARD_SIZE := Vector2(CARD_W, CARD_H)   # 세로 1×3 — 3카드 + 2간격(35*2) = 640px
const CARD_SEPARATION := 35.0

var _bg: ColorRect
var _center: CenterContainer
var _card_container: BoxContainer
var _title_label: Label
var _cards: Array = []   # 현재 표시 중인 LevelUpChoice 목록
var _lord_node: Node     # LordState autoload (선택지 적용 대상)
var _selected: bool = false   # 카드 선택 여부 (중복 터치 방지)


func _ready() -> void:
	# 오버레이 자체는 항상 full rect 로 화면을 채운다 (visible 은 끄지 않음 — 끄면 layout 이 0 이 됨).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# top_level = true — 부모(SlotMachineView/BattleField) transform(스크롤/카메라 offset)과
	# 완전 분리되어 항상 화면 중앙에 고정. 두 번째 레벨업부터 팝업이 우측으로 밀리는 버그 방지.
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 표시 전에는 입력 통과
	z_index = 100
	# 일시정지 중에도 UI 동작 — 게임은 멈추고 카드 선택만 가능.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	EventBus.level_up_available.connect(_on_level_up_available)
	_build_ui()


func _build_ui() -> void:
	# 배경 (어두운 반투명)
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color(0.02, 0.02, 0.08, 0.92)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_bg.visible = false                          # 표시 전 숨김
	add_child(_bg)

	# 중앙 콘텐츠
	# size_flags EXPAND_FILL 필수 — 부모(오버레이 full rect)를 채워야 중앙 정렬됨.
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.visible = false                      # 표시 전 숨김
	add_child(_center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 40)
	vbox.custom_minimum_size = Vector2(CARD_W, 640.0)
	_center.add_child(vbox)

	# 타이틀
	_title_label = Label.new()
	_title_label.text = "✦ 레벨 업 ✦"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 64)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	vbox.add_child(_title_label)

	# 카드 컨테이너 (세로 1×3)
	_card_container = VBoxContainer.new()
	_card_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_container.add_theme_constant_override("separation", int(CARD_SEPARATION))
	_card_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	# 표시 직전 overlay 를 부모 전체로 강제 — lazy layout 으로 size=0 되어 CenterContainer 가
	# 좌상단에 표시되는 버그 방지 (GameOverOverlay 와 동일).
	_ensure_full_rect()
	_bg.visible = true
	_center.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 게임 일시정지
	get_tree().paused = true
	var names := []
	for c in _cards:
		var ch: LevelUpChoice = c
		names.append(String(ch.display_name))
	print("[LevelUpUI] 레벨업 UI 표시 — 카드 %d장: %s" % [_cards.size(), str(names)])


## overlay size 를 화면(viewport) 전체로 강제.
## top_level = true 이므로 부모가 아닌 viewport 기준 — 부모 transform 영향 없이 항상 전체 화면.
func _ensure_full_rect() -> void:
	var vp := get_viewport().get_visible_rect().size
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if vp.x > 0.0 and vp.y > 0.0:
		position = Vector2.ZERO
		size = vp
	if _bg != null:
		_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _center != null:
		# CenterContainer 에도 viewport size 를 명시 적용 — lazy layout 타이밍에 size 가
		# 갱신되지 않아 minimum size 만큼만 표시되는 버그 방지.
		_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_center.position = Vector2.ZERO
		_center.size = size


## 3장 카드를 HBoxContainer 에 렌더링.
func _render_cards(choices: Array) -> void:
	_selected = false   # 새 레벨업 카드 세트 — 선택 잠금 해제
	# 기존 카드 즉시(동기) 제거 — queue_free 는 다음 프레임이라 두 번째 레벨업 시
	# 이전 카드가 남아 HBox 가 넘치고, 그 결과 카드들이 우측으로 밀려 일부만 보이는 버그 방지.
	for child in _card_container.get_children():
		_card_container.remove_child(child)
		child.free()
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
	# 터치 피드백 — 누름 시 축소·밝게 강조, 뗄 때 선택. 중복 터치 방지(_selected 가드).
	card.pivot_offset = CARD_SIZE * 0.5
	card.gui_input.connect(func(event: InputEvent):
		if _selected:
			return
		var pressed := false
		if event is InputEventScreenTouch:
			pressed = event.pressed
		elif event is InputEventMouseButton:
			pressed = event.pressed
		else:
			return
		if pressed:
			# 눌림 시각 피드백 (축소 + 밝게).
			card.scale = Vector2(0.96, 0.96)
			card.modulate = Color(1.15, 1.15, 1.15)
		else:
			# 뗄 때 원래 상태 복원 + 선택 처리.
			card.scale = Vector2.ONE
			card.modulate = Color.WHITE
			_on_card_selected(index))

	# 카드 내용 — HBox: [아이콘 좌측] [이름/설명 우측 세로]
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	card.add_child(hbox)

	# 아이콘 도형 (좌측 정렬)
	var icon := _IconRect.new()
	icon.color = choice.icon_color
	icon.custom_minimum_size = Vector2(120, 120)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(icon)

	# 이름/설명 세로 박스 (우측, EXPAND_FILL)
	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 12)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(text_box)

	# 제목 (좌측 정렬)
	var title := Label.new()
	title.text = choice.display_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", choice.icon_color.lightened(0.3))
	text_box.add_child(title)

	# 설명 (좌측 정렬)
	var desc := Label.new()
	desc.text = choice.description
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc.add_theme_font_size_override("font_size", 22)
	desc.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(desc)

	return card


## 카드 선택 처리 — 효과 적용 + 게임 재개.
func _on_card_selected(index: int) -> void:
	if _selected:
		return   # 중복 터치 방지
	if index < 0 or index >= _cards.size():
		return
	_selected = true
	var choice: LevelUpChoice = _cards[index]
	print("[LevelUpUI] 카드 선택: %s" % choice.display_name)
	# ChoiceEffect.apply() 실행 (duck-typing — effect는 Resource, apply 메서드 호출)
	if choice.effect != null and choice.effect.has_method("apply"):
		choice.effect.apply(_lord_node)
	# 내부 숨김 + 오버레이 입력 비활성화 + 게임 재개
	_bg.visible = false
	_center.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
