class_name LevelUpChoice
extends Resource
## 레벨업 3지선다 카드 1장의 정적 데이터 (Phase 8-B).
## 인스턴스는 향후 resources/choices/*.tres 로 데이터화 (현재는 코드 생성).
##
## 구조 (open-structure):
##   - 카드 메타데이터(id/표시명/설명/아이콘 색상) — UI 표시용.
##   - effect: ChoiceEffect 서브클래스 — 실제 효과 로직. 플러그인 패턴.
##
## 참고: effect 필드는 Resource 타입으로 선언 (class_name 순환 참조 회피 —
## SymbolMechanic 모바일 로딩 버그와 동일 패턴). apply()/can_choose() 는
## duck-typing 으로 호출 (has_method 로 가드). ChoiceEffect 베이스는
## scripts/data/ChoiceEffect.gd 참조.

@export var id: StringName = &""                # 고유 식별자 ("unit_evolution", "miss_boost", ...)
@export var display_name: String = ""           # 카드 제목 ("유닛 체급 진화")
@export var description: String = ""            # 카드 설명 ("기사/방패병 티어 +1")
@export var icon_color: Color = Color.WHITE     # 카드 아이콘 색상 (프로시저럴 도형용)
@export var category: StringName = &"general"   # 카테고리 (성주별 선택지 풀 필터링용)
## ★핵심: 이 카드를 선택했을 때 실행될 효과. ChoiceEffect 서브클래스 인스턴스.
## null 이면 효과 없는 더미 카드 (테스트용).
## Resource 타입으로 선언 (apply/can_choose 메서드 duck-typing 호출).
@export var effect: Resource
