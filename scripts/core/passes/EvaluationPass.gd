class_name EvaluationPass
extends RefCounted
## 평과 패스 플러그인 베이스.
## WinCalculator 가 이 패스들을 순차 실행하며 SpinResult 를 조립한다.
## 새 평가 규칙을 추가하려면 이 클래스를 상속해 process() 를 구현하면 끝.
##   예) WaysToWinPass, ClusterPass, CascadePass, JackpotPass ...
##
## 평가 컨텍스트(ctx Dictionary) 키:
##   grid, paylines, paytable, bet, line_bet, free_multiplier, payline_count

## 현재 결과(result)를 갱신한다. ctx 에서 필요한 값을 꺼내 쓴다.
func process(_result: SpinResult, _ctx: Dictionary) -> void:
	pass  # 서브클래스에서 구현
