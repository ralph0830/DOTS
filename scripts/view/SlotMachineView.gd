class_name SlotMachineView
extends Control
## 슬롯머신 뷰 오케스트레이터 + 이펙트 통합 지점.
## ReelView[5] + PaylineOverlay + 이펙트(BackgroundFX/WinEffects/FloatingText) 를 연결.
## 코어(SlotMachine)와는 EventBus 시그널로만 통신 — 코어 인스턴스를 직접 호출하지 않는다.

var REEL_W := 180.0   # Layout.reel_size() 로 런타임 갱신(거대화)
var ROW_H := 180.0
const MIN_SPIN_TIME := 0.5      # 최소 스핀 시간(감속 전)
const REEL_STOP_DELAY := 0.18   # 릴 간 정지 간격
# Phase 7: 모바일 세로형 상하 분할 — 전투 55% / 슬롯 45%.
# BATTLE_H/SLOT_H 은 Layout autoload (vp 비례) 사용 — Layout.battle_h()/slot_h().

var _core: SlotMachine                          # 생성/초기화 전용 — 런타임 호출은 EventBus 경유
var _is_idle: bool = true                       # 코어 IDLE 상태 추적(EventBus.state_changed 구독)
var _reel_area: Control
var _slot_bg: TextureRect
var _minimap: Control
var _reels: Array[ReelView] = []
var _paylines: PaylineOverlay
var _reel_area_origin: Vector2 = Vector2.ZERO   # 진동 후 복원용
var _grid: Array = []
var _next_stop: int = -1
var _stop_timer: float = 0.0
var _active_stop_order: Array = []   # 정지 순서(활성 릴만) — 비활성 릴은 스핀/정지 제외
# 자동스핀 상태: _auto_remaining = -1 무한, 0 끔, N 남은 횟수.
var _auto_remaining := 0
var _auto_start_credit := 0   # 자동스핀 시작 시점 크레딧 (손실 한도 계산용)
const AUTO_LOSS_RATIO := 0.5   # 시작 크레딧의 50% 손실 시 자동 정지
# Phase 7: 전투 필드 (상단 전투 영역에 배치)
var _battle_field: BattleField
var _battle_view: BattleFieldView   # 전투 뷰 (속도 리셋 등 재시작 처리용)


func _ready() -> void:
	# ★ export 빌드 중 main scene instantiate 시 게임 로직 완전 정지.
	#   --headless --export-debug 실행 시 DisplayServer.get_name() == "headless".
	#   WaveManager/Unit 들의 _physics_process 가 돌아 main loop 점유 → export 막힘.
	#   process_mode = DISABLED 로 자식 노드까지 전부 정지 (set_physics_process(false) 는
	#   자식에 전파 안 됨). export 는 scene 직렬화만 필요하므로 로직 멈춰도 무방.
	if DisplayServer.get_name() == &"headless":
		print("[SlotMachineView] headless 모드 — 게임 로직 정지 (export 중)")
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	add_to_group("slot_machine_view")
	_build_layout()
	_setup_core()
	_setup_reels()
	_setup_battle()   # Phase 7: 전투 시스템 (UnitSpawner/WaveManager) 초기화
	# 모든 싱글턴/매니저를 결정론적으로 초기화 (게임 시작 시 항상 동일 상태).
	_initialize_all()
	# EventBus 구독 — 코어 직접 참조 없이 시그널로 통신.
	EventBus.spin_requested.connect(_on_spin_requested)
	EventBus.state_changed.connect(_on_state_changed)
	EventBus.spin_complete.connect(_on_spin_complete)
	EventBus.highlight_wins.connect(_on_highlight)
	EventBus.big_win.connect(_on_big_win)
	EventBus.auto_spin_changed.connect(_on_auto_changed)
	EventBus.evaluation_completed.connect(_on_eval_auto)
	EventBus.game_over.connect(_on_game_over)   # game_over 시 AUTO 즉시 중단
	EventBus.bet_level_changed.connect(_on_bet_level_changed)


