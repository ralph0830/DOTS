class_name BattleFieldView
extends Control
## 상단 전투 영역 뷰 — 전투 배경 + 전투 라인/기지 + 상단 정보바.
## 상단 정보바 (3분할): 체력(좌) / 웨이브(중앙) / 보스 게이지(우, 보스 등장 시).
## 하단 경험치(영혼) 게이지. 실제 유닛/적 렌더링은 BattleField(Node2D).

const BG_PATH := "res://assets/backgrounds/background_battle_ground_midnight.jpg"
# 소환 알림 유닛 한글명 매핑.
const _UNIT_NAME_KO := {
	&"knight": "기사", &"archer": "궁수", &"mage": "마법사", &"minion": "미니언",
}

var _bg_tex: Texture2D
var _bg_phase: float = 0.0   # 배경 미세 fade 위상(10초 주기)
var _ally_hp: int = 100
var _ally_max: int = 100
var _enemy_hp: int = 100
var _enemy_max: int = 100
var _soul: int = 0
var _soul_max: int = 15
var _level: int = 1
var _wave_num: int = 0
var _boss_active: bool = false
var _wave_banner: Label = null
var _banner_tween: Tween = null
var _banner_queue: Array = []   # 순차 배너(WAVE → BOSS) 재생 큐
var _spawn_label: Label = null   # 소환 알림 슬라이드 라벨
var _spawn_tween: Tween = null
var _boss_hp: int = 0
var _boss_max: int = 0
var _cur_speed: int = 1   # 게임 속도 배수 (1/2/3) — Engine.time_scale
var _speed_btn: Button = null


func _ready() -> void:
	anchor_left = 0.0
	anchor_top = Layout.TOP_MARGIN
	anchor_right = 1.0
	anchor_bottom = Layout.TOP_MARGIN + Layout.BATTLE_RATIO
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP   # 터치 드래그 (전투 필드 스와이프)
	clip_contents = true   # 전투 영역 안만 표시
	_bg_tex = load(BG_PATH)
	EventBus.base_hp_changed.connect(_on_base_hp_changed)
	EventBus.soul_changed.connect(_on_soul_changed)
	EventBus.game_initialized.connect(_on_game_initialized)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.boss_hp_changed.connect(_on_boss_hp_changed)
	EventBus.unit_spawned.connect(_on_unit_spawned)
	_build_speed_button()
	_build_wave_banner()


func _on_game_initialized(state: Dictionary) -> void:
	_soul = int(state.get("soul", 0))
	_soul_max = int(state.get("soul_max", _soul_max))
	_level = int(state.get("lord_level", 1))
	_wave_num = int(state.get("wave", 0))
	queue_redraw()


## 터치 드래그 — 전투 필드 스와이프 (본진~적진). camera_x 갱신.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		Layout.set_camera_x(Layout.camera_x() - event.relative.x)
		queue_redraw()


## 카메라 변화 감지(미니맵 터치 등 외부 갱신) → 배경 redraw.
## _gui_input(직접 스와이프) 외에 MinimapView 터치로 camera_x 가 바뀔 때 배경이 안 따라가는 버그 방지.
var _last_cam_x := 0.0
func _process(_delta: float) -> void:
	var c := Layout.camera_x()
	if not is_equal_approx(c, _last_cam_x):
		_last_cam_x = c
		queue_redraw()
	# 배경 미세 fade(10초 주기) — 매 프레임 위상 갱신 + redraw.
	_bg_phase += _delta / 10.0
	queue_redraw()


## 게임 속도 토글 버튼 (×1/×2/×3) — 보스 게이지 아래 우측. Engine.time_scale 로 전투+슬롯 전체 제어.
func _build_speed_button() -> void:
	var btn := Button.new()
	btn.text = "SPD ×1"
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.anchor_top = 0.0
	btn.anchor_bottom = 0.0
	btn.offset_left = -220.0
	btn.offset_right = -16.0
	btn.offset_top = 72.0
	btn.offset_bottom = 124.0
	btn.add_theme_font_size_override("font_size", 26)
	btn.pressed.connect(_on_speed_pressed)
	add_child(btn)
	_speed_btn = btn


