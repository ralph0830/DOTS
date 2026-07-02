class_name WildMechanic
extends SymbolMechanic
## 와일드 메카닉. 모든 심볼에 매치(대체)하며, 전부-Wild 라인에서는 자체 payout 의 타겟이 됨.

func is_substitutable() -> bool:
	return true


func matches(_target: SymbolData, _self_data: SymbolData) -> bool:
	return true   # 어떤 타겟이든 매치(대체)