## 게임 시작 시 모든 상태를 초기값으로 리셋.
## 크레딧/잭팟/전투 필드/WAVE/자동스핀 — 저장값 무시, 항상 시작 상태에서 시작.
func _initialize_all() -> void:
	# 1. 지갑 — 시작 크레딧으로 리셋 (저장값 무시).
	var cfg := GameConfig.config
	WalletManager.initialize(cfg)
	WalletManager.reset_credit(int(cfg.starting_credit))
	# 2. 잭팟 — 시드값으로 리셋.
	JackpotSystem.initialize(cfg)
	JackpotSystem.reset_to_seeds()
	# 3. 전투 필드 — HP/유닛 리셋.
	if _battle_field != null:
		_battle_field.reset_run()
	# 4. WAVE — 1번부터 재개.
	var wave_mgr := get_node_or_null("WaveManager")
	if wave_mgr != null and wave_mgr.has_method("restart"):
		wave_mgr.restart()
	# 5. 자동스핀 — 끔.
	_auto_remaining = 0
	# 게임 속도 — 기본 ×1 (재시작 시 리셋). BattleFieldView 버튼 표시도 동기화.
	if _battle_view != null:
		_battle_view.reset_speed()
	else:
		Engine.time_scale = 1.0
	# 5.1 게임오버 플래그 해제 — 코어/스포너가 다시 스핀/소환 허용 (재시작 후 정상 동작).
	if _core != null:
		_core.reset_game_over()
	var spawner := get_node_or_null("UnitSpawner")
	if spawner != null and spawner.has_method("reset_game_over"):
		spawner.reset_game_over()
	# 6. 프리스핀/멀티플라이어 — 잔류 방지 (BonusManager.reset, 재시작 버그 수정).
	BonusManager.reset()
	# 7. 게임 매니저 런 상태.
	GameManager.start_game()
	# 8. 영혼 게이지 — 레벨 1, 게이지 0으로 리셋 (Phase 8-A).
	SoulGauge.initialize()
	# 9. 성주 상태 — 강화 레벨 전체 리셋 (Phase 8-B).
	LordState.reset()
	# 10. 유닛 레지스트리 — 아군/적 UnitData 재생성 (Phase 8-C).
	UnitRegistry.initialize()
	# 11. 유물 매니저 — 활성 유물 초기화 (Phase 8-E).
	ArtifactManager.initialize()
	# DEBUG: 초기화 상태를 화면 표시용 딕셔너리로 emit.
	var state := {
		"credit": WalletManager.credit,
		"bet": WalletManager.current_bet,
		"ally_hp": _battle_field.base_hp if _battle_field != null else -1,
		"enemy_hp": _battle_field.enemy_base_hp if _battle_field != null else -1,
		"wave": GameManager.current_wave,
		"running": GameManager.is_defense_active,
		"soul": SoulGauge.soul,
		"soul_max": SoulGauge.soul_max,
		"lord_level": SoulGauge.level,
	}
	print("[init] 게임 초기화 완료: credit=%d bet=%d ally=%d enemy=%d wave=%d soul=%d/%d lv%d" \
		% [state.credit, state.bet, state.ally_hp, state.enemy_hp, state.wave, state.soul, state.soul_max, state.lord_level])
	EventBus.game_initialized.emit(state)


