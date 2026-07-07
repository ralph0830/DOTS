@tool
extends Control
## 유닛 관리 패널 — 에디터 하단 탭.
## resources/units/{ally,enemy}/*.tres 의 모든 UnitData 를 한 화면에서 편집.

const UNIT_ALLY_DIR := "res://resources/units/ally/"
const UNIT_ENEMY_DIR := "res://resources/units/enemy/"

var _scroll: ScrollContainer
var _table_container: VBoxContainer
var _status_label: Label
var _units: Array = []
var _loaded: bool = false
var _loading: bool = false  # 중복 로드 방지


func _ready() -> void:
	_build_ui()


## 하단 탭이 처음 표시될 때 한 번만 로드.
func _on_visibility_changed() -> void:
	if visible and not _loaded and not _loading:
		_load_units()


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	# set_anchors_preset 를 명시적으로 호출하여 패널 전체 채우기.
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# visibility_changed 시그널 (탭 클릭 시 로드).
	# 자식이 아닌 이 노드 자체의 visibility 변경을 감지.
	visibility_changed.connect(_on_visibility_changed)

	# --- 툴바 ---
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)
	vbox.add_child(toolbar)

	var title := Label.new()
	title.text = "유닛 수치 관리"
	title.add_theme_font_size_override("font_size", 16)
	toolbar.add_child(title)

	toolbar.add_child(_make_spacer())

	var btn_save := Button.new()
	btn_save.text = "💾 모두 저장"
	btn_save.pressed.connect(_save_all)
	toolbar.add_child(btn_save)

	var btn_reload := Button.new()
	btn_reload.text = "🔄 새로고침"
	btn_reload.pressed.connect(func():
		_loaded = false
		_load_units())
	toolbar.add_child(btn_reload)

	# --- 상태 라벨 ---
	_status_label = Label.new()
	_status_label.text = "유닛을 로드하려면 '새로고침'을 누르세요."
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_status_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_status_label)

	# --- 헤더 행 ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	vbox.add_child(header)
	var headers := ["", "이름", "역할", "HP", "공격", "공속", "이속", "사거", "EXP", "도형", "크기"]
	var widths := [50, 100, 70, 55, 55, 55, 55, 55, 45, 80, 55]
	for i in range(headers.size()):
		var lbl := Label.new()
		lbl.text = headers[i]
		lbl.custom_minimum_size = Vector2(widths[i], 24)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		header.add_child(lbl)

	# --- 스크롤 테이블 ---
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(_scroll)

	_table_container = VBoxContainer.new()
	_table_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_container.add_theme_constant_override("separation", 2)
	_scroll.add_child(_table_container)


func _load_units() -> void:
	if _loading:
		return
	_loading = true
	_loaded = true

	# 기존 행 제거 (queue_free 대신 즉시 free — 동기적 처리).
	for child in _table_container.get_children():
		child.free()

	_units.clear()

	var ally_count := _load_dir(UNIT_ALLY_DIR, true)
	var enemy_count := _load_dir(UNIT_ENEMY_DIR, false)

	_status_label.text = "로드 완료: 아군 %d종, 적 %d종 (총 %d)" % [ally_count, enemy_count, ally_count + enemy_count]
	_loading = false


func _load_dir(dir_path: String, is_ally: bool) -> int:
	if not DirAccess.dir_exists_absolute(dir_path):
		_status_label.text = "디렉토리 없음: %s" % dir_path
		return 0
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0

	var section := Label.new()
	section.text = "▶ 아군 (Ally)" if is_ally else "▶ 적 (Enemy)"
	section.add_theme_font_size_override("font_size", 14)
	section.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0) if is_ally else Color(1.0, 0.4, 0.4))
	section.custom_minimum_size = Vector2(0, 28)
	_table_container.add_child(section)

	var count := 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res_path := dir_path + fname
			var data: UnitData = load(res_path)
			if data != null and data.unit_id != &"":
				_units.append({"data": data, "path": res_path, "is_ally": is_ally})
				_add_row(data, res_path, is_ally)
				count += 1
		fname = dir.get_next()
	dir.list_dir_end()
	return count


func _add_row(data: UnitData, res_path: String, is_ally: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	if not is_ally:
		row.modulate = Color(1.0, 0.92, 0.92)
	_table_container.add_child(row)

	var preview := _PreviewRect.new()
	preview.color = data.color
	preview.shape = data.shape
	preview.custom_minimum_size = Vector2(40, 40)
	row.add_child(preview)

	row.add_child(_make_label(String(data.display_name), 100))
	row.add_child(_make_label(_role_name(data.role), 70))
	row.add_child(_make_spin(data, "max_hp", 1, 9999, 55))
	row.add_child(_make_spin(data, "attack", 0, 999, 55))
	row.add_child(_make_float_spin(data, "attack_interval", 0.1, 5.0, 55))
	row.add_child(_make_float_spin(data, "move_speed", 0.0, 500.0, 55))
	row.add_child(_make_float_spin(data, "attack_range", 0.0, 500.0, 55))
	row.add_child(_make_spin(data, "exp_reward", 0, 999, 45))
	row.add_child(_make_shape_option(data, 80))
	row.add_child(_make_float_spin(data, "size", 20.0, 200.0, 55))


func _make_spin(data: UnitData, prop: String, min_val: int, max_val: int, w: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = int(data.get(prop))
	spin.custom_minimum_size = Vector2(w, 24)
	spin.value_changed.connect(func(v: float): data.set(prop, int(v)))
	return spin


func _make_float_spin(data: UnitData, prop: String, min_val: float, max_val: float, w: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = 0.1
	spin.value = float(data.get(prop))
	spin.custom_minimum_size = Vector2(w, 24)
	spin.value_changed.connect(func(v: float): data.set(prop, v))
	return spin


func _make_shape_option(data: UnitData, w: int) -> OptionButton:
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(w, 24)
	for s in ["CIRCLE", "SQUARE", "TRIANGLE", "DIAMOND", "KNIGHT", "ARCHER", "MAGE", "SKULL"]:
		opt.add_item(s)
	opt.selected = data.shape
	opt.item_selected.connect(func(idx: int): data.shape = idx)
	return opt


func _make_label(text: String, w: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(w, 24)
	lbl.add_theme_font_size_override("font_size", 13)
	return lbl


func _make_spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _role_name(role: int) -> String:
	match role:
		0: return "TANK"
		1: return "DEALER"
		2: return "SUPP"
		3: return "MINION"
		4: return "ENEMY"
		_: return "?"


func _save_all() -> void:
	var saved := 0
	for entry in _units:
		var data: UnitData = entry["data"]
		var path: String = entry["path"]
		var err := ResourceSaver.save(data, path)
		if err == OK:
			saved += 1
	_status_label.text = "저장 완료: %d개 유닛" % saved


class _PreviewRect:
	extends Control
	var color: Color = Color.WHITE
	var shape: int = 0

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.4
		var center := size * 0.5
		match shape:
			0: draw_circle(center, r, color)
			1: draw_rect(Rect2(center - Vector2(r, r), Vector2(r * 2, r * 2)), color)
			2: draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, r), center + Vector2(-r, r)]), color)
			3: draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0)]), color)
			_: draw_circle(center, r, color)
		draw_arc(center, r, 0.0, TAU, 24, color.darkened(0.3), 2.0)
