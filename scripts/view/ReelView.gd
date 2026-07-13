class_name ReelView
extends Control
## 단일 릴 시각. 활성 행(_active_rows)만 무한 스크롤 스핀.
## 비활성 행은 회색 오버레이로 고정(스핀하지 않음 → 결과 null/팝업 문제 원천 차단).
## bet_level별 활성 행 수(3~5)에 맞춰 풀 크기를 동적 재구성.
##
## 사용 흐름: configure(strip) → set_active_rows(rows) → start_spin() → stop_at(result_활성수)

signal reel_stopped(reel_index: int)

var SYMBOL_SIZE := 180.0   # 셀 크기 — Layout.cell_size()로 런타임 갱신 (정사형)
const ROWS := 5
# 비활성 셀 회색 오버레이 색 — 불투명 진회형(배경 대비, 활성 셀과 명확 구분).
const INACTIVE_COLOR := Color(0.10, 0.10, 0.13, 0.95)
# 릴 비활성(x1 릴0/4) → blue grey + "x2" 표시(x2 단계에서 열릴 예정).
const BLUE_GREY := Color(0.30, 0.40, 0.50, 0.92)
# 행 비활성(x1/x2 행0/4) → red grey + "x3" 표시(x3 단계에서 열릴 예정).
const RED_GREY := Color(0.50, 0.30, 0.32, 0.92)

enum _State { IDLE, SPIN, STOP }

@export var reel_index: int = 0
@export var spin_speed: float = 2400.0   # 스크롤 속도(px/sec)
@export var decel_time: float = 0.6      # 감속 시간(초)

var _pool: Array[SymbolView] = []        # 활성 행 스핀 풀 (활성 행 수 + 1 버퍼)
var _overlays: Array[ColorRect] = []     # 5행 회색 오버레이 (비활성 행 고정 덮개)
var _overlay_labels: Array[Label] = []   # 오버레이별 라벨(x2/x3 예고)
var _strip: Array[SymbolData] = []
var _offset: float = 0.0
var _state: int = _State.IDLE
var _result: Array[SymbolData] = []
var _rng := RandomNumberGenerator.new()
var _tween: Tween
var _active_rows: Array = [0, 1, 2, 3, 4]
var _dimmed: bool = false   # 릴 전체 비활성 (오버레이 5행 전부)


func _ready() -> void:
	clip_contents = true
	SYMBOL_SIZE = Layout.cell_size()   # 런타임 셀 크기 적용 (정사형 — scale 불필요)
	custom_minimum_size = Vector2(SYMBOL_SIZE, SYMBOL_SIZE * float(ROWS))
	_build_overlays()
	_rebuild_pool()
	set_physics_process(false)


## 비활성 행 회색 오버레이 5행 생성 — 행 위치(i*SIZE) 고정, 항상 최상단. 라벨(x2/x3) 자식.
func _build_overlays() -> void:
	for i in range(ROWS):
		var rect := ColorRect.new()
		rect.color = INACTIVE_COLOR
		rect.size = Vector2(SYMBOL_SIZE, SYMBOL_SIZE)
		rect.position = Vector2(0.0, float(i) * SYMBOL_SIZE)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		_overlays.append(rect)
		var lbl := Label.new()
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 72)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 12)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.add_child(lbl)
		_overlay_labels.append(lbl)


## 활성 행 수에 맞춰 스핀 풀 재구성 (활성 행 수 + 1 감속 버퍼).
func _rebuild_pool() -> void:
	for sv in _pool:
		sv.queue_free()
	_pool.clear()
	var n := _active_rows.size() + 1   # 활성 행 + 1(감속 중 잠깐 보이는 버퍼)
	for i in range(n):
		var sv: SymbolView = preload("res://scenes/slot/Symbol.tscn").instantiate()
		sv.size = Vector2(SYMBOL_SIZE, SYMBOL_SIZE)
		add_child(sv)
		_pool.append(sv)
	# 오버레이를 풀 위로(z순서 맨 위) — 비활성 셀을 덮도록.
	for rect in _overlays:
		move_child(rect, -1)
	if not _strip.is_empty():
		for sv in _pool:
			sv.symbol_data = _strip[_rng.randi() % _strip.size()]
	_layout(0.0)


## 릴 스트립 심볼 설정.
func configure(strip: Array) -> void:
	_strip = strip
	_rebuild_pool()


## 스핀 시작.
func start_spin() -> void:
	_state = _State.SPIN
	_result.clear()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	set_physics_process(true)


