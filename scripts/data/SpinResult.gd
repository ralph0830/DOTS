class_name SpinResult
extends RefCounted
## 단일 스핀의 전체 평가 결과. SpinEvaluator/WinCalculator가 생성하고 View/Effects가 소비.

var total_win: int = 0                       # 이번 스핀 총 당첨 (잭팟 제외)
var line_wins: Array[LineWin] = []           # 라인 당첨 목록
var scatter_win: int = 0                     # 스캐터 당첨 금액
var scatter_count: int = 0                   # 등장한 스캐터 총 개수
var free_spins_awarded: int = 0              # 이번 스핀으로 획득한 프리스핀 수
var jackpot_tier: int = -1                   # 당첨된 잭팟 티어 (-1 = 없음; JackpotSystem.Tier 참조)
var winning_positions: Array[Vector2i] = []  # 모든 당첨 셀 (하이라이트/이펙트용)
var grid: Array = []                         # 5x3 결과 그리드: grid[reel][row] = SymbolData


## 당첨이 하나라도 있는지 (라인/스캐터/잭팟 포함).
func has_win() -> bool:
	return total_win > 0 or jackpot_tier >= 0


## 빅윈 임계치 (총 베팅의 N배) 초과 여부 — 연출 강도 결정용.
func is_big_win(bet: int, threshold_multiplier: float = 15.0) -> bool:
	if bet <= 0:
		return false
	return float(total_win) >= float(bet) * threshold_multiplier
