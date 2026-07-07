class_name ChoiceEffect
extends Resource
## 레벨업 선택지 효과 플러그인 베이스 (Phase 8-B).
## EvaluationPass 패턴을 참고 — 코어 수정 없이 새 효과를 서브클래싱으로 추가.
##
## Resource 를 상속 (LevelUpChoice.effect 필드에 할당 가능).
## RefCounted 는 Resource 필드에 할당 불가 → Resource 사용.
##
## 새 선택지 효과를 만들려면 이 클래스를 상속해 apply() 를 구현하면 된다.
##   예) UnitEvolutionEffect, SkullCompensationEffect, DefenseArtifactEffect ...
##
## 적용 대상: LordState (성주의 현재 강화 상태).
## 부작용: apply() 내에서 EventBus 시그널을 emit 하거나 다른 매니저를 호출 가능.

## 이 선택지를 성주 상태에 적용한다.
## lord: LordState — 적용 대상. effect 전용 데이터는 서브클래스 필드로 보관.
func apply(_lord: Node) -> void:
	pass  # 서브클래스에서 구현


## 선택지가 현재 적용 가능한지 (선택지 풀에서 필터링용).
## 예) 이미 만렙인 유닛 진화는 제외. 기본은 항상 가능.
func can_choose(_lord: Node) -> bool:
	return true