## 속도 버튼 누름 — ×1 → ×2 → ×3 → ×1 순환. Engine.time_scale 설정 (전투/슬롯/이펙트 전체).
func _on_speed_pressed() -> void:
	_cur_speed += 1
	if _cur_speed > 3:
		_cur_speed = 1
	Engine.time_scale = float(_cur_speed)
	if _speed_btn != null:
		_speed_btn.text = "SPD ×%d" % _cur_speed


## 게임 속도를 기본 ×1로 리셋 (런 재시작 시 — GAME OVER 전 속도가 유지되는 버그 방지).
func reset_speed() -> void:
	_cur_speed = 1
	Engine.time_scale = 1.0
	if _speed_btn != null:
		_speed_btn.text = "SPD ×1"


func _on_wave_started(wave_num: int) -> void:
	_wave_num = wave_num
	# 보스 WAVE(5배수)가 아니면 보스 게이지 숨김.
	if wave_num % 5 != 0:
		_boss_active = false
	_show_banner("WAVE %d" % wave_num, 2.0)
	queue_redraw()


func _on_enemy_spawned(enemy_id: StringName) -> void:
	if enemy_id == &"boss":
		_boss_active = true
		var data := UnitRegistry.get_enemy_unit(&"boss")
		if data != null:
			_boss_hp = data.max_hp
			_boss_max = data.max_hp
		_show_banner("BOSS 등장!!", 2.0)
		queue_redraw()


## 유닛 소환 알림 — "기사[LV2] x 3 소환!!" 좌→우 슬라이드 + fade.
func _on_unit_spawned(unit_id: StringName, count: int) -> void:
	var name_ko: String = _UNIT_NAME_KO.get(unit_id, String(unit_id))
	var text := "%s[LV%d] x %d 소환!!" % [name_ko, _level, count]
	_show_spawn_slide(text)


## 소환 알림 슬라이드 — 왼쪽 끝에서 시작, 중앙까지 fade in, 우끝으로 fade out.
## y 위치 = 전투 영역 중앙 - 50px (라인 위).
func _show_spawn_slide(text: String) -> void:
	if _spawn_label == null:
		_spawn_label = Label.new()
		_spawn_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_spawn_label.add_theme_font_size_override("font_size", 64)
		_spawn_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		_spawn_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_spawn_label.add_theme_constant_override("outline_size", 10)
		_spawn_label.z_index = 100
		_spawn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_spawn_label)
	_spawn_label.text = text
	_spawn_label.visible = true
	var cy: float = size.y * 0.5 - 150.0   # 전투 중앙 - 150px 위
	_spawn_label.position = Vector2(0.0, cy)
	_spawn_label.modulate.a = 0.0
	if _spawn_tween != null and _spawn_tween.is_valid():
		_spawn_tween.kill()
	_spawn_tween = create_tween()
	# fade in(0.3초) + 좌→중앙 이동(1.0초 병렬).
	_spawn_tween.tween_property(_spawn_label, "modulate:a", 1.0, 0.3)
	_spawn_tween.parallel().tween_property(_spawn_label, "position:x", size.x * 0.5, 1.0)
	# fade out(0.5초) + 중앙→우끝 이동(0.5초 병렬).
	_spawn_tween.tween_property(_spawn_label, "modulate:a", 0.0, 0.5)
	_spawn_tween.parallel().tween_property(_spawn_label, "position:x", size.x, 0.5)
	_spawn_tween.tween_callback(func() -> void: _spawn_label.visible = false)


## 웨이브/보스 경고 배너 빌드 — 전투 영역 중앙 큰 텍스트 + 페이드 인/아웃.
func _build_wave_banner() -> void:
	_wave_banner = Label.new()
	_wave_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wave_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wave_banner.add_theme_font_size_override("font_size", 120)
	_wave_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_wave_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_wave_banner.add_theme_constant_override("outline_size", 16)
	_wave_banner.modulate.a = 0.0
	_wave_banner.visible = false
	_wave_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_banner.z_index = 100            # 유닛(Node2D) 위로.
	add_child(_wave_banner)


