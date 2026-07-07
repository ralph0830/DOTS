class_name MissCompensationEffect
extends ChoiceEffect
## 알베르트 선택지 2: 꽝 보정 강화 (Phase 8-B).
## 슬롯 꽝 시 소환되는 미니언 수/품질 강화. LordState.miss_compensation +1.
## 현재는 상태만 갱신. UnitSpawner 가 이 값을 읽어 소환 수를 결정하도록 Phase 8-D 에서 연결.


func apply(lord: Node) -> void:
	super.apply(lord)
	if lord.has_method("upgrade_miss_compensation"):
		var ok: bool = lord.upgrade_miss_compensation()
		if not ok:
			print("[MissCompensationEffect] 이미 만렙 — 적용 건너뜀")


func can_choose(lord: Node) -> bool:
	if lord.has_method("get_state_summary"):
		var summary: Dictionary = lord.get_state_summary()
		return int(summary.get("miss_compensation", 0)) < int(summary.get("miss_compensation_max", 3))
	return true
