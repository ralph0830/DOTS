extends Node
## GameManager (autoload 싱글톤)
## 게임 전역 상태와 라이프사이클을 관리한다. 어디서나 GameManager로 접근 가능.
## Phase 7: 디펜스 게임 런(run) 상태 추가 (WAVE, 적 처치, 게임오버).

# --- 시그널: 상태 변화를 외부에 알림 ---
signal game_started
signal score_changed(new_score: int)
signal pause_changed(is_paused: bool)

# --- 게임 전역 상태 ---
var score: int = 0          # 현재 점수
var is_game_running: bool = false  # 게임 진행 여부

# --- Phase 7: 디펜스 런(run) 상태 ---
var current_wave: int = 0           # 현재 WAVE 번호
var enemies_killed_total: int = 0   # 총 적 처치 수
var is_defense_active: bool = false # 디펜스 진행 중 여부


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.game_over.connect(_on_game_over)


## 게임 시작 처리. 메인 씬의 _ready()에서 호출한다.
func start_game() -> void:
	score = 0
	is_game_running = true
	current_wave = 0
	enemies_killed_total = 0
	is_defense_active = true
	score_changed.emit(score)
	game_started.emit()
	print("[GameManager] 디펜스 런 시작.")


## 점수 증가 헬퍼. amount만큼 score를 더하고 시그널을 발생시킨다.
func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)


## Phase 7: 적 처치 처리.
## Phase 8-A: exp_reward 인자 추가 (SoulGauge용) — GameManager는 무시.
func _on_enemy_killed(_enemy_id: StringName, _exp_reward: int) -> void:
	enemies_killed_total += 1
	add_score(10)   # 적 처치 시 10점


## Phase 7: WAVE 시작 추적.
func _on_wave_started(wave_num: int) -> void:
	current_wave = wave_num


## Phase 7: 게임오버 처리 (승리/패배).
func _on_game_over(victory: bool) -> void:
	is_defense_active = false
	if victory:
		print("[GameManager] 승리! 최종 점수: %d, WAVE: %d" % [score, current_wave])
	else:
		print("[GameManager] 패배. 최종 점수: %d, WAVE: %d, 적 처치: %d" % [score, current_wave, enemies_killed_total])


## 일시정지 토글. get_tree().paused를 반전시키고 시그널로 알린다.
func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_changed.emit(get_tree().paused)


## 씬 전환 헬퍼. scene_path(res:// 경로)의 씬으로 교체한다.
func change_scene(scene_path: String) -> void:
	is_game_running = false
	is_defense_active = false
	get_tree().change_scene_to_file(scene_path)


## 안전한 종료. 저장 등 정리가 필요하면 이곳에 추가한다.
func quit_game() -> void:
	get_tree().quit()
