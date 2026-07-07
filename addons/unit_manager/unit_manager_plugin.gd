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
	# ★ 핵심: 하단 패널을 펼치고 활성화 (안 하면 접힌 상태로 보이지 않음).
	make_bottom_panel_item_visible(_panel)
	# 패널이 트리에 추가된 후 로드.
	_panel.call_deferred("_load_units")
	print("[UnitManager] 플러그인 활성화 — 하단 패널 추가됨")


func _exit_tree() -> void:
	# 하단 패널에서 제거.
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
