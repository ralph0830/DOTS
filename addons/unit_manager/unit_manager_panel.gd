@tool
extends Control
## 유닛 관리 패널 — 에디터 하단 탭.
## resources/units/{ally,enemy}/*.tres 의 모든 UnitData 를 한 화면에서 편집.

const UNIT_ALLY_DIR := "res://resources/units/ally/"
const UNIT_ENEMY_DIR := "res://resources/units/enemy/"
# inner class 대신 별도 @tool 파일 — 에디터에서 도형 _draw() 가 호출되려면 분리 필요.
const PreviewRect := preload("res://addons/unit_manager/unit_preview_rect.gd")

# 진단 로그 토글. 문제 해결 확인 후 false 로 변경.
const DEBUG := false

var _vbox: VBoxContainer
var _scroll: ScrollContainer
var _table_container: VBoxContainer
var _status_label: Label
var _units: Array = []
var _loaded: bool = false
var _loading: bool = false  # 중복 로드 방지


## DEBUG 토글용 래퍼 — 한 곳에서 로그 on/off.
func _dbg(msg: String) -> void:
	if DEBUG:
		print("[UnitManager] ", msg)


func _ready() -> void:
	_dbg("_ready() 진입 — visible=%s" % visible)
	_build_ui()
	_dbg("_ready() _build_ui 완료 — 루트 자식 수 %d" % get_child_count())
	# _ready 직후 바로 로드 (플러그인이 make_bottom_panel_item_visible 로 펼칠 것).
	call_deferred("_load_units")


## 하단 탭 표시 시 아직 로드 안 됐으면 로드.
func _on_visibility_changed() -> void:
	_dbg("visibility_changed — visible=%s loaded=%s loading=%s" % [visible, _loaded, _loading])
	if visible and not _loaded and not _loading:
		_load_units()


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	# 루트 자신을 부모(하단 패널 dock)에 꽉 채우기.
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# ★ 핵심 수정: vbox 도 루트를 꽉 채워야 자식(특히 ScrollContainer)이
	#   EXPAND 공간을 받아 표시됨. anchor 미설정 시 vbox 는 minimum size 로 고정되어
	#   ScrollContainer 의 expand 공간이 사라지고 높이가 0 → 행이 화면에 안 보임.
	_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_vbox)
	_dbg("_build_ui: vbox 추가 — size=%s" % _vbox.size)

	# visibility_changed 시그널 (탭 클릭 시 로드).
	# 자식이 아닌 이 노드 자체의 visibility 변경을 감지.
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)

	# --- 툴바 ---
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)
	_vbox.add_child(toolbar)

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
	_vbox.add_child(_status_label)

	# --- 헤더 행 ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	_vbox.add_child(header)
	var headers := ["", "이름", "역할", "행동", "HP", "공격", "공속", "이속", "사거", "EXP", "CREDIT", "도형", "가로", "세로"]
	var widths := [50, 100, 70, 60, 55, 55, 55, 55, 55, 45, 55, 80, 45, 45]
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
	# 레이아웃이 잡히기 전 expand 공간이 없을 때도 행이 보이도록 최소 높이 보장.
	_scroll.custom_minimum_size = Vector2(0, 120)
	_vbox.add_child(_scroll)

	_table_container = VBoxContainer.new()
	_table_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table_container.add_theme_constant_override("separation", 2)
	_scroll.add_child(_table_container)
	_dbg("_build_ui: 컨테이너 구축 완료 — scroll.size=%s table.size=%s" % [_scroll.size, _table_container.size])