func _build_layout() -> void:
	# 슬롯 영역 배경 (밝은 도트 — 하단 Layout.BATTLE_RATIO~1.0). BackgroundFX(전체 셰이더) 대체.
	# 전투 영역(상단 0~BATTLE_RATIO) 배경은 BattleFieldView 가 _draw 로 담당 → 전투/슬롯 배경 분리.
	_slot_bg = TextureRect.new()
	var slot_tex := load("res://assets/backgrounds/bg_slot_solid_512.png")
	if slot_tex != null:
		_slot_bg.texture = slot_tex
	# ★ 절대 position/size 사용(anchor 0) — anchor 비율이 부모 size(window 물리)와
	#   Layout._vp(EXPAND) 불일치 시 어긋나는 것을 원천 차단. _apply_area_rects 가 vp 변화마다 갱신.
	_slot_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_slot_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_slot_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_slot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot_bg)
	# Phase 7: 상단 전투 영역 (1080×1056px) — 배경 위, 릴 아래.
	_battle_view = BattleFieldView.new()
	add_child(_battle_view)
	# 미니맵 영역 (전투-슬롯 사이) — 독립 노드, 흰색 배경. 추후 전투 필드 축소 표시.
	_minimap = MinimapView.new()
	_minimap.name = "MinimapView"
	_minimap.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(_minimap)
	# Phase 7: 전투 필드 (Node2D) — 유닛/적이 실제로 배치되는 전투 좌표계.
	_battle_field = BattleField.new()
	_battle_field.name = "BattleField"
	add_child(_battle_field)
	# 릴 영역 — 절대 좌표(_apply_area_rects 로 vp 변화마다 slot_top/slot_h 강제).
	# anchor 비율 대신 절대 position/size → 부모 size 와 Layout._vp 불일치(EXPAND)에 면역.
	_reel_area = Control.new()
	_reel_area.name = "ReelArea"
	_reel_area.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_reel_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reel_area)
	# 페이라인 오버레이(릴 영역 자식 → 로컬 좌표)
	_paylines = PaylineOverlay.new()
	_paylines.reel_w = REEL_W
	_paylines.row_h = ROW_H
	_reel_area.add_child(_paylines)
	# 당첨 파티클(릴 영역 로컬 좌표 = winning_positions 변환 기준)
	var win_fx := WinEffects.new()
	_reel_area.add_child(win_fx)
	# 당첨 금액 플로팅 텍스트
	var floating := FloatingText.new()
	_reel_area.add_child(floating)
	# 잭팟 전체화면 연출
	var jackpot_fx := preload("res://scenes/slot/JackpotOverlay.tscn").instantiate()
	add_child(jackpot_fx)
	# HUD
	var hud := preload("res://scenes/slot/HUD.tscn").instantiate()
	add_child(hud)
	# Phase 8: 게임오버/승리 오버레이 (탭 시 리스타트)
	# ★ add_child 전에 부모가 직접 anchor 설정 — 자식의 _ready(deferred) 에만 의존하면
	#   부모 layout 확정 타이밍과 어긋나 overlay size 가 0 으로 남아 좌상단에 작게 표시됨.
	#   BackgroundFX 도 동일 패턴(add_child 전 set_anchors_preset) 으로 정상 동작 중.
	var game_over_overlay := GameOverOverlay.new()
	game_over_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(game_over_overlay)
	# Phase 8-B: 레벨업 3지선다 카드 UI (level_up_available 시 표시)
	var level_up_ui := LevelUpUI.new()
	level_up_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(level_up_ui)


func _setup_core() -> void:
	# 코어 인스턴스는 생성/초기화만 담당 — 이후 모든 통신은 EventBus.
	_core = SlotMachine.new()
	add_child(_core)
	_core.initialize(GameConfig.config)


func _setup_reels() -> void:
	var config := GameConfig.config
	for i in range(config.reel_count):
		var reel: ReelView = preload("res://scenes/slot/Reel.tscn").instantiate()
		reel.reel_index = i
		reel.configure(config.reels[i].symbols)
		reel.reel_stopped.connect(_on_reel_stopped)
		_reel_area.add_child(reel)
		_reels.append(reel)
	_layout_reels()
	# ReelView _ready(deferred) 후 활성 매트릭스 적용 — _pool 구축 전이면 visible 제어 안 됨.
	call_deferred("_on_bet_level_changed", WalletManager.bet_level)


## Phase 7: 전투 시스템(UnitSpawner + WaveManager) 초기화. 슬롯 결과 → 유닛 소환 연결.
func _setup_battle() -> void:
	var spawner := UnitSpawner.new()
	spawner.name = "UnitSpawner"
	add_child(spawner)
	var wave_mgr := WaveManager.new()
	wave_mgr.name = "WaveManager"
	add_child(wave_mgr)


func _layout_reels() -> void:
	var vp := Layout.viewport()
	REEL_W = Layout.reel_w()
	ROW_H = Layout.reel_h()
	# slot_bg/minimap/_reel_area 절대 좌표 강제 — anchor 비율 → 부모 size 불일치 회피 (빈 공간 원천 차단).
	_apply_area_rects()
	var total_w := REEL_W * float(_reels.size())
	var reel_grid_h := ROW_H * 5.0
	# 슬롯 영역 크기 (vp 기반) = ReelArea size 와 동일(_apply_area_rects 로 강제).
	var area_w := vp.x
	var area_h := Layout.slot_h()
	# 릴 그리드를 슬롯 영역 중앙 (ReelArea 로컬 좌표).
	var start_x := (area_w - total_w) * 0.5
	var start_y := (area_h - reel_grid_h) * 0.5
	_reel_area_origin = Vector2.ZERO   # 절대 좌표 기반 — 진동은 position offset 으로.
	for i in range(_reels.size()):
		_reels[i].set_cell(REEL_W)   # cell 갱신 (vp/해상도 변화 대응 — 빈 공간 방지)
		_reels[i].position = Vector2(start_x + float(i) * REEL_W, start_y)
	# PaylineOverlay 셀 크기 동기화.
	if _paylines != null:
		_paylines.reel_w = REEL_W
		_paylines.row_h = ROW_H


