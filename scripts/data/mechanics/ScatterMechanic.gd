class_name ScatterMechanic
extends SymbolMechanic
## 스캐터 메카닉. 라인 평가에서 제외(위치 무관 그리드 평가에서 별도 처리 — ScatterEvaluationPass).

func participates_in_line() -> bool:
	return false


func can_be_line_target() -> bool:
	return false
