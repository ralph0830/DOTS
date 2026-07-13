class_name JudgmentDayEffect
extends ChoiceEffect
## 심판의 날 (후반) — 5매칭(잭팟) 성공 시 필드 모든 적에게 현재 체력의 50% 고정 피해.
## LordState.judgment_day_enabled = true. SlotMachine._evaluate 가 5매칭 시 발동.

func apply(lord: Node) -> void:
	super.apply(lord)
	lord.judgment_day_enabled = true


func can_choose(lord: Node) -> bool:
	if lord.has_method("get_state_summary"):
		return not bool(lord.get_state_summary().get("judgment_day_enabled", false))
	return true
