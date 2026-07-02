class_name JackpotEvaluationPass
extends EvaluationPass
## 잭팟 평가 패스.
## 각 페이라인에서 왼쪽(릴 0)부터 BONUS 심볼 연속 개수를 세어
## Paytable.bonus_line_jackpot 조건을 만족하면 JackpotSystem 에서 금액을 지급받는다.
## 한 스핀에 잭팟은 최대 1개(가장 높은 tier 우선).

func process(result: SpinResult, ctx: Dictionary) -> void:
	var paytable: Paytable = ctx["paytable"]
	# 잭팟 비활성(조건 딕셔너리 비었음) → 아무 것도 하지 않음.
	if paytable.bonus_line_jackpot.is_empty():
		return

	var grid: Array = ctx["grid"]
	var paylines: Array = ctx["paylines"]

	# 잭팩트: BONUS 연속 카운트 → 잭팟 티어 후보들을 모은 뒤, 가장 높은 tier 선택.
	var best_tier: int = -1
	var best_count: int = 0
	var best_positions: Array[Vector2i] = []

	for payline in paylines:
		var counted := _count_bonus_run(grid, payline)
		var count: int = counted[0]
		if count <= 0:
			continue
		# 해당 카운트가 잭팟 조건 키에 해당하는지.
		if not paytable.bonus_line_jackpot.has(count):
			continue
		var tier: int = int(paytable.bonus_line_jackpot[count])
		# 더 높은 tier 가 우선. (JackpotSystem.Tier: MINI=0 < GRAND=3)
		if tier > best_tier:
			best_tier = tier
			best_count = count
			best_positions = counted[1]

	# 당첨 없음.
	if best_tier < 0:
		return

	# 잭팫 지급: JackpotSystem autoload(전역 식별자). RefCounted는 노드가 아니라 get_node_or_null 불가.
	var js: Node = JackpotSystem
	if js == null or not js.has_method("award"):
		return
	var amount: int = js.award(best_tier)
	if amount <= 0:
		return

	# 결과 반영: 티어/금액 기록, 당첨 금액 누적, 당첨 위치 추가(연출용).
	result.jackpot_tier = best_tier
	result.jackpot_amount = amount
	result.total_win += amount
	for pos in best_positions:
		# 중복 위치 회피(다른 당첨과 겹칠 수 있음).
		if not result.winning_positions.has(pos):
			result.winning_positions.append(pos)


## 한 페이라인에서 왼쪽(릴 0)부터 BONUS 심볼의 연속 개수와 위치를 반환.
## 반환: [count:int, positions:Array[Vector2i]] — BONUS 가 아니거나 중단되면 그 시점까지.
static func _count_bonus_run(grid: Array, payline: Payline) -> Array:
	var count := 0
	var positions: Array[Vector2i] = []
	var reel_count: int = grid.size()
	# Payline.get_row 는 페이라인 길이(릴 수)만큼만 유효 row 를 반환한다고 가정.
	for r in range(reel_count):
		var row: int = payline.get_row(r)
		var sym: SymbolData = _cell(grid, r, row)
		if sym == null:
			break
		if sym.is_bonus():
			count += 1
			positions.append(Vector2i(r, row))
		else:
			break
	return [count, positions]


## 그리드에서 (reel, row) 심볼 조회. 범위 밖이면 null.
static func _cell(grid: Array, reel: int, row: int) -> SymbolData:
	if reel < 0 or reel >= grid.size():
		return null
	var col: Array = grid[reel]
	if row < 0 or row >= col.size():
		return null
	return col[row]
