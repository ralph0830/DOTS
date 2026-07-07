@tool
extends EditorPlugin
## Unit Manager EditorPlugin.
## 에디터 하단 패널에 "유닛 관리" 탭을 추가.
## resources/units/{ally,enemy}/*.tres 의 모든 UnitData 를 한 화면에서 편집.

const PanelScene := preload("res://addons/unit_manager/unit_manager_panel.tscn")
var _panel: Control


func _enter_tree() -> void:
	# 하단 패널에 유닛 관리 UI 추가.
	_panel = PanelScene.instantiate()
	_panel.custom_minimum_size = Vector2(800, 300)
	add_control_to_bottom_panel(_panel, "유닛 관리")
	# 로드는 패널이 처음 표시될 때(_on_visibility_changed) 자동 수행.
	print("[UnitManager] 플러그인 활성화 — 하단 패널 추가됨")


func _exit_tree() -> void:
	# 하단 패널에서 제거.
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