## 배너 표시 요청 — 큐에 적재, 재생 중이면 완료 후 순차 재생(WAVE → BOSS 중복 대응).
func _show_banner(text: String, hold: float = 1.5) -> void:
	_banner_queue.append({"text": text, "hold": hold})
	if _banner_queue.size() == 1:
		_play_banner()


func _play_banner() -> void:
	if _wave_banner == null or _banner_queue.is_empty():
		return
	var b: Dictionary = _banner_queue[0]
	var t: String = b["text"]
	_wave_banner.text = t
	_wave_banner.visible = true
	_wave_banner.modulate.a = 0.0
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_wave_banner, "modulate:a", 1.0, 0.25)
	_banner_tween.tween_interval(float(b["hold"]))
	_banner_tween.tween_property(_wave_banner, "modulate:a", 0.0, 0.4)
	_banner_tween.tween_callback(_on_banner_done)


func _on_banner_done() -> void:
	if _wave_banner != null:
		_wave_banner.visible = false
	if not _banner_queue.is_empty():
		_banner_queue.pop_front()
	if not _banner_queue.is_empty():
		_play_banner()


func _on_enemy_killed(enemy_id: StringName, _exp: int) -> void:
	if enemy_id == &"boss":
		_boss_active = false
		queue_redraw()


func _on_boss_hp_changed(hp: int, max_hp: int) -> void:
	_boss_hp = hp
	_boss_max = max_hp
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var bh := size.y
	var ly := bh   # 바닥선(전투 영역 하단) — Layout.line_y(minimap_top)와 정렬
	# 전투 필드 스크롤 — camera_x offset (배경/라인/기지/포탈). 정보바/경험치는 고정.
	var cam := Layout.camera_x()
	var fw := Layout.field_w()
	# 전투 배경 (3배 폭, offset). 테스트 50% 투명.
	if _bg_tex != null:
		# 미세 fade: 10초 주기로 5% 어두워짐(0.95~1.0). _bg_phase 는 _process 에서 갱신.
		var fade := 0.975 + 0.025 * sin(_bg_phase * TAU)
		draw_texture_rect(_bg_tex, Rect2(-cam, 0.0, fw, bh), false, Color(1.0, 1.0, 1.0, fade))
	# 전투 라인 (field 전체)
	draw_line(Vector2(40.0 - cam, ly), Vector2(fw - 40.0 - cam, ly), Color(1.0, 1.0, 1.0, 0.85), 3.0)
	# 아군 기지 / 적 포탈 영역 (field 좌표 + offset)
	draw_rect(Rect2(Layout.ally_base_x() - cam - 40.0, ly - 60.0, 80.0, 120.0), Color(0.2, 0.9, 0.3, 1.0), false, 5.0)
	draw_rect(Rect2(Layout.ally_base_x() - cam - 36.0, ly - 56.0, 72.0, 112.0), Color(0.3, 0.8, 0.4, 0.35), true)
	draw_rect(Rect2(Layout.enemy_portal_x() - cam - 40.0, ly - 60.0, 80.0, 120.0), Color(1.0, 0.3, 0.3, 1.0), false, 5.0)
	draw_rect(Rect2(Layout.enemy_portal_x() - cam - 36.0, ly - 56.0, 72.0, 112.0), Color(0.9, 0.3, 0.3, 0.35), true)
	# 하단 분할선 (전투/슬롯 경계)
	draw_line(Vector2(0.0, bh), Vector2(w, bh), Color(0.8, 0.7, 1.0, 1.0), 6.0)
	# 라벨
	_draw_label("⚔ BATTLE", Vector2(20.0, 70.0), 30, Color(1.0, 0.95, 0.8, 1.0))
	_draw_label("ALLY", Vector2(15.0, ly + 80.0), 20, Color(0.5, 1.0, 0.6, 1.0))
	_draw_label("ENEMY", Vector2(w - 130.0, ly + 80.0), 20, Color(1.0, 0.5, 0.5, 1.0))
	# ★ 상단 정보바 — 3분할 (체력 좌 / 웨이브 중앙 / 보스 우). 높이 64(2배). 200px 하강.
	var seg := w / 3.0
	var bar_h := 64.0
	var bar_y := 200.0   # 정보바 y 하강(Layout.line_y 정렬)
	# 체력 (좌)
	var hr := clampf(float(_ally_hp) / float(_ally_max), 0.0, 1.0) if _ally_max > 0 else 0.0
	draw_rect(Rect2(0.0, bar_y, seg, bar_h), Color(0.05, 0.08, 0.05, 0.95), true)
	draw_rect(Rect2(0.0, bar_y, seg * hr, bar_h), Color(0.3, 0.9, 0.4), true)
	draw_rect(Rect2(0.0, bar_y, seg, bar_h), Color(1.0, 1.0, 1.0, 0.6), false, 2.0)
	_draw_label("HP %d/%d" % [_ally_hp, _ally_max], Vector2(12.0, bar_y + 44.0), 30, Color(0.9, 1.0, 0.9, 1.0))
	# 웨이브 (중앙)
	_draw_label_center("WAVE %d" % _wave_num, seg, seg * 0.5, bar_y + 44.0, 34, Color(1.0, 1.0, 1.0, 1.0))
	# 보스 게이지 (우) — 보스 등장 시만.
	if _boss_active:
		var br := clampf(float(_boss_hp) / float(_boss_max), 0.0, 1.0) if _boss_max > 0 else 0.0
		draw_rect(Rect2(seg * 2.0, bar_y, seg, bar_h), Color(0.1, 0.05, 0.05, 0.95), true)
		draw_rect(Rect2(seg * 2.0, bar_y, seg * br, bar_h), Color(1.0, 0.3, 0.3), true)
		draw_rect(Rect2(seg * 2.0, bar_y, seg, bar_h), Color(1.0, 1.0, 1.0, 0.6), false, 2.0)
		_draw_label("BOSS %d/%d" % [_boss_hp, _boss_max], Vector2(seg * 2.0 + 12.0, bar_y + 44.0), 30, Color(1.0, 0.6, 0.6, 1.0))
	# 하단 경험치 게이지.
	_draw_exp_bar(20.0, bh - 48.0, w - 40.0)


