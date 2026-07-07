class_name BonusMechanic
extends SymbolMechanic
## 보너스 메카닉. 라인 평가에서 제외. 잭팟 트리거 심볼(Phase 4 JackpotPass 에서 평가).

func participates_in_line() -> bool:
	return false


func can_be_line_target() -> bool:
	return false


## 보너스 태그 — SymbolData.is_bonus()가 타입 체크 대신 조회.
func get_tags() -> PackedStringArray:
	return PackedStringArray([&"bonus"])
