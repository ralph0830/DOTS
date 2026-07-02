extends Node
## ParticleBudget — 활성 파티클 수를 기기 티어에 맞춰 제한하는 전역 예산 관리자.
## WinEffects 등 이펙트 노드가 request()로 허용량을 받아 생성하고, release()로 반환.
## 모바일 저사양 대응: Android/iOS에서는 기본 예산의 절반만 할당.

# --- 설정 ---
## 기본(데스크톱/콘솔) 총 파티클 예산
const DEFAULT_BUDGET: int = 400

# --- 상태 ---
## 현재 기기에 할당된 최대 활성 파티클 수
var _max_budget: int = DEFAULT_BUDGET
## 현재 활성(살아있는) 파티클 수
var _active: int = 0


func _ready() -> void:
	# 기기 티어 판별 — 모바일은 예산 절반으로 저사양 대응
	var os_name: String = OS.get_name()
	if os_name == "Android" or os_name == "iOS":
		_max_budget = int(float(DEFAULT_BUDGET) * 0.5)
	else:
		_max_budget = DEFAULT_BUDGET


## 요청량 대비 허용량 반환.
## 예산이 부족하면 남은 예산에 비례해 축소(0 가능). 0 이하 입력은 0 반환.
func request(amount: int) -> int:
	if amount <= 0:
		return 0
	# 남은 예산
	var remaining: int = _max_budget - _active
	if remaining <= 0:
		return 0
	if amount <= remaining:
		# 요청 전체 허용
		_active += amount
		return amount
	# 예산 초과 — 남은 만큼만 비례 할당
	_active = _max_budget
	return remaining


## 활성 파티클 수 감소. 음수 방지.
func release(amount: int) -> void:
	if amount <= 0:
		return
	_active = max(0, _active - amount)


## 현재 활성 파티클 수 (디버그/모니터링용).
func get_active() -> int:
	return _active


## 현재 할당된 최대 예산 (디버그/모니터링용).
func get_max_budget() -> int:
	return _max_budget
