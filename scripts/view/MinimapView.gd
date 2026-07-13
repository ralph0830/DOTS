class_name MinimapView
extends Control
## 전투 필드 미니맵 뷰 (전투-슬롯 사이 얇은 가로 영역).
## field_w(3배 폭) 전투 필드를 축소 표시 — 아군/적 유닛 점, 카메라 뷰 영역, 양 끝 기지.
## Control _draw 매 프레임 렌더링(_process → queue_redraw).
## 절대 좌표는 SlotMachineView._apply_area_rects 가 강제(EXPAND 대응, size = vp.x × minimap_h).

# --- 색상 ---
const COLOR_BG := Color(0.08, 0.08, 0.12, 0.95)     # 배경(어두운 반투명)
const COLOR_LINE := Color(0.4, 0.4, 0.45, 0.8)      # 전투 라인
const COLOR_ALLY := Color(0.3, 0.9, 0.4)            # 아군 점(초록)
const COLOR_ENEMY := Color(0.95, 0.3, 0.3)          # 적 점(빨강)
const COLOR_BOSS := Color(0.7, 0.3, 0.95)           # 보스 점(보라, 큼)
const COLOR_BASE_ALLY := Color(0.3, 0.6, 0.95)      # 아군 기지(청)
const COLOR_BASE_ENEMY := Color(0.95, 0.75, 0.2)    # 적 기지(황)
const COLOR_CAMERA := Color(1.0, 1.0, 1.0, 0.85)    # 카메라 뷰 테두리(흰)

# --- 크기 ---
const DOT_R := 6.0        # 일반 유닛 점 반경
const BOSS_R := 10.0      # 보스 점 반경
const BASE_W := 8.0       # 기지 막대 폭

var _battle: BattleField = null
var _wave_num: int = 0
var _ally_hp: int = 100
var _ally_max: int = 100
var _enemy_hp: int = 100
var _enemy_max: int = 100


func _ready() -> void:
	# ★ anchor 는 부모(SlotMachineView._build_layout)가 PRESET_TOP_LEFT 로 설정 +
	#   _apply_area_rects 가 절대 position/size 를 강제(EXPAND 대응).
	#   여기서 FULL_RECT(0,0,1,1) 설정하면 절대 size 와 충돌(anchors non-equal → size overridden 경고).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.base_hp_changed.connect(_on_base_hp_changed)
	call_deferred("_cache_battle")


## BattleField 참조 캐싱 (부모 트리 확정 후). UnitSpawner._get_battle_field 패턴.
func _cache_battle() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var smv: Node = tree.get_first_node_in_group(&"slot_machine_view") if tree.has_group(&"slot_machine_view") else null
	if smv != null and smv.has_node("BattleField"):
		_battle = smv.get_node("BattleField") as BattleField


func _process(_delta: float) -> void:
	# 유닛이 매 프레임 이동 → 미니맵 갱신.
	queue_redraw()


func _on_wave_started(wave_num: int) -> void:
	_wave_num = wave_num


func _on_base_hp_changed(ally_hp: int, ally_max: int, enemy_hp: int, enemy_max: int) -> void:
	_ally_hp = ally_hp
	_ally_max = ally_max
	_enemy_hp = enemy_hp
	_enemy_max = enemy_max


## field_x → 미니맵 x. field_w = vp.x × 3, size.x = vp.x → 비율 1/3.
func _map_x(field_x: float) -> float:
	var fw := Layout.field_w()
	if fw <= 0.0:
		return 0.0
	return (field_x / fw) * size.x


func _draw() -> void:
	var sz: Vector2 = size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var mid_y := sz.y * 0.5
	# 1. 배경
	draw_rect(Rect2(Vector2.ZERO, sz), COLOR_BG, true)
	# 2. 전투 라인 (중앙 가로선)
	draw_line(Vector2(0.0, mid_y), Vector2(sz.x, mid_y), COLOR_LINE, 2.0)
	# 3. 기지 — 좌단(아군)/우단(적) 세로 막대, HP 비율만큼 위로 채움.
	var ally_ratio := float(_ally_hp) / float(_ally_max) if _ally_max > 0 else 0.0
	var enemy_ratio := float(_enemy_hp) / float(_enemy_max) if _enemy_max > 0 else 0.0
	var bar_h_ally := sz.y * ally_ratio
	var bar_h_enemy := sz.y * enemy_ratio
	draw_rect(Rect2(0.0, mid_y - bar_h_ally * 0.5, BASE_W, bar_h_ally), COLOR_BASE_ALLY, true)
	draw_rect(Rect2(sz.x - BASE_W, mid_y - bar_h_enemy * 0.5, BASE_W, bar_h_enemy), COLOR_BASE_ENEMY, true)
	# 4. 유닛 점 — BattleField 순회.
	if _battle != null:
		for child in _battle.get_children():
			if not (child is Unit):
				continue
			var u: Unit = child
			if not u._alive:
				continue
			var mx := _map_x(u.position.x)
			var is_boss: bool = u.data != null and u.data.unit_id == &"boss"
			var col: Color = COLOR_BOSS if is_boss else (COLOR_ENEMY if u.is_enemy else COLOR_ALLY)
			var r := BOSS_R if is_boss else DOT_R
			draw_circle(Vector2(mx, mid_y), r, col)
	# 5. 카메라 뷰 사각형 — 현재 화면 영역(테두리만).
	var cam_x := _map_x(Layout.camera_x())
	var cam_w := sz.x / Layout.FIELD_MULT
	draw_rect(Rect2(cam_x, 0.0, cam_w, sz.y), COLOR_CAMERA, false, 2.0)
