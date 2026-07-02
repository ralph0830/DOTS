class_name BonusMechanic
extends SymbolMechanic
## 보너스 메카닉. 라인 평가에서 제외. 잭팟 트리거 심볼(Phase 4 JackpotPass 에서 평가).

func participates_in_line() -> bool:
	return false


func can_be_line_target() -> bool:
	return false
