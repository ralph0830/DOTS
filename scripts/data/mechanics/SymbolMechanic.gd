class_name SymbolMechanic
extends Resource
## 심볼 메카닉 플러그인 베이스(평가 로직의 확장점).
## 라인 평가에 필요한 질문 4가지를 "심볼 스스로" 답하게 만든다.
##   - participates_in_line : 라인 매칭에 참여하는 심볼인가?(Scatter/Bonus=false)
##   - can_be_line_target   : 매칭의 '기준(타겟)'이 될 수 있는가?
##   - is_substitutable     : 다른 심볼을 '대체'하는가?(Wild=true)
##   - matches              : 주어진 타겟에 매치되는가?
## 새 메카닉(ExpandingWild, Multiplier, Sticky, BonusTrigger 등)은 이 클래스를 상속해
## 해당 메서드만 오버라이드하면 된다 — SpinEvaluator 코드 수정 불필요.
## SymbolData.mechanic 이 null 이면 kind 기반 기본 메카닉(for_kind)이 사용된다.


## 라인 평가에 참여하는 심볼인지 (Scatter/Bonus 계열은 false).
func participates_in_line() -> bool:
	return true


## 라인의 첫 심볼(매칭 타겟)이 될 수 있는지.
func can_be_line_target() -> bool:
	return true


## 다른 심볼을 대체하는가 (Wild 계열). 타겟 선택 우선순위에 영향.
func is_substitutable() -> bool:
	return false


## 주어진 타겟 심볼에 매치되는지. 기본: 자기 자신과 같은 ID.
func matches(_target: SymbolData, self_data: SymbolData) -> bool:
	return self_data.id == _target.id


## kind → 기본 메카닉 팩토리. SymbolData.mechanic 이 null 일 때 사용.
static func for_kind(kind: int) -> SymbolMechanic:
	match kind:
		SymbolData.Kind.NORMAL:
			return NormalMechanic.new()
		SymbolData.Kind.WILD:
			return WildMechanic.new()
		SymbolData.Kind.SCATTER:
			return ScatterMechanic.new()
		SymbolData.Kind.BONUS:
			return BonusMechanic.new()
	return NormalMechanic.new()
