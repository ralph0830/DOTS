class_name SymbolView
extends Control
## 심볼 1개의 시각 표현.
## SymbolData 의 color/shape 로 프로시저럴 도형을 그린다(아트 없이도 동작).
## SymbolData.texture 가 있으면 자동으로 텍스처로 전환한다(★에셋 교체 포인트).
## 당첨 시 펄스/확대 연출을 위한 하이라이트 토글도 제공(Phase 3 이펙트가 사용).

@export var symbol_data: SymbolData :
	set(value):
		symbol_data = value
		_texture_dirty = true
		queue_redraw()

var _texture_dirty: bool = true
var _highlight: bool = false
var _highlight_t: float = 0.0
var _shape_drawers: Dictionary = {}   # Shape enum → draw Callable (match 분기 제거)


func _ready() -> void:
	resized.connect(queue_redraw)
	_build_shape_drawers()


## Shape enum → draw Callable 매핑 구축. 새 도형 추가 시 이 딕셔너리만 확장(open-structure).
func _build_shape_drawers() -> void:
	_shape_drawers = {
		SymbolData.Shape.CIRCLE: _draw_circle_shape,
		SymbolData.Shape.DIAMOND: _draw_diamond_shape,
		SymbolData.Shape.SQUARE: _draw_square_shape,
		SymbolData.Shape.TRIANGLE: _draw_triangle_shape,
		SymbolData.Shape.STAR: _draw_star_shape,
		SymbolData.Shape.HEX: _draw_hex_shape,
		SymbolData.Shape.KNIGHT: _draw_knight,
		SymbolData.Shape.ARCHER: _draw_archer,
		SymbolData.Shape.MAGE: _draw_mage,
		SymbolData.Shape.SKULL: _draw_skull,
	}


func _process(delta: float) -> void:
	# 하이라이트 중일 때 펄스 애니메이션(Phase 3에서 SymbolEffects 로 대체 가능)
	if _highlight:
		_highlight_t += delta
		queue_redraw()


## 비활성 셀 회색 처리 (비활성 행/릴). modulate 로 어둡게 — 빈칸이 아니라 회색 셀로 표시.
func set_dimmed(dimmed: bool) -> void:
	modulate = Color(0.30, 0.30, 0.30, 0.75) if dimmed else Color.WHITE


## 당첨 하이라이트 on/off.
func set_highlight(enabled: bool) -> void:
	_highlight = enabled
	if not enabled:
		_highlight_t = 0.0
	queue_redraw()


func _draw() -> void:
	if symbol_data == null:
		return
	# 텍스처가 있으면 _draw 를 쓰지 않고 TextureRect 자식으로 위임(별도 처리)
	if symbol_data.texture != null:
		_draw_texture()
		return
	_draw_shape()


## 프로시저럴 도형(플레이스홀더). 중앙에 맞춰 그린다.
func _draw_shape() -> void:
	var radius: float = minf(size.x, size.y) * 0.42
	var center: Vector2 = size * 0.5
	var col: Color = symbol_data.color
	# 하이라이트 중이면 밝기 펄스 + 테두리 번쩍
	if _highlight:
		var pulse := 0.5 + 0.5 * cos(_highlight_t * 8.0)   # cos → t=0 최대(릴 멈춤과 동시 밝게 시작)
		col = col.lerp(Color.WHITE, pulse * 0.5)
		radius *= 1.0 + pulse * 0.08
		# 테두리 번쩍 (neon_color → 흰색 펄스) — 매칭 시 심볼 카드 강조. 색상은 심볼별 neon_color.
		var border_col := symbol_data.neon_color.lerp(Color.WHITE, pulse)
		draw_rect(Rect2(Vector2.ZERO, size), border_col, false, 4.0 + pulse * 4.0)

	# 테두리(깊이감)
	draw_circle_outline_solid(center, radius, col)
	# Shape enum → draw Callable (match 분기 없음). 새 도형은 _build_shape_drawers 확장.
	var drawer: Callable = _shape_drawers.get(symbol_data.shape, Callable())
	if drawer.is_valid():
		drawer.call(center, radius, col)
	else:
		draw_circle(center, radius, col)   # 알 수 없는 도형 폴백