func _load_units() -> void:
	_dbg("_load_units() 진입 — loading=%s loaded=%s" % [_loading, _loaded])
	if _loading:
		_dbg("_load_units: 이미 로딩 중 → 반환")
		return
	# 새로고침이 _loaded=false 로 풀지 않는 한, 두 번째 call_deferred 는 여기서 차단.
	if _loaded:
		_dbg("_load_units: 이미 로드됨(_loaded=true) → 반환")
		return
	_loading = true
	_loaded = true

	# 기존 행 제거 (queue_free 대신 즉시 free — 동기적 처리).
	for child in _table_container.get_children():
		child.free()

	_units.clear()
	_dbg("_load_units: 기존 행 제거 완료 — table 자식 수 %d" % _table_container.get_child_count())

	var ally_count := _load_dir(UNIT_ALLY_DIR, true)
	var enemy_count := _load_dir(UNIT_ENEMY_DIR, false)

	_status_label.text = "로드 완료: 아군 %d종, 적 %d종 (총 %d)" % [ally_count, enemy_count, ally_count + enemy_count]
	_dbg("_load_units() 완료 — 아군 %d, 적 %d, table 자식 수 %d" % [ally_count, enemy_count, _table_container.get_child_count()])
	_dbg("_load_units: table.size=%s scroll.size=%s vbox.size=%s" % [_table_container.size, _scroll.size, _vbox.size])
	_loading = false


func _load_dir(dir_path: String, is_ally: bool) -> int:
	if not DirAccess.dir_exists_absolute(dir_path):
		_status_label.text = "디렉토리 없음: %s" % dir_path
		_dbg("_load_dir: 디렉토리 없음 — %s" % dir_path)
		return 0
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_dbg("_load_dir: DirAccess.open 실패 — %s" % dir_path)
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
				_dbg("_load_dir: 행 추가 — %s (table 자식 수 %d)" % [data.display_name, _table_container.get_child_count()])
			else:
				_dbg("_load_dir: 스킵 — %s (data=%s)" % [res_path, data])
		fname = dir.get_next()
	dir.list_dir_end()
	return count


func _add_row(data: UnitData, res_path: String, is_ally: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	if not is_ally:
		row.modulate = Color(1.0, 0.92, 0.92)
	_table_container.add_child(row)

	var preview := PreviewRect.new()
	preview.color = data.color
	preview.shape = int(data.shape)
	preview.custom_minimum_size = Vector2(40, 40)
	row.add_child(preview)

	row.add_child(_make_label(String(data.display_name), 100))
	row.add_child(_make_label(_role_name(int(data.role)), 70))
	row.add_child(_make_behavior_option(data, 60))
	row.add_child(_make_spin(data, "max_hp", 1, 9999, 55))
	row.add_child(_make_spin(data, "attack", 0, 999, 55))
	row.add_child(_make_float_spin(data, "attack_interval", 0.1, 5.0, 55))
	row.add_child(_make_float_spin(data, "move_speed", 0.0, 500.0, 55))
	row.add_child(_make_float_spin(data, "attack_range", 0.0, 500.0, 55))
	row.add_child(_make_spin(data, "exp_reward", 0, 999, 45))
	row.add_child(_make_spin(data, "credit_reward", 0, 99999, 55))
	row.add_child(_make_shape_option(data, 80))
	row.add_child(_make_float_spin(data, "size_w", 10.0, 300.0, 45))
	row.add_child(_make_float_spin(data, "size_h", 10.0, 300.0, 45))


func _make_spin(data: UnitData, prop: String, min_val: int, max_val: int, w: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	var v = data.get(prop)
	spin.value = int(v) if v != null else 0
	spin.custom_minimum_size = Vector2(w, 24)
	spin.value_changed.connect(func(val: float): data.set(prop, int(val)))
	return spin


func _make_float_spin(data: UnitData, prop: String, min_val: float, max_val: float, w: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = 0.1
	var v = data.get(prop)
	spin.value = float(v) if v != null else 0.0
	spin.custom_minimum_size = Vector2(w, 24)
	spin.value_changed.connect(func(val: float): data.set(prop, val))
	return spin


func _make_behavior_option(data: UnitData, w: int) -> OptionButton:
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(w, 24)
	for b in ["MELEE", "RANGED", "SUPPORT"]:
		opt.add_item(b)
	opt.selected = int(data.behavior)
	opt.item_selected.connect(func(idx: int): data.behavior = idx)
	return opt


func _make_shape_option(data: UnitData, w: int) -> OptionButton:
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(w, 24)
	# UnitData.Shape enum = 4개(CIRCLE, SQUARE, TRIANGLE, DIAMOND)와 정확히 일치.
	for s in ["CIRCLE", "SQUARE", "TRIANGLE", "DIAMOND"]:
		opt.add_item(s)
	opt.selected = int(data.shape)
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
