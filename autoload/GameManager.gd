extends Node
## GameManager (autoload 싱글톤)
## 게임 전역 상태와 라이프사이클을 관리한다. 어디서나 GameManager로 접근 가능.

# --- 시그널: 상태 변화를 외부에 알림 ---
signal game_started
signal score_changed(new_score: int)
signal pause_changed(is_paused: bool)

# --- 게임 전역 상태 ---
var score: int = 0          # 현재 점수
var is_game_running: bool = false  # 게임 진행 여부


func _ready() -> void:
	# 일시정지 중에도 GameManager는 동작해야 하므로 항상 처리 모드로 설정
	process_mode = Node.PROCESS_MODE_ALWAYS


## 게임 시작 처리. 메인 씬의 _ready()에서 호출한다.
func start_game() -> void:
	score = 0
	is_game_running = true
	score_changed.emit(score)
	game_started.emit()
	print("[GameManager] 게임이 시작되었습니다.")


## 점수 증가 헬퍼. amount만큼 score를 더하고 시그널을 발생시킨다.
func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)


## 일시정지 토글. get_tree().paused를 반전시키고 시그널로 알린다.
func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_changed.emit(get_tree().paused)


## 씬 전환 헬퍼. scene_path(res:// 경로)의 씬으로 교체한다.
func change_scene(scene_path: String) -> void:
	is_game_running = false
	get_tree().change_scene_to_file(scene_path)


## 안전한 종료. 저장 등 정리가 필요하면 이곳에 추가한다.
func quit_game() -> void:
	get_tree().quit()
