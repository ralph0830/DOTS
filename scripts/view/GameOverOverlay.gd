class_name GameOverOverlay
extends Control
## 게임오버/승리 시 전체화면 오버레이. 탭하면 새 런으로 리스타트.
## BattleField.reset_run() 호출로 HP/유닛 리셋, WaveManager 재개.

var _label: Label
var _sub_label: Label
var _victory: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 100
	EventBus.game_over.connect(_on_game_over)

	# 배경 (반투명 어둠)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# 중앙 콘텐츠
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	vbox.custom_minimum_size = Vector2(700, 0)
	center.add_child(vbox)

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


func _on_game_over(victory: bool) -> void:
	_victory = victory
	if victory:
		_label.text = "🏆 VICTORY!"
		_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	else:
		_label.text = "💀 DEFEAT"
		_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_sub_label.text = "TAP TO RESTART"
	visible = true


## 탭/클릭 시 리스타트.
func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch and event.pressed:
		_restart()
	elif event is InputEventMouseButton and event.pressed:
		_restart()


func _restart() -> void:
	visible = false
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
