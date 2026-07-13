class_name WinCalculator
extends RefCounted
## 평가 오케스트레이터.
## EvaluationPass 체인을 순차 실행해 SpinResult 를 구성한다.
## 새 평가 규칙은 EvaluationPass 서브클래스를 만들어 체인에 끼워 넣으면 된다(데이터/코드 어디든).


## 기본 패스 시퀀스. 커스텀 패스를 evaluate() 의 passes 인자로 넘기면 대체/확장 가능.
static func default_passes() -> Array:
	return [LineEvaluationPass.new(), ScatterEvaluationPass.new(), JackpotEvaluationPass.new()]


## 그리드를 평가해 SpinResult 반환.
## active_reels: bet_level별 활성 릴 인덱스. passes 생략 시 default_passes() 사용.
static func evaluate(
		grid: Array,
		paylines: Array,
		paytable: Paytable,
		bet: int,
		free_multiplier: float,
		payline_count: int,
		active_reels: Array = [0, 1, 2, 3, 4],
		passes: Array = []
	) -> SpinResult:
		if passes.is_empty():
			passes = default_passes()

		var result := SpinResult.new()
		result.grid = grid

		# 평가 컨텍스트: 각 패스가 공유로 사용하는 입력 묶음.
		var ctx: Dictionary = {
			"grid": grid,
			"paylines": paylines,
			"paytable": paytable,
			"bet": bet,
			"line_bet": (float(bet) / float(payline_count)) if payline_count > 0 else 0.0,
			"free_multiplier": free_multiplier,
			"payline_count": payline_count,
			"active_reels": active_reels,
		}

		for p in passes:
			p.process(result, ctx)

		return result
