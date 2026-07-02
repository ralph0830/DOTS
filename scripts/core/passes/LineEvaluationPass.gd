class_name LineEvaluationPass
extends EvaluationPass
## 라인 매칭 평가 패스.
## 모든 페이라인을 순회하며 왼쪽(릴 0)부터 연속 매칭을 평가한다.
## SpinEvaluator(순수 로직)를 호출하고, 당첨 금액에 라인 베팅·프리스핀 배수를 곱한다.

func process(result: SpinResult, ctx: Dictionary) -> void:
	var paylines: Array = ctx["paylines"]
	var grid: Array = ctx["grid"]
	var line_bet: float = ctx["line_bet"]
	var free_mult: float = ctx["free_multiplier"]

	for payline in paylines:
		var lw := SpinEvaluator.evaluate_line(grid, payline)
		if lw == null:
			continue
		lw.amount = int(float(lw.amount) * line_bet * free_mult)
		result.line_wins.append(lw)
		result.total_win += lw.amount
		for pos in lw.positions:
			result.winning_positions.append(pos)
