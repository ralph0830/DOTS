class_name SymbolData
extends Resource
## 심볼 1종의 정적 속성을 정의하는 데이터 리소스.
## 에디터에서 @export로 노출되어 코딩 없이 튜닝 가능. 인스턴스는 resources/symbols/*.tres.

# 심볼 종류: 일반 / 와일드(대체) / 스캐터(프리스핀) / 보너스(잭팟 트리거)
enum Kind { NORMAL, WILD, SCATTER, BONUS }

# 프로시저럴 렌더링용 도형 모양 (SymbolView._draw에서 분기)
# Phase 8: 유닛 4종(기사/궁수/마법사/해골) 식별용 도형 추가. 기존 보석 도형은 호환 유지.
enum Shape { CIRCLE, DIAMOND, SQUARE, TRIANGLE, STAR, HEX, KNIGHT, ARCHER, MAGE, SKULL }

@export var id: StringName = &""                       # 고유 식별자 ("ruby", "unicorn" ...)
@export var kind: Kind = Kind.NORMAL                   # 심볼 종류
@export var display_name: String = ""                  # UI 표시명
@export var color: Color = Color.WHITE                 # 플레이스홀더 도형 색상
@export var shape: Shape = Shape.CIRCLE                # 플레이스홀더 도형 모양
## 지불표: 3/4/5매치 당첨 배수. PackedInt32Array 대신 개별 int로 분해
## (Godot 4.7 바이너리 export 시 PackedInt32Array 직렬화 손실 버그 회피).
@export var payout_3: int = 0
@export var payout_4: int = 0
@export var payout_5: int = 0
## ★에셋 교체 포인트: null이면 프로시저럴 도형, 텍스처 할당 시 자동 적용.
@export var texture: Texture2D
## Phase 7: 매칭 시 소환할 유닛 ID (빈 값 = 유닛 미매핑/순수 크레딧 심볼).
@export var unit_id: StringName = &""

## 확장 축: 커스텀 메카닉(확장 Wild·Multiplier·Sticky 등). null이면 kind 기반 기본 동작.
## 새 메카닉은 SymbolMechanic 서브클래스 리소스를 만들어 여기에 할당하면 된다.
@export var mechanic: SymbolMechanic


## 호환용 payout 배열 반환 (기존 코드 호환). payout_3/4/5를 합쳐서 반환.
func get_payout_array() -> PackedInt32Array:
	return PackedInt32Array([0, 0, 0, payout_3, payout_4, payout_5])


## 주어진 매치 수(3/4/5)에 대한 배수를 반환. 범위 밖이면 0.
func get_payout(match_count: int) -> int:
	match match_count:
		3: return payout_3
		4: return payout_4
		5: return payout_5
	return 0


## 이 심볼이 라인 지불 대상인지 (일반 심볼만). 메카닉 기반.
func is_payable() -> bool:
	return participates_in_line() and can_be_line_target() and not is_substitutable()


# --- 메카닉 위임 ---
# SpinEvaluator 가 kind 를 직접 모르게 한다. 모든 평가 질문은 메카닉으로.

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


## 스캐터 계열 심볼인지(ScatterMechanic 또는 그 서브클래스).
func is_scatter() -> bool:
	return effective_mechanic() is ScatterMechanic


## 보너스 계열 심볼인지(BonusMechanic 또는 서브클래스 — 잭팟 트리거).
func is_bonus() -> bool:
	return effective_mechanic() is BonusMechanic
