class_name ReelView
extends Control
## 단일 릴 시각. 심볼 풀을 세로로 무한 스크롤하고 감속 tween 으로 결과에 착지.
## 사용 흐름:
##   configure(strip) → start_spin() → stop_at(result_3) → reel_stopped 시그널
## 무한 스크롤 원리: offset 이 SYMBOL_SIZE 에 도달할 때마다 풀의 맨 위 심볼을
## 맨 아래로 옮기고 새 랜덤 심볼을 할당. clip_contents 로 표시 영역(3행)만 노출.
## 헤드리스에서도 동작하도록 _physics_process 기반(tween 도 physics 모드).

signal reel_stopped(reel_index: int)

const SYMBOL_SIZE := 180.0
const ROWS := 3
const POOL_SIZE := 4            # ROWS + 1(아래 버퍼). 표시 영역엔 pool[0..2]

enum _State { IDLE, SPIN, STOP }

@export var reel_index: int = 0
@export var spin_speed: float = 2400.0   # 스크롤 속도(px/sec)
@export var decel_time: float = 0.6      # 감속 시간(초)

var _pool: Array[SymbolView] = []
var _strip: Array[SymbolData] = []
var _offset: float = 0.0          # 현재 셀 내 오프셋(0 ~ SYMBOL_SIZE)
var _state: int = _State.IDLE
var _result: Array[SymbolData] = []
var _rng := RandomNumberGenerator.new()
var _tween: Tween


func _ready() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(SYMBOL_SIZE, SYMBOL_SIZE * float(ROWS))
	_build_pool()
	set_physics_process(false)


func _build_pool() -> void:
	for c in get_children():
		c.queue_free()
	_pool.clear()
	for i in range(POOL_SIZE):
		var sv: SymbolView = preload("res://scenes/slot/Symbol.tscn").instantiate()
		sv.size = Vector2(SYMBOL_SIZE, SYMBOL_SIZE)
		add_child(sv)
		_pool.append(sv)


## 릴 스트립 심볼 설정 + 초기 랜덤 표시.
func configure(strip: Array) -> void:
	_strip = strip
	if _strip.is_empty():
		return
	for sv in _pool:
		sv.symbol_data = _strip[_rng.randi() % _strip.size()]
	_layout(0.0)


## 스핀 시작.
func start_spin() -> void:
	_state = _State.SPIN
	_result.clear()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	set_physics_process(true)


## 결과(위→아래 ROWS 개)로 감속 정지.
## 결과를 풀의 pool[1..ROWS]에 미리 배치해두면, 감속 1칸 스크롤 중 결과가
## 위에서 자연스럽게 스크롤인하여 착지하고 _cycle_one 후 pool[0..ROWS-1]이
## 결과가 된다 — 정지 순간에 결과를 덮어쓰는 점프가 발생하지 않는다.
func stop_at(result: Array) -> void:
	_result = result
	_state = _State.STOP
	for i in range(min(ROWS, _result.size())):
		_pool[i + 1].symbol_data = _result[i]
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)   # 헤드리스 대응
	_tween.tween_method(_set_offset, _offset, SYMBOL_SIZE, decel_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_land)


func _physics_process(delta: float) -> void:
	if _state == _State.SPIN:
		_set_offset(_offset + spin_speed * delta)


## offset 설정. SYMBOL_SIZE 도달 시 풀을 한 칸 순환시키고 0부터 재시작(무한 스크롤).
func _set_offset(v: float) -> void:
	while v >= SYMBOL_SIZE:
		v -= SYMBOL_SIZE
		_cycle_one()
	_offset = v
	_layout(v)


## 풀의 맨 위 심볼을 맨 아래로 옮기고 새 랜덤 심볼을 할당.
func _cycle_one() -> void:
	var first: SymbolView = _pool.pop_front()
	_pool.append(first)
	if not _strip.is_empty():
		first.symbol_data = _strip[_rng.randi() % _strip.size()]


## 감속 완료. 결과는 stop_at 에서 pool 에 미리 배치했으므로 _cycle_one 후
## pool[0..ROWS-1]이 자동으로 결과가 된다(별도 덮어쓰기 없음 → 점프 없음).
func _land() -> void:
	_offset = 0.0
	_layout(0.0)
	_state = _State.IDLE
	set_physics_process(false)
	reel_stopped.emit(reel_index)


## 풀을 offset 기준으로 세로 배치. pool[i].y = i*SIZE - offset.
func _layout(offset: float) -> void:
	for i in range(_pool.size()):
		_pool[i].position = Vector2(0.0, float(i) * SYMBOL_SIZE - offset)


## 특정 행의 표시 심볼(pool[0..ROWS-1]) 하이라이트 토글(당첨 강조용).
func set_symbol_highlight(row: int, on: bool) -> void:
	if row >= 0 and row < ROWS:
		_pool[row].set_highlight(on)


## 모든 표시 심볼 하이라이트 해제.
func clear_highlights() -> void:
	for i in range(ROWS):
		_pool[i].set_highlight(false)
