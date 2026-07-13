extends Node
## 비율 대응 캡처 — 9:20 비율 창(1080×2400 좌표계)에서 Layout 비례 배치 확인.
## Layout 이 vp.y 비례로 battle_h/slot_h/line_y 를 반환해 전투/슬롯이 비율 유지하는지 검증.
## 실행: godot --path <project> res://scenes/setup/RatioCapture.tscn

const CAPTURE_PATH := "C:/Project/DOTS/captures/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CAPTURE_PATH)
	# 창을 9:20 비율로 — aspect=expand 가 좌표계를 1080×2400 으로 세로 확장.
	get_window().set_size(Vector2i(486, 1080))
	await get_tree().create_timer(1.0).timeout
	var smv: Node = load("res://scenes/slot/SlotMachine.tscn").instantiate()
	add_child(smv)
	WalletManager.reset_credit(10000)
	await get_tree().create_timer(1.5).timeout
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(CAPTURE_PATH + "ratio_20x9.png")
	print("[ratio] vp=%s battle_h=%s slot_h=%s line_y=%s 저장 err=%d" \
		% [str(Layout.viewport()), Layout.battle_h(), Layout.slot_h(), Layout.line_y(), err])
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()
