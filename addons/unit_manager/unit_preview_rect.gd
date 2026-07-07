@tool
extends Control
## 유닛 미리보기 도형 — 에디터(@tool)에서도 _draw() 가 호출되도록 별도 파일로 분리.
## unit_manager_panel.gd 의 inner class 였으나, inner class 에는 @tool annotation 을
## 붙일 수 없어(최상단 전용) 에디터에서 도형이 렌더링되지 않던 문제 해결.
## UnitData 의 shape / color / size 로 프로시저럴 도형을 그린다.

var color: Color = Color.WHITE
var shape: int = 0  # UnitData.Shape enum 값 (0=CIRCLE, 1=SQUARE, 2=TRIANGLE, 3=DIAMOND)


func _draw() -> void:
    # 도형이 너무 작으면 그리지 않음(0 나눗셈/깨짐 방지).
    if size.x < 2.0 or size.y < 2.0:
        return
    var r := minf(size.x, size.y) * 0.4
    var center := size * 0.5
    match shape:
        0: draw_circle(center, r, color)
        1: draw_rect(Rect2(center - Vector2(r, r), Vector2(r * 2, r * 2)), color)
        2: draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, r), center + Vector2(-r, r)]), color)
        3: draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0)]), color)
        _: draw_circle(center, r, color)
    draw_arc(center, r, 0.0, TAU, 24, color.darkened(0.3), 2.0)
