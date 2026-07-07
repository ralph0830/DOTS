class_name SymbolMechanic
extends Resource
## 심볼 메카닉 플러그인 베이스(평가 로직의 확장점).
## 라인 평가에 필요한 질문 4가지를 "심볼 스스로" 답하게 만든다.
##   - participates_in_line : 라인 매칭에 참여하는 심볼인가?(Scatter/Bonus=false)
##   - can_be_line_target   : 매칭의 '기준(타겟)'이 될 수 있는가?
##   - is_substitutable     : 다른 심볼을 '대체'하는가?(Wild=true)
##   - matches              : 주어진 타겟에 매치되는가?
##   - get_tags             : 이 메카닉의 종류 태그(scatter/bonus/...). 타입 체크 대신 사용.
## 새 메카닉(ExpandingWild, Multiplier, Sticky, BonusTrigger 등)은 이 클래스를 상속해
## 해당 메서드만 오버라이드하면 된다 — SpinEvaluator 코드 수정 불필요.
## SymbolData.mechanic 이 null 이면 kind 기반 기본 메카닉(for_kind)이 사용된다.

# 모바일 export 안전: 서브클래스를 preload 로 컴파일 타임 강제 로드한다.
# 이유: for_kind() 가 class_name 전역 식별자로 서브클래스를 lazy 참조하면, 모바일 APK
# 런타임에서 for_kind() 첫 호출 시점에 서브클래스 스크립트가 아직 로드되지 않아
# 잘못된 폴백 메카닉이 반환되고 매칭이 실패하는 버그가 발생한다(데스크톱은 에디터가
# 글로벌 클래스 DB를 사전 완성하므로 정상 동작). preload 는 이 파일이 로드되는 순간
# 서브클래스들도 함께 로드하므로 호출 시점을 보장한다.
# (const 명 뒤의 _ 접미사는 class_name 과의 식별자 충돌 회피용.)
const NormalMechanic_  := preload("res://scripts/data/mechanics/NormalMechanic.gd")
const WildMechanic_    := preload("res://scripts/data/mechanics/WildMechanic.gd")
const ScatterMechanic_ := preload("res://scripts/data/mechanics/ScatterMechanic.gd")
const BonusMechanic_   := preload("res://scripts/data/mechanics/BonusMechanic.gd")

# kind → 기본 메카닉 레지스트리. match 분기 대신 Dictionary 조회로 코어 OCP 확보.
# 새 Kind/기본 메카닉 추가 시 _ensure_registry() 에 _register() 한 줄만 추가하면 된다.
static var _registry: Dictionary = {}   # int(kind) -> SymbolMechanic(무상태 싱글톤)


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


## 이 메카닉의 종류 태그. SymbolData.is_scatter()/is_bonus() 등이 타입 체크(`is X`) 대신
## 이 태그를 조회한다 — 새 메카닉 종류 추가 시 베이스/타입 체크 코드 수정 불필요.
func get_tags() -> PackedStringArray:
	return PackedStringArray()


## 레지스트리에 메카닉 등록(무상태 싱글톤 재사용).
static func _register(kind: int, mech: SymbolMechanic) -> void:
	_registry[kind] = mech


## 최초 호출 시 기본 메카닉 4종을 레지스트리에 등록.
static func _ensure_registry() -> void:
	if not _registry.is_empty():
		return
	_register(SymbolData.Kind.NORMAL, NormalMechanic_.new())
	_register(SymbolData.Kind.WILD, WildMechanic_.new())
	_register(SymbolData.Kind.SCATTER, ScatterMechanic_.new())
	_register(SymbolData.Kind.BONUS, BonusMechanic_.new())


## kind → 기본 메카닉 팩토리. SymbolData.mechanic 이 null 일 때 사용.
## 무상태 메카닉 싱글톤을 반환(최초 등록 시 1회 생성, 이후 재사용).
static func for_kind(kind: int) -> SymbolMechanic:
	_ensure_registry()
	if _registry.has(kind):
		return _registry[kind]
	# 알 수 없는 kind → 일반 메카닉 폴백.
	return _registry[SymbolData.Kind.NORMAL]
