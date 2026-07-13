class_name RefundOnMissEffect
extends ChoiceEffect
## 재활용 주술 (초반) — 슬롯 꽝 시 다음 스핀에서 소모한 베팅의 50% 환급.
## LordState.refund_on_miss = true. UnitSpawner 꽝 분기에서 WalletManager.add_credit.

func apply(lord: Node) -> void:
	super.apply(lord)
	lord.refund_on_miss = true


func can_choose(lord: Node) -> bool:
	if lord.has_method("get_state_summary"):
		return not bool(lord.get_state_summary().get("refund_on_miss", false))
	return true
