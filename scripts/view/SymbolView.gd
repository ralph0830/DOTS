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


func _ready() -> void:
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	# 하이라이트 중일 때 펄스 애니메이션(Phase 3에서 SymbolEffects 로 대체 가능)
	if _highlight:
		_highlight_t += delta
		queue_redraw()


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
	# 하이라이트 중이면 밝기 펄스
	if _highlight:
		var pulse := 0.5 + 0.5 * sin(_highlight_t * 8.0)
		col = col.lerp(Color.WHITE, pulse * 0.5)
		radius *= 1.0 + pulse * 0.08

	# 테두리(깊이감)
	draw_circle_outline_solid(center, radius, col)

	match symbol_data.shape:
		SymbolData.Shape.CIRCLE:
			draw_circle(center, radius, col)
		SymbolData.Shape.DIAMOND:
			draw_colored_polygon(_polygon_points(center, radius, 4, PI / 4.0), col)
		SymbolData.Shape.SQUARE:
			var s := radius * 0.9
			draw_rect(Rect2(center - Vector2(s, s), Vector2(s * 2.0, s * 2.0)), col)
		SymbolData.Shape.TRIANGLE:
			draw_colored_polygon(_polygon_points(center, radius, 3, -PI / 2.0), col)
		SymbolData.Shape.STAR:
			draw_colored_polygon(_star_points(center, radius, radius * 0.45, 5), col)
		SymbolData.Shape.HEX:
			draw_colored_polygon(_polygon_points(center, radius, 6, 0.0), col)


## 텍스처 모드: 전체 영역에 텍스처를 그린다.
func _draw_texture() -> void:
	draw_texture_rect(symbol_data.texture, Rect2(Vector2.ZERO, size), false)


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
