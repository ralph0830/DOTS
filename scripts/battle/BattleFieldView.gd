class_name BattleFieldView
extends Control
## 상단 전투 영역 뷰 — Phase 7 임시 배경/라벨.
## 실제 유닛/적 렌더링은 BattleField(Node2D)가 담당. 여기선 영역 확보 + 시각적 분할선만.
## 레이아웃: 상단 1080×1056px (전체 1920의 55%).

const BATTLE_H := 1056.0   # 전투 영역 높이 (1920 × 0.55)
const LINE_Y := 528.0      # 전투 라인 중심 y (BATTLE_H / 2) — 유닛/적이 이 선 위에 배치됨

# 기지 HP 표시용 (draw 라벨). EventBus.base_hp_changed 로 갱신.
var _ally_hp: int = 100
var _ally_max: int = 100
var _enemy_hp: int = 100
var _enemy_max: int = 100
# DEBUG: 초기화 상태 화면 표시용. game_initialized 시그널로 갱신.
var _dbg_init_text: String = "WAITING INIT..."
var _dbg_init_color: Color = Color(1.0, 0.5, 0.2)
var _dbg_init_t: float = 0.0


func _ready() -> void:
	# 상단 전투 영역 전체 채우기
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = -864.0   # 하단 864px(슬롯 영역)만큼 위로 당김 → 상단 1056px만 차지
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.base_hp_changed.connect(_on_base_hp_changed)
	EventBus.game_initialized.connect(_on_game_initialized)


func _process(delta: float) -> void:
	# DEBUG: 초기화 전에는 펄스하며 대기 표시. 초기화 후엔 정지.
	if not _dbg_init_text.begins_with("INIT OK"):
		_dbg_init_t += delta
		queue_redraw()


## DEBUG: 초기화 완료 수신 — 상태를 화면에 녹색으로 표시.
func _on_game_initialized(state: Dictionary) -> void:
	var credit: int = int(state.get("credit", -1))
	var bet: int = int(state.get("bet", -1))
	var ally: int = int(state.get("ally_hp", -1))
	var enemy: int = int(state.get("enemy_hp", -1))
	var wave: int = int(state.get("wave", -1))
	var running: bool = bool(state.get("running", false))
	_dbg_init_text = "INIT OK | credit=%d bet=%d ally=%d enemy=%d wave=%d run=%s" \
		% [credit, bet, ally, enemy, wave, running]
	_dbg_init_color = Color(0.3, 1.0, 0.4)
	queue_redraw()


func _draw() -> void:
	# 전투 영역 배경 (밝게 조정 — 파타폰 톤이지만 가독성 우선)
	draw_rect(Rect2(0.0, 0.0, 1080.0, BATTLE_H), Color(0.18, 0.15, 0.25, 1.0), true)
	# 전투 라인 (중앙 가로선 — 유닛/적이 지나다니는 줄, 더 밝게)
	draw_line(Vector2(40.0, LINE_Y), Vector2(1040.0, LINE_Y), Color(0.5, 0.45, 0.7, 0.8), 3.0)
	# 아군 기지 영역 표시 (좌단 — 초록 채우기 사각형 80×120)
	draw_rect(Rect2(20.0, LINE_Y - 60.0, 80.0, 120.0), Color(0.15, 0.5, 0.2, 0.9), false, 4.0)
	draw_rect(Rect2(24.0, LINE_Y - 56.0, 72.0, 112.0), Color(0.2, 0.6, 0.3, 0.3), true)
	# 적 포탈 영역 표시 (우단 — 빨간 채우기 사각형 80×120)
	draw_rect(Rect2(980.0, LINE_Y - 60.0, 80.0, 120.0), Color(0.6, 0.15, 0.15, 0.9), false, 4.0)
	draw_rect(Rect2(984.0, LINE_Y - 56.0, 72.0, 112.0), Color(0.7, 0.2, 0.2, 0.3), true)
	# 하단 분할선 (전투/슬롯 경계 — 밝은 네온 선으로 명확히 표시)
	draw_line(Vector2(0.0, BATTLE_H), Vector2(1080.0, BATTLE_H), Color(0.7, 0.6, 1.0, 1.0), 5.0)
	# 임시 라벨 (좌상단 — 밝게)
	_draw_label("⚔ BATTLE FIELD", Vector2(20.0, 30.0), 36, Color(0.85, 0.8, 1.0, 0.9))
	# 아군/적 라벨
	_draw_label("ALLY BASE", Vector2(15.0, LINE_Y + 80.0), 22, Color(0.3, 0.8, 0.4, 0.8))
	_draw_label("ENEMY PORTAL", Vector2(920.0, LINE_Y + 80.0), 22, Color(0.9, 0.3, 0.3, 0.8))
	# 기지 HP 바 — 아군(좌단 상단), 적(우단 상단). HP 비율에 따라 폭 변동.
	_draw_hp_bar(120.0, LINE_Y - 70.0, 200.0, _ally_hp, _ally_max, Color(0.2, 0.8, 0.3))
	_draw_hp_bar(760.0, LINE_Y - 70.0, 200.0, _enemy_hp, _enemy_max, Color(0.9, 0.3, 0.3))
	# HP 숫자 라벨 (기지 위)
	_draw_label("HP %d/%d" % [_ally_hp, _ally_max], Vector2(120.0, LINE_Y - 110.0), 26, Color(0.3, 0.9, 0.4, 1.0))
	_draw_label("HP %d/%d" % [_enemy_hp, _enemy_max], Vector2(760.0, LINE_Y - 110.0), 26, Color(0.9, 0.4, 0.4, 1.0))
	# DEBUG: 초기화 상태 크게 표시 (전투 영역 하단, 분할선 바로 위).
	# 초기화 전: 주황 펄스 "WAITING INIT...", 초기화 후: 녹색 "INIT OK | ..."
	var col := _dbg_init_color
	if not _dbg_init_text.begins_with("INIT OK"):
		col = _dbg_init_color.lerp(Color.WHITE, 0.5 + 0.5 * sin(_dbg_init_t * 6.0))
	_draw_label(_dbg_init_text, Vector2(60.0, BATTLE_H - 70.0), 30, col)


## HP 바 그리기 (배경 + 비율 채우기).
func _draw_hp_bar(x: float, y: float, w: float, hp: int, mx: int, col: Color) -> void:
	var r := clampf(float(hp) / float(mx), 0.0, 1.0) if mx > 0 else 0.0
	# 배경 (어두운 회색)
	draw_rect(Rect2(x, y, w, 16.0), Color(0.1, 0.1, 0.15, 0.95), true)
	# 채우기 (색상 + 테두리)
	draw_rect(Rect2(x, y, w * r, 16.0), col, true)
	draw_rect(Rect2(x, y, w, 16.0), Color(1.0, 1.0, 1.0, 0.4), false, 2.0)


func _on_base_hp_changed(ally_hp: int, ally_max: int, enemy_hp: int, enemy_max: int) -> void:
	_ally_hp = ally_hp
	_ally_max = ally_max
	_enemy_hp = enemy_hp
	_enemy_max = enemy_max
	queue_redraw()   # HP 바 갱신


## 임시 텍스트 그리기 (Godot 4 draw_string 헬퍼).
func _draw_label(text: String, pos: Vector2, font_size: int, col: Color) -> void:
	var font := get_theme_default_font()
	if font != null:
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