## vp 변화 대응 — slot_bg/minimap/_reel_area 를 Layout 절대 좌표로 강제.
## anchor 비율 대신 절대 position/size → 부모 size(window 물리)와 Layout._vp(EXPAND) 불일치에 면역.
func _apply_area_rects() -> void:
	var vp := Layout.viewport()
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var slot_top := Layout.slot_top()
	var slot_h := Layout.slot_h()
	if _reel_area != null:
		_reel_area.position = Vector2(0.0, slot_top)
		_reel_area.size = Vector2(vp.x, slot_h)
	if _slot_bg != null:
		_slot_bg.position = Vector2(0.0, slot_top)
		_slot_bg.size = Vector2(vp.x, slot_h)
	if _minimap != null:
		_minimap.position = Vector2(0.0, Layout.minimap_top())
		_minimap.size = Vector2(vp.x, Layout.minimap_h())


var _last_vp := Vector2.ZERO
## vp/해상도 변화 감지 → 릴 레이아웃 재적용(ReelView cell 갱신 — 빈 공간 방지).
func _process(_delta: float) -> void:
	var vp: Vector2 = Layout.viewport()
	if vp != _last_vp:
		_last_vp = vp
		_layout_reels()


# --- 스핀 흐름 ---

## 스핀 요청 수신(EventBus.spin_requested) — 뷰 책임: 이전 당첨 하이라이트 제거만.
## 실제 스핀 개시는 코어가 EventBus.spin_requested를 직접 구독해 수행한다.
func _on_spin_requested() -> void:
	for reel in _reels:   # 이전 당첨 하이라이트 제거
		reel.clear_highlights()


## bet_level 변경 수신 — 활성 매트릭스 갱신 (비활성 릴/행 회색 처리).
## 항상 5×5 표시 — 활성 셀만 정상 색, 비활성 셀은 회색(빈칸 아님).
func _on_bet_level_changed(level: int) -> void:
	var active_reels := WalletManager.active_reels_for(level)
	var active_rows := WalletManager.active_rows_for(level)
	for i in range(_reels.size()):
		var reel: ReelView = _reels[i]
		var is_active := active_reels.has(i)
		reel.visible = true   # 항상 5릴 표시 — 비활성 릴은 회색(set_dimmed).
		reel.set_dimmed(not is_active)   # 비활성 릴 전체 회색
		reel.set_active_rows(active_rows)   # 비활성 행 회색


## game_over 수신 — 자동스핀 즉시 중단.
## 게임오버 후에도 AUTO 가 살아있으면 코어 스핀 → 유닛 소환 루프가 돌아
## DEFEAT 연출 중에도 새 유닛이 계속 생산되므로 즉시 끊는다.
func _on_game_over(_victory: bool) -> void:
	if _auto_remaining != 0:
		_auto_remaining = 0
		EventBus.auto_spin_changed.emit(false, 0)   # HUD AUTO 버튼 리셋 동기화


## 코어 상태 전이 수신(EventBus.state_changed) — _is_idle 추적.
## _maybe_auto_spin 등이 코어 직접 참조 대신 이 플래그를 사용.
func _on_state_changed(_from: int, to: int) -> void:
	_is_idle = (to == SlotMachine.State.IDLE)


func _on_spin_complete(grid: Array) -> void:
	_grid = grid
	# 활성 릴만 스핀/정지 — 비활성 릴은 회색 정지 상태 유지(stop_at/reel_stopped 없음).
	var active_reels := WalletManager.active_reels_for(WalletManager.bet_level)
	_active_stop_order = active_reels.duplicate()
	for i in active_reels:
		_reels[i].start_spin()
	_next_stop = 0
	_stop_timer = MIN_SPIN_TIME


