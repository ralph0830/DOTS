class_name DamageNumberLayer
extends Node2D
## 전투 데미지 숫자 이펙트. BattleField 자식(Node2D 좌표계 = Unit 과 동일).
## EventBus.damage_dealt 를 구독 — 맞은 유닛 위치에 데미지 숫자를 1초간 상승+페이드아웃.
## 적이 맞으면 노랑, 아군이 맞으면 빨강(위험 표시).
## Label 풀(재사용) — 모바일 성능. FloatingText 패턴 차용 + is_instance_valid 보완.

const POOL_SIZE: int = 12                 # 동시 데미지 숫자 풀 크기
const RISE_DISTANCE: float = 80.0         # 위로 상승할 거리(px)
const LIFETIME: float = 1.0               # 표시 지속 시간(초) — 1초 후 사라짐
const FONT_SIZE: int = 36
const COLOR_ENEMY_HIT := Color(1.0, 0.9, 0.2)    # 적이 맞음(내가 입힘) — 노랑
const COLOR_ALLY_HIT := Color(1.0, 0.3, 0.3)     # 아군이 맞음(위험) — 빨강
const Y_OFFSET: float = -40.0             # 유닛 위로 띄울 오프셋

var _pool: Array[Label] = []
var _active: Array[Label] = []


func _ready() -> void:
	z_index = 50   # Unit 위에 표시
	_build_pool()
	EventBus.damage_dealt.connect(_on_damage_dealt)


func _build_pool() -> void:
	for i in range(POOL_SIZE):
		var label := Label.new()
		label.name = "DamageNumber_%d" % i
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.visible = false
		add_child(label)
		_pool.append(label)


## 데미지 숫자 표시 요청 수신.
func _on_damage_dealt(pos: Vector2, amount: int, is_target_enemy: bool) -> void:
	if amount <= 0:
		return
	var label := _acquire()
	if label == null:
		return
	var col := COLOR_ENEMY_HIT if is_target_enemy else COLOR_ALLY_HIT
	_show(label, pos, amount, col)


## 풀에서 Label 획득. 부족하면 가장 오래된 것(활성 첫 요소)을 강제 회수해 재사용 —
## 데미지 숫자는 전투 피드백의 핵심이라 무시하지 않고 재활용.
func _acquire() -> Label:
	if _pool.is_empty():
		if _active.is_empty():
			return null
		# 가장 오래된 활성 Label 회수(tween kill + 풀 반환).
		var oldest: Label = _active[0]
		_release(oldest)
	if _pool.is_empty():
		return null
	var label: Label = _pool.pop_back()
	_active.append(label)
	return label


func _show(label: Label, pos: Vector2, amount: int, col: Color) -> void:
	label.add_theme_color_override("font_color", col)
	label.text = "%d" % amount
	label.position = pos + Vector2(0, Y_OFFSET)
	label.modulate.a = 1.0
	label.visible = true
	# 상승 + 페이드아웃 (1초). TWEEN_PROCESS_PHYSICS(헤드리스/pause 대응).
	var tw := create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var start_y := label.position.y
	tw.tween_property(label, "position:y", start_y - RISE_DISTANCE, LIFETIME)
	tw.parallel().tween_property(label, "modulate:a", 0.0, LIFETIME)
	tw.tween_callback(_on_tween_finished.bind(label))
	# tween 을 메타에 저장 → 강제 kill 시 안전 정리.
	label.set_meta("tween", tw)


func _on_tween_finished(label: Label) -> void:
	if is_instance_valid(label):
		_release(label)


func _release(label: Label) -> void:
	_kill_tween(label)
	label.visible = false
	label.text = ""
	label.modulate.a = 1.0
	var idx := _active.find(label)
	if idx >= 0:
		_active.remove_at(idx)
	if not _pool.has(label):
		_pool.append(label)


## tween 안전 정리 — FloatingText 결함(is_instance_valid 누락) 보완.
func _kill_tween(label: Label) -> void:
	if label.has_meta("tween"):
		var tw: Variant = label.get_meta("tween")
		if tw is Tween and is_instance_valid(tw as Tween):
			(tw as Tween).kill()
		label.remove_meta("tween")


## 런 리스타트 시 활성 데미지 숫자를 모두 회수 (BattleField.reset_run 에서 호출).
func clear() -> void:
	for label in _active.duplicate():
		_release(label)
	_active.clear()
