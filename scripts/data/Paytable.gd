class_name Paytable
extends Resource
## 스캐터 보상 규칙과 잭팟 트리거 조건을 담은 리소스.
## 라인 지불은 각 SymbolData.payout에 직접 정의되므로 여기서는 보너스 보상만 관리.
## 인스턴스는 resources/paytables/default_paytable.tres.

# --- 프리스핀 보상 (Scatter 3개 이상 시) ---
@export var scatter_free_spins_base: int = 8          # Scatter 3개 부여 프리스핀
@export var scatter_free_spins_per_extra: int = 4     # 3개 초과 시 추가당 프리스핀
@export var free_spin_multiplier: float = 2.0         # 프리스핀 중 당첨 배수

# --- 스캐터 크레딧 보상 (베팅 대비 배수) ---
@export var scatter_credit_mult_base: float = 2.0     # Scatter 3개 크레딧 배수
@export var scatter_credit_mult_per_extra: float = 1.0  # 3개 초과 시 추가당 배수

# --- 잭팟 트리거 (BONUS 심볼; Phase 4 본격 사용, 여기선 조건 데이터만 보관) ---
## BONUS 심볼이 한 라인에서 연속 N개일 때의 잭팟 티어 (JackpotSystem.Tier).
## 예: {5 = GRAND 인덱스, 4 = MAJOR 인덱스}. 빈 딕셔너리면 잭팟 비활성.
@export var bonus_line_jackpot: Dictionary = {}


## Scatter 개수 → 부여 프리스핀 수 계산.
func get_free_spins_for_scatter(scatter_count: int) -> int:
	if scatter_count < 3:
		return 0
	return scatter_free_spins_base + (scatter_count - 3) * scatter_free_spins_per_extra


## Scatter 개수 → 크레딧 보상 (베팅 곱). 3개 미만이면 0.
func get_scatter_credit(scatter_count: int, bet: int) -> int:
	if scatter_count < 3:
		return 0
	var mult: float = scatter_credit_mult_base + (scatter_count - 3) * scatter_credit_mult_per_extra
	return int(mult * float(bet))