func _physics_process(_delta: float) -> void:
	# 순차 정지: 활성 릴만(_active_stop_order). 타이머 만료 시 다음 활성 릴 stop_at.
	if _next_stop < 0 or _next_stop >= _active_stop_order.size():
		return
	_stop_timer -= _delta
	if _stop_timer <= 0.0:
		_stop_reel(_active_stop_order[_next_stop])
		_next_stop += 1
		_stop_timer = REEL_STOP_DELAY


func _stop_reel(i: int) -> void:
	# 활성 행 결과만 추출 — ReelView 풀 크기(활성 행 수)와 일치. 비활성 행(null)은 제외.
	var active_rows := WalletManager.active_rows_for(WalletManager.bet_level)
	var result: Array[SymbolData] = []
	for row in active_rows:
		result.append(_grid[i][row])
	_reels[i].stop_at(result)


## 릴 정지 완료(ReelView 시그널) → 코어에 EventBus로 보고.
func _on_reel_stopped(reel_index: int) -> void:
	EventBus.reel_stopped.emit(reel_index)


# --- 이펙트 훅 ---

## 당첨 심볼 하이라이트(EventBus.highlight_wins).
func _on_highlight(result: SpinResult) -> void:
	for pos in result.winning_positions:
		if pos.x >= 0 and pos.x < _reels.size():
			_reels[pos.x].set_symbol_highlight(pos.y, true)


## 빅윈 시 릴 영역 진동(EventBus.big_win).
## Control 기반 UI 씬에서는 Camera2D 활성화가 좌표계를 흐트러뜨리므로
## 릴 영역 position 만 tween 으로 흔드는 인라인 방식을 사용한다.
func _on_big_win(amount: int) -> void:
	var amplitude := clampf(float(amount) / 50.0, 4.0, 18.0)
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	for i in range(5):
		var off := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amplitude
		tween.tween_property(_reel_area, "position", _reel_area_origin + off, 0.04)
	tween.tween_property(_reel_area, "position", _reel_area_origin, 0.1).set_trans(Tween.TRANS_QUAD)


# --- 자동스핀 / 프리스핀 연쇄 ---

## 자동스핀 토글 수신. remaining: -1=무한, 0=끔, N=남은 횟수.
## HUD 의 AUTO 버튼 순환 클릭으로 호출됨.
func _on_auto_changed(enabled: bool, remaining: int) -> void:
	_auto_remaining = remaining if enabled else 0
	if enabled and remaining != 0:
		_auto_start_credit = WalletManager.credit   # 손실 한도 기준점
		_maybe_auto_spin()


## 평가 완료 후 자동스핀 또는 프리스핀 잔여 시 다음 스핀 예약.
func _on_eval_auto(_r: SpinResult) -> void:
	var active := _auto_remaining != 0 or _free_spins_active()
	if not active:
		return
	await get_tree().create_timer(0.9).timeout   # 당첨 연출 관찰 시간
	# 자동스핀 횟수 차감 (프리스핀이 아닐 때만)
	if _auto_remaining > 0:
		_auto_remaining -= 1
		if _auto_remaining == 0:
			# 횟수 모두 소진 → 정지 (HUD 동기화)
			EventBus.auto_spin_changed.emit(false, 0)
			return
	_maybe_auto_spin()


## 조건(IDLE + 자금/손실한도/프리스핀)이 맞으면 다음 스핀 요청.
func _maybe_auto_spin() -> void:
	if not _is_idle:
		return
	# 프리스핀 중이면 횟수/자금 제약 없이 스핀.
	if _free_spins_active():
		EventBus.spin_requested.emit()
		return
	# 자동스핀 비활성 → 종료.
	if _auto_remaining == 0:
		return
	# 손실 한도 도달 여부 (시작 크레딧의 AUTO_LOSS_RATIO 이하로 하락).
	var loss_limit := int(float(_auto_start_credit) * (1.0 - AUTO_LOSS_RATIO))
	if WalletManager.credit <= loss_limit and _auto_start_credit > 0:
		_auto_remaining = 0
		EventBus.auto_spin_changed.emit(false, 0)
		return
	# 자금 부족 → 정지.
	if not WalletManager.can_bet():
		_auto_remaining = 0
		EventBus.auto_spin_changed.emit(false, 0)
		return
	EventBus.spin_requested.emit()


## 프리스핀이 진행 중(잔여 횟수 > 0)인지.
func _free_spins_active() -> bool:
	var bm := get_node_or_null("/root/BonusManager")
	return bm != null and bm.has_method("is_free_spin") and bm.is_free_spin()
