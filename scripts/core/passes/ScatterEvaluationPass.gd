class_name ScatterEvaluationPass
extends EvaluationPass
## 스캐터 평가 패스.
## 그리드 전체의 SCATTER 심볼 수를 세어 3개 이상이면 크레딧 보상과 프리스핀을 부여한다.

func process(result: SpinResult, ctx: Dictionary) -> void:
	var grid: Array = ctx["grid"]
	var paytable: Paytable = ctx["paytable"]
	var bet: int = ctx["bet"]
	var free_mult: float = ctx["free_multiplier"]

	result.scatter_count = _count_scatter(grid)
	if result.scatter_count < 3:
		return

	result.scatter_win = int(float(paytable.get_scatter_credit(result.scatter_count, bet)) * free_mult)
	result.total_win += result.scatter_win
	result.free_spins_awarded = paytable.get_free_spins_for_scatter(result.scatter_count)
	for pos in _positions_of_scatter(grid):
		result.winning_positions.append(pos)


## 그리드 내 스캐터 심볼 개수(mechanic 기반 — kind 를 직접 모름).
static func _count_scatter(grid: Array) -> int:
	var count := 0
	for col in grid:
		for sym in col:
			if sym != null and sym.is_scatter():
				count += 1
	return count


## 그리드 내 스캐터 심볼의 (reel, row) 좌표 목록.
static func _positions_of_scatter(grid: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in range(grid.size()):
		var col: Array = grid[r]
		for row in range(col.size()):
			var sym: SymbolData = col[row]
			if sym != null and sym.is_scatter():
				out.append(Vector2i(r, row))
	return out
