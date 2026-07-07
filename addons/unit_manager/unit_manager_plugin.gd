@tool
extends EditorPlugin
## Unit Manager EditorPlugin (Phase 8-E 디테일).
## 에디터 하단 패널에 "유닛 관리" 탭을 추가.
## resources/units/{ally,enemy}/*.tres 의 모든 UnitData 를 한 화면에서 편집.

const PanelScene := preload("res://addons/unit_manager/unit_manager_panel.tscn")
var _panel: Control


func _enter_tree() -> void:
	# 하단 패널에 유닛 관리 UI 추가.
	_panel = PanelScene.instantiate()
	add_control_to_bottom_panel(_panel, "유닛 관리")


func _exit_tree() -> void:
	# 하단 패널에서 제거.
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
