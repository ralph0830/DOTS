class_name SymbolData
extends Resource
## 심볼 1종의 정적 속성을 정의하는 데이터 리소스.
## 에디터에서 @export로 노출되어 코딩 없이 튜닝 가능. 인스턴스는 resources/symbols/*.tres.

# 심볼 종류: 일반 / 와일드(대체) / 스캐터(프리스핀) / 보너스(잭팟 트리거)
enum Kind { NORMAL, WILD, SCATTER, BONUS }

# 프로시저럴 렌더링용 도형 모양 (SymbolView._draw에서 분기)
# Phase 8: 유닛 4종(기사/궁수/마법사/해골) 식별용 도형 추가. 기존 보석 도형은 호환 유지.
enum Shape { CIRCLE, DIAMOND, SQUARE, TRIANGLE, STAR, HEX, KNIGHT, ARCHER, MAGE, SKULL }

# 메카닉 태그 — is_scatter/is_bonus 가 타입 체크 대신 조회(코어 OCP).
const TAG_SCATTER := &"scatter"
const TAG_BONUS := &"bonus"

@export var id: StringName = &""                       # 고유 식별자 ("ruby", "unicorn" ...)
@export var kind: Kind = Kind.NORMAL                   # 심볼 종류
@export var display_name: String = ""                  # UI 표시명
@export var color: Color = Color.WHITE                 # 플레이스홀더 도형 색상
@export var shape: Shape = Shape.CIRCLE                # 플레이스홀더 도형 모양
## 지불표: {매치수: 배수} Dictionary — 3/4/5 제한 없이 임의 매치 수 지원(open-structure).
## 모바일 export 직렬화 안전(Dictionary는 PackedArray 손실 이슈 없음).
@export var payouts: Dictionary = {3: 0, 4: 0, 5: 0}
## ★에셋 교체 포인트: null이면 프로시저럴 도형, 텍스처 할당 시 자동 적용.
@export var texture: Texture2D
## Phase 7: 매칭 시 소환할 유닛 ID (빈 값 = 유닛 미매핑/순수 크레딧 심볼).
@export var unit_id: StringName = &""

## 확장 축: 커스텀 메카닉(확장 Wild·Multiplier·Sticky 등). null이면 kind 기반 기본 메카닉(for_kind).
## 새 메카닉은 SymbolMechanic 서브클래스 리소스를 만들어 여기에 할당하면 된다.
@export var mechanic: SymbolMechanic


## 호환용 payout 배열 반환 (인덱스 3/4/5).
func get_payout_array() -> PackedInt32Array:
	return PackedInt32Array([0, 0, 0, get_payout(3), get_payout(4), get_payout(5)])


## 주어진 매치 수에 대한 배수를 반환. Dictionary 조회 — 임의 매치 수 지원.
func get_payout(match_count: int) -> int:
	return int(payouts.get(match_count, 0))


# --- 메카닉 위임 (Open-structure 핵심) ---
# SpinEvaluator 가 kind 를 직접 모르게 한다. 모든 평가 질문은 메카닉으로 위임한다.
# 기본 메카닉(for_kind)의 모바일 export 안전성은 SymbolMechanic.gd 의 preload 강제
# 로드로 보장된다 — kind 를 직접 분기하는 회피 없이도 APK/데스크톱이 동일하게 동작.

## 유효 메카닉: mechanic 우선, 없으면 kind 기본 메카닉(for_kind).
func effective_mechanic() -> SymbolMechanic:
	if mechanic != null:
		return mechanic
	return SymbolMechanic.for_kind(kind)


func participates_in_line() -> bool:
	return effective_mechanic().participates_in_line()


func can_be_line_target() -> bool:
	return effective_mechanic().can_be_line_target()


func is_substitutable() -> bool:
	return effective_mechanic().is_substitutable()


func matches(target_symbol: SymbolData) -> bool:
	return effective_mechanic().matches(target_symbol, self)


## 스캐터 계열 심볼인지(메카닉 태그 기반 — 타입 체크 대신).
func is_scatter() -> bool:
	return effective_mechanic().get_tags().has(TAG_SCATTER)


## 보너스 계열 심볼인지(메카닉 태그 기반 — 잭팟 트리거).
func is_bonus() -> bool:
	return effective_mechanic().get_tags().has(TAG_BONUS)
