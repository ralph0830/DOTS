extends Node
## GameConfig — SlotConfig 리소스(default_slot.tres)를 전역에서 접근 가능하게 로드.
## class_name SlotConfig 와 이름 충돌을 피해 autoload 노드명은 GameConfig 사용.

const CONFIG_PATH := "res://resources/config/default_slot.tres"

var config: SlotConfig


func _ready() -> void:
	var loaded := load(CONFIG_PATH)
	if loaded == null:
		push_error("[GameConfig] default_slot.tres 로드 실패. 리소스가 존재하는지 확인.")
		return
	config = loaded
	# DEBUG: 로드된 심볼 payout 확인 (모바일 .res 변환 시 손실 여부 진단).
	print("[GameConfig] config 로드: symbols=%d reels=%d paylines=%d" \
		% [config.symbols.size(), config.reels.size(), config.paylines.size()])
	for sym in config.symbols:
		print("[GameConfig]   %s: kind=%d payout[3,4,5]=[%d,%d,%d] unit_id=%s" \
			% [sym.id, sym.kind, sym.get_payout(3), sym.get_payout(4), sym.get_payout(5), sym.unit_id])