func _draw_exp_bar(x: float, y: float, bar_w: float) -> void:
	var r := clampf(float(_soul) / float(_soul_max), 0.0, 1.0) if _soul_max > 0 else 0.0
	var h := 28.0
	draw_rect(Rect2(x, y, bar_w, h), Color(0.05, 0.05, 0.12, 0.95), true)
	draw_rect(Rect2(x, y, bar_w * r, h), Color(0.6, 0.4, 1.0), true)
	draw_rect(Rect2(x, y, bar_w, h), Color(1.0, 1.0, 1.0, 0.6), false, 2.0)
	_draw_label("LV %d" % _level, Vector2(x + 12.0, y + 21.0), 22, Color(1.0, 0.95, 1.0, 1.0))
	_draw_label("EXP %d/%d" % [_soul, _soul_max], Vector2(x + bar_w - 200.0, y + 21.0), 22, Color(1.0, 1.0, 1.0, 1.0))


func _on_base_hp_changed(ally_hp: int, ally_max: int, enemy_hp: int, enemy_max: int) -> void:
	_ally_hp = ally_hp
	_ally_max = ally_max
	_enemy_hp = enemy_hp
	_enemy_max = enemy_max
	queue_redraw()


func _on_soul_changed(value: int, maximum: int, lvl: int) -> void:
	_soul = value
	_soul_max = maximum
	_level = lvl
	queue_redraw()


## 텍스트 그리기 — 검은 외곽선 + 밝은 본문 (좌측 정렬).
func _draw_label(text: String, pos: Vector2, font_size: int, col: Color) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0.0, 0.0, 0.0, 0.85))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


## 텍스트 중앙 정렬 — seg 폭 내 center_x 기준.
func _draw_label_center(text: String, seg_start: float, center_offset: float, y: float, font_size: int, col: Color) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	var pos := Vector2(seg_start + center_offset - text_w * 0.5, y)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0.0, 0.0, 0.0, 0.85))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