# --- 기본 도형 draw 래퍼 (_shape_drawers 매핑용) ---
func _draw_circle_shape(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r, col)


func _draw_diamond_shape(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(_polygon_points(c, r, 4, PI / 4.0), col)


func _draw_square_shape(c: Vector2, r: float, col: Color) -> void:
	var s := r * 0.9
	draw_rect(Rect2(c - Vector2(s, s), Vector2(s * 2.0, s * 2.0)), col)


func _draw_triangle_shape(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(_polygon_points(c, r, 3, -PI / 2.0), col)


func _draw_star_shape(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(_star_points(c, r, r * 0.45, 5), col)


func _draw_hex_shape(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(_polygon_points(c, r, 6, 0.0), col)


## 텍스처 모드: 전체 영역에 텍스처 + 당첨 시 점멸 tint + 테두리 네온(symbol_data.neon_color).
func _draw_texture() -> void:
	var tint := Color.WHITE
	if _highlight:
		var pulse := 0.5 + 0.5 * cos(_highlight_t * 8.0)   # cos → 시작 최대
		tint = Color.WHITE.lerp(symbol_data.color, pulse * 0.5)
		var neon := symbol_data.neon_color.lerp(Color.WHITE, pulse)
		draw_rect(Rect2(Vector2.ZERO, size), neon, false, 4.0 + pulse * 4.0)
	draw_texture_rect(symbol_data.texture, Rect2(Vector2.ZERO, size), false, tint)


# --- Phase 8: 유닛 4종 프로시저럴 도형 ---
# 기사=방패(파랑), 궁수=활+화살(초록), 마법사=마법진(보라), 해골=해골(회색).
# 색상은 SymbolData.color 로 받아 도형 자체는 색+모양으로 구분.

## 기사: 방패 모양 (위 뾰족, 아래 둥근 전형적인 방패 실루엣).
func _draw_knight(center: Vector2, r: float, col: Color) -> void:
	var top := center + Vector2(0.0, -r)
	var bot_l := center + Vector2(-r * 0.75, r * 0.3)
	var bot_r := center + Vector2(r * 0.75, r * 0.3)
	var bot_c := center + Vector2(0.0, r)
	var mid_l := center + Vector2(-r * 0.75, -r * 0.2)
	var mid_r := center + Vector2(r * 0.75, -r * 0.2)
	var pts := PackedVector2Array([top, mid_r, bot_r, bot_c, bot_l, mid_l])
	draw_colored_polygon(pts, col)
	# 방패 내부 십자 문양 (은색 테두리 느낌)
	var inner := col.lightened(0.4)
	draw_line(top, bot_c, inner, r * 0.12)
	draw_line(center + Vector2(-r * 0.4, -r * 0.1), center + Vector2(r * 0.4, -r * 0.1), inner, r * 0.1)


## 궁수: 활 + 화살 (원호 + 수직 화살).
func _draw_archer(center: Vector2, r: float, col: Color) -> void:
	# 활 (오른쪽 원호)
	var arc_pts := PackedVector2Array()
	for i in range(13):
		var a := -PI * 0.45 + PI * 0.9 * float(i) / 12.0
		arc_pts.append(center + Vector2(cos(a) * r * 0.55, sin(a) * r) - Vector2(r * 0.15, 0.0))
	# 활은 선으로 (두껍게)
	for i in range(arc_pts.size() - 1):
		draw_line(arc_pts[i], arc_pts[i + 1], col, r * 0.15)
	# 활시위 (수직선)
	draw_line(center + Vector2(-r * 0.45, -r * 0.7), center + Vector2(-r * 0.45, r * 0.7), col.lightened(0.3), r * 0.08)
	# 화살 (수직, 위→아래)
	var arrow_col := col.lightened(0.5)
	draw_line(center + Vector2(r * 0.1, -r * 0.7), center + Vector2(r * 0.1, r * 0.7), arrow_col, r * 0.12)
	# 화살촉 (아래 삼각)
	var tip := center + Vector2(r * 0.1, r * 0.85)
	draw_colored_polygon(PackedVector2Array([
		tip, tip + Vector2(-r * 0.2, -r * 0.15), tip + Vector2(r * 0.2, -r * 0.15)
	]), arrow_col)
	# 화살 깃털 (위)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(r * 0.1, -r * 0.7),
		center + Vector2(r * 0.1, -r * 0.5),
		center + Vector2(-r * 0.05, -r * 0.6)
	]), arrow_col)


## 마법사: 마법진 (이중 원 + 별 + 룬).
func _draw_mage(center: Vector2, r: float, col: Color) -> void:
	# 외곽 원 (두께감)
	draw_arc(center, r * 0.9, 0.0, TAU, 48, col, r * 0.12)
	# 내곽 원 (얇게)
	draw_arc(center, r * 0.65, 0.0, TAU, 32, col.lightened(0.3), r * 0.06)
	# 중앙 별 (5점)
	draw_colored_polygon(_star_points(center, r * 0.45, r * 0.2, 5), col.lightened(0.4))
	# 4방향 룬 점
	for i in range(4):
		var a := PI * 0.25 + PI * 0.5 * float(i)
		var p := center + Vector2(cos(a), sin(a)) * r * 0.78
		draw_circle(p, r * 0.07, col.lightened(0.5))


## 해골: 둥근 머리 + 눈구멍 + 십자 아래턱.
func _draw_skull(center: Vector2, r: float, col: Color) -> void:
	# 머리 (둥근 윗부분)
	var head_pts := PackedVector2Array()
	for i in range(16):
		var a := -PI + PI * float(i) / 15.0   # 위쪽 반원
		head_pts.append(center + Vector2(cos(a) * r * 0.8, sin(a) * r * 0.8) + Vector2(0.0, -r * 0.05))
	# 아래쪽은 평평하게
	head_pts.append(center + Vector2(r * 0.8, r * 0.2))
	head_pts.append(center + Vector2(-r * 0.8, r * 0.2))
	draw_colored_polygon(head_pts, col)
	# 눈구멍 (검은 원 2개)
	var eye_offset := r * 0.3
	var eye_y := center.y - r * 0.15
	draw_circle(center + Vector2(-eye_offset, eye_y), r * 0.18, Color(0.05, 0.05, 0.05))
	draw_circle(center + Vector2(eye_offset, eye_y), r * 0.18, Color(0.05, 0.05, 0.05))
	# 코 (작은 검은 삼각)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, r * 0.05),
		center + Vector2(-r * 0.08, r * 0.2),
		center + Vector2(r * 0.08, r * 0.2),
	]), Color(0.05, 0.05, 0.05))
	# 아래턱 이빨 (3개 검은 선)
	var teeth_y := r * 0.2
	for i in range(-1, 2):
		var tx := center.x + float(i) * r * 0.25
		draw_line(Vector2(tx, teeth_y), Vector2(tx, r * 0.55), Color(0.05, 0.05, 0.05), r * 0.06)


## 도우미: n각형 정점(시작 각도 offset).
func _polygon_points(center: Vector2, radius: float, sides: int, angle_offset: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(sides):
		var a: float = angle_offset + TAU * float(i) / float(sides)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts


## 도우미: 별 정점(외곽/내곽 반지름, 5점).
func _star_points(center: Vector2, r_out: float, r_in: float, points: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var total := points * 2
	for i in range(total):
		var r: float = r_out if i % 2 == 0 else r_in
		var a: float = -PI / 2.0 + TAU * float(i) / float(total)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


## 도우미: 약한 외곽선으로 깊이감 부여.
func draw_circle_outline_solid(center: Vector2, radius: float, col: Color) -> void:
	var dark := col.darkened(0.45)
	draw_circle(center, radius * 1.12, dark)
