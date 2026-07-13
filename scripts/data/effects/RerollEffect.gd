class_name RerollEffect
extends ChoiceEffect
## 스핀 리롤러 (초반) — 슬롯 결과가 나쁠 때 무상 리롤 버튼 사용 횟수 +3.
## LordState.reroll_charges += 3. HUD 리롤 버튼이 이 값을 소모.

const REROLL_GRANT := 3
const REROLL_MAX := 9   # 누적 상한 (중복 선택 한계)


func apply(lord: Node) -> void:
	super.apply(lord)
	lord.reroll_charges = mini(lord.reroll_charges + REROLL_GRANT, REROLL_MAX)


func can_choose(lord: Node) -> bool:
	# 누적 상한 미만일 때만 선택 가능.
	if lord.has_method("get_state_summary"):
		return int(lord.get_state_summary().get("reroll_charges", 0)) < REROLL_MAX
	return true
