extends Node2D
## 메인 씬 스크립트.
## 게임의 최상위 노드로, 씬 전환과 라이프사이클의 기준점이 된다.


func _ready() -> void:
	# 게임 시작 알림 (GameManager autoload가 이미 로드되어 있음)
	GameManager.start_game()


func _unhandled_input(event: InputEvent) -> void:
	# ESC: 일시정지 토글
	if event.is_action_pressed("ui_cancel"):
		GameManager.toggle_pause()
