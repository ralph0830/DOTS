extends Node
## GameConfig — SlotConfig 리소스(default_slot.tres)를 전역에서 접근 가능하게 로드.
## class_name SlotConfig 와 이름 충돌을 피해 autoload 노드명은 GameConfig 사용.

const CONFIG_PATH := "res://resources/config/default_slot.tres"
# 빌드 식별 스탬프 — 모바일 lazy-load 방지용 preload (class_name 직접 참조 위험).
const _BuildStamp_ := preload("res://scripts/build_stamp.gd")

var config: SlotConfig


func _ready() -> void:
	# [BUILD] 스탬프 출력 — adb logcat 으로 "이 APK가 언제 빌드됐나" 확인 (stale APK 진단).
	print("[BUILD] APK 빌드 시각: %s" % _BuildStamp_.BUILD_TIME)
	var loaded := load(CONFIG_PATH)
	if loaded == null:
		push_error("[GameConfig] default_slot.tres 로드 실패. 리소스가 존재하는지 확인.")
		return
	config = loaded
