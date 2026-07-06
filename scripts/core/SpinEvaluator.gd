class_name SpinEvaluator
extends RefCounted
## 단일 페이라인 평가. 각 심볼의 SymbolMechanic 에 매칭을 위임한다(kind 하드코딩 없음).
## 왼쪽(릴 0)부터 연속 매치. 타겟 = 첫 일반(비-대체) 심볼, 없으면 첫 대체(Wild) 심볼.

const MIN_MATCH := 3


## 한 페이라인의 당첨을 평가해 LineWin 반환. 무당첨이면 null.
static func evaluate_line(grid: Array, payline: Payline) -> LineWin:
	var line: Array[SymbolData] = []
	for r in range(5):
		line.append(_cell(grid, r, payline.get_row(r)))

	var first: SymbolData = line[0]
	if first == null or not first.participates_in_line():
		return null

	var target: SymbolData = _pick_target(line)
	if target == null:
		return null

	# DEBUG: 페이라인 0(가운데 행)만 상세 추적 — 매칭 실패 원인 파악.
	var dbg := payline.id == 0
	if dbg:
		var ids := []
		for s in line:
			ids.append(String(s.id) if s != null else "null")
		print("[DBG] pl0 line=%s target=%s" % [str(ids), String(target.id)])

	# 왼쪽부터 연속 매치. 참여하지 않는 심볼(Scatter/Bonus)을 만나면 중단.
	var match_count := 0
	var positions: Array[Vector2i] = []
	for r in range(5):
		var sym: SymbolData = line[r]
		if sym == null:
			if dbg: print("[DBG]   r%d null → break" % r)
			break
		if not sym.participates_in_line():
			if dbg: print("[DBG]   r%d %s not_participate → break" % [r, sym.id])
			break
		var matched := sym.matches(target)
		if dbg:
			print("[DBG]   r%d %s.matches(%s)=%s" % [r, String(sym.id), String(target.id), matched])
		if matched:
			match_count += 1
			positions.append(Vector2i(r, payline.get_row(r)))
		else:
			break

	if dbg:
		print("[DBG]   match_count=%d" % match_count)
	if match_count < MIN_MATCH:
		return null
	var amount2 := target.get_payout(match_count)
	if amount2 <= 0:
		return null

	var lw := LineWin.new()
	lw.payline_id = payline.id
	lw.symbol_id = target.id
	lw.match_count = match_count
	lw.amount = amount2
	lw.positions = positions
	return lw


## 타겟 심볼 선택. 우선순위: (1) 일반 심볼(참여+타겟가능+비대체) (2) 대체 심볼(Wild).
## (1)이 없으면(전부 Wild인 라인) (2)로 Wild 자체 payout 사용.
static func _pick_target(line: Array) -> SymbolData:
	var fallback: SymbolData = null
	for sym in line:
		if sym == null:
			continue
		if not sym.participates_in_line() or not sym.can_be_line_target():
			continue
		if fallback == null:
			fallback = sym
		if not sym.is_substitutable():
			return sym   # 일반 심볼 → 즉시 타겟
	return fallback


## 그리드에서 그리드 좌표의 심볼 반환. 범위 밖이면 null.
static func _cell(grid: Array, reel: int, row: int) -> SymbolData:
	if reel < 0 or reel >= grid.size():
		return null
	var col: Array = grid[reel]
	if row < 0 or row >= col.size():
		return null
	return col[row]
