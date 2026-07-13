class_name AllInEffect
extends ChoiceEffect
## 올 인 (후반) — 슬롯 베팅을 보유 CREDIT 100%로 설정. 매칭 성공 시 소환 물량 10배.
## LordState.all_in_enabled = true. SlotMachine.request_spin 이 베팅 금액 결정.

func apply(lord: Node) -> void:
	super.apply(lord)
	lord.all_in_enabled = true


func can_choose(lord: Node) -> bool:
	if lord.has_method("get_state_summary"):
		return not bool(lord.get_state_summary().get("all_in_enabled", false))
	return true