## 결과(활성 행 수 개)로 즉시 정지.
## 결과를 pool[0..n-1]에 직접 배치 — cycle/감속 의존을 제거해 마지막 행이 늦게 나타나거나
## 교체 깜빡이는 버그(모든 bet_level)를 원천 차단. 감속은 _next_stop 순차 정지로 자연스럽게.
func stop_at(result: Array) -> void:
	_result = result
	_state = _State.STOP
	var n: int = min(_active_rows.size(), result.size())
	# 결과를 pool[0..n-1]에 직접 배치.
	for i in range(n):
		_pool[i].symbol_data = result[i]
	# 나머지 풀(버퍼)은 랜덤 심볼.
	for i in range(n, _pool.size()):
		if not _strip.is_empty():
			_pool[i].symbol_data = _strip[_rng.randi() % _strip.size()]
	_offset = 0.0
	_layout(0.0)
	# 감속 tween 종료 처리.
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_land()


func _physics_process(delta: float) -> void:
	if _state == _State.SPIN:
		_set_offset(_offset + spin_speed * delta)


## offset 설정. SYMBOL_SIZE 도달 시 풀을 한 칸 순환(무한 스크롤).
func _set_offset(v: float) -> void:
	while v >= SYMBOL_SIZE:
		v -= SYMBOL_SIZE
		_cycle_one()
	_offset = v
	_layout(v)


## 풀의 맨 위 심볼을 맨 아래로 옮기고 새 랜덤 심볼 할당.
func _cycle_one() -> void:
	var first: SymbolView = _pool.pop_front()
	_pool.append(first)
	if not _strip.is_empty():
		first.symbol_data = _strip[_rng.randi() % _strip.size()]


## 감속 완료. pool[0..n-1]이 자동으로 결과.
func _land() -> void:
	_offset = 0.0
	_layout(0.0)
	_state = _State.IDLE
	set_physics_process(false)
	reel_stopped.emit(reel_index)


## 풀을 활성 블록(시작행 ~ 시작행+활성수)에 배치. 비활성 행은 오버레이가 덮음.
func _layout(offset: float) -> void:
	if _active_rows.is_empty():
		return
	var start_row: int = _active_rows[0]
	var n := _active_rows.size()
	for j in range(_pool.size()):
		var row_pos: int = start_row + j
		_pool[j].position = Vector2(0.0, float(row_pos) * SYMBOL_SIZE - offset)
		# 활성 블록 내 행만 표시 (버퍼 행은 숨김).
		_pool[j].visible = (row_pos >= start_row and row_pos < start_row + n)
	# 비활성 행 회색 오버레이 — _dimmed(릴 전체) 또는 해당 행 비활성.
	# 행0/4 → red grey "x3"(x1/x2 비활성 행). x1 릴0/4 행1-3 → blue grey "x2"(릴 비활성).
	var bl := WalletManager.bet_level
	for i in range(_overlays.size()):
		var inactive := _dimmed or not _active_rows.has(i)
		_overlays[i].visible = inactive
		if i >= _overlay_labels.size():
			continue
		if not inactive:
			_overlay_labels[i].text = ""
			continue
		var col: Color = INACTIVE_COLOR
		var txt := ""
		if i == 0 or i == 4:
			col = RED_GREY
			txt = "x3"
		elif _dimmed and bl <= 1 and (i == 1 or i == 2 or i == 3):
			col = BLUE_GREY
			txt = "x2"
		_overlays[i].color = col
		_overlay_labels[i].text = txt


## 특정 행(전역 행 인덱스) 하이라이트 토글(당첨 강조). 활성 행 풀 인덱스로 변환.
func set_symbol_highlight(row: int, on: bool) -> void:
	var idx: int = _active_rows.find(row)
	if idx >= 0 and idx < _pool.size():
		_pool[idx].set_highlight(on)


## 모든 풀 심볼 하이라이트 해제.
func clear_highlights() -> void:
	for sv in _pool:
		sv.set_highlight(false)


## 활성 행 설정 — 풀 크기 재구성 + 레이아웃 갱신.
func set_active_rows(rows: Array) -> void:
	_active_rows = rows
	_rebuild_pool()


## 셀 크기 갱신 (vp/해상도 변화 시). pool/overlay/custom_minimum 모두 재적용.
func set_cell(size: float) -> void:
	if size <= 0.0:
		return
	SYMBOL_SIZE = size
	custom_minimum_size = Vector2(SYMBOL_SIZE, SYMBOL_SIZE * float(ROWS))
	for sv in _pool:
		sv.size = Vector2(SYMBOL_SIZE, SYMBOL_SIZE)
	for i in range(_overlays.size()):
		_overlays[i].size = Vector2(SYMBOL_SIZE, SYMBOL_SIZE)
		_overlays[i].position = Vector2(0.0, float(i) * SYMBOL_SIZE)
	_layout(_offset)


## 릴 전체 회색 처리 (비활성 릴). set_active_rows 와 독립.
func set_dimmed(dimmed: bool) -> void:
	_dimmed = dimmed
	_layout(_offset)
