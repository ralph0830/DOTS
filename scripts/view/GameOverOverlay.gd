class_name GameOverOverlay
extends Control
## 게임오버/승리 시 전체화면 오버레이. 탭하면 새 런으로 리스타트.
## BattleField.reset_run() 호출로 HP/유닛 리셋, WaveManager 재개.
##
## 레이아웃 주의: 오버레이 자체(visible)를 끄면 Godot 가 레이아웃을 계산하지 않아
## size 가 0 으로 남고, CenterContainer 가 minimum size 만큼만 좌상단에 표시되는 버그.
## 따라서 오버레이 자체는 항상 visible + PRESET_FULL_RECT 로 두어 레이아웃을 잡고,
## 표시/숨김은 내부(_bg/_center)의 visible 토글 + mouse_filter 토글로 제어한다.

var _bg: ColorRect
var _center: CenterContainer
var _label: Label
var _sub_label: Label
var _victory: bool = false


func _ready() -> void:
	# 오버레이 자체는 항상 full rect 로 화면을 채운다 (visible 은 끄지 않음 — 끄면 layout 이 0 이 됨).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 표시 전에는 입력 통과
	z_index = 100
	EventBus.game_over.connect(_on_game_over)

	# 배경 (반투명 어둠)
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color(0.0, 0.0, 0.0, 0.75)
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
	vbox.add_theme_constant_override("separation", 30)
	vbox.custom_minimum_size = Vector2(700, 0)
	_center.add_child(vbox)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 96)
	_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_label)

	_sub_label = Label.new()
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.add_theme_font_size_override("font_size", 44)
	_sub_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(_sub_label)


## 현재 표시 중인지.
func is_shown() -> bool:
	return _bg.visible


func _on_game_over(victory: bool) -> void:
	_victory = victory
	if victory:
		_label.text = "🏆 VICTORY!"
		_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	else:
		_label.text = "💀 DEFEAT"
		_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_sub_label.text = "TAP TO RESTART"
	# 표시 직전 overlay 를 부모 전체 크기로 강제 — 부모 layout 이 늦게 잡히는 환경에서
	# overlay size 가 0 으로 남아 CenterContainer 가 좌상단에 minimum size 만큼만 표시되는 버그 방지.
	_ensure_full_rect()
	# 내부 콘텐츠 표시 + 오버레이 입력 활성화. (오버레이 자체는 항상 visible)
	_bg.visible = true
	_center.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


## overlay size 를 부모(게임 화면) 전체로 강제.
## anchor preset 만으로는 deferred _ready 시점의 layout 미확정 상태에서 size 가 0 으로 남을 수 있어,
## 표시 직전에 부모 size 로 명시 적용한다. 자식(bg/center) 도 동일 full rect 재적용.
func _ensure_full_rect() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := get_parent()
	if p is Control and p.size.x > 0.0 and p.size.y > 0.0:
		position = Vector2.ZERO
		size = p.size
	if _bg != null:
		_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _center != null:
		# CenterContainer 에도 부모 size 를 명시 적용 — anchors preset 만으로는 lazy layout
		# 타이밍에 size 가 갱신되지 않아 minimum size 만큼만 좌상단에 표시되는 버그 방지.
		_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_center.position = Vector2.ZERO
		_center.size = size


## 탭/클릭 시 리스타트.
func _gui_input(event: InputEvent) -> void:
	if not is_shown():
		return
	if event is InputEventScreenTouch and event.pressed:
		_restart()
	elif event is InputEventMouseButton and event.pressed:
		_restart()


func _restart() -> void:
	# 내부 콘텐츠 숨김 + 오버레이 입력 비활성화.
	_bg.visible = false
	_center.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 부모 SlotMachineView 의 통합 초기화 재사용 — 모든 상태를 시작값으로.
	var smv := get_tree().get_first_node_in_group(&"slot_machine_view") if get_tree().has_group(&"slot_machine_view") else null
	if smv != null and smv.has_method("_initialize_all"):
		smv._initialize_all()
		return
	# 폴백: 직접 리셋 (SlotMachineView 가 없을 때)
	var battle := _get_battle_field()
	if battle != null:
		battle.reset_run()
	var wave_mgr := _get_wave_manager()
	if wave_mgr != null and wave_mgr.has_method("restart"):
		wave_mgr.restart()
	GameManager.score = 0
	GameManager.current_wave = 0
	GameManager.enemies_killed_total = 0
	GameManager.is_defense_active = true
	GameManager.score_changed.emit(0)


func _get_battle_field() -> BattleField:
	var smv := get_tree().get_first_node_in_group(&"slot_machine_view") if get_tree().has_group(&"slot_machine_view") else null
	if smv != null and smv.has_node("BattleField"):
		return smv.get_node("BattleField") as BattleField
	return null


func _get_wave_manager() -> Node:
	var smv := get_tree().get_first_node_in_group(&"slot_machine_view") if get_tree().has_group(&"slot_machine_view") else null
	if smv != null and smv.has_node("WaveManager"):
		return smv.get_node("WaveManager")
	return null
