class_name UnitEvolutionEffect
extends ChoiceEffect
## 알베르트 선택지 1: 유닛 체급 진화 (Phase 8-B).
## 기사/방패병 티어를 +1 상승 (훈련병 → 정규직 → 왕실 근위대).
## 현재는 LordState 상태만 갱신. Phase 8-D 에서 실제 UnitData 스탯에 반영 예정.


func apply(lord: Node) -> void:
	super.apply(lord)
	if lord.has_method("upgrade_unit_tier"):
		var ok: bool = lord.upgrade_unit_tier()
		if not ok:
			print("[UnitEvolutionEffect] 이미 만렙 — 적용 건너뜀")


func can_choose(lord: Node) -> bool:
	# 만렙이면 선택지 풀에서 제외.
	if lord.has_method("get_state_summary"):
		var summary: Dictionary = lord.get_state_summary()
		return int(summary.get("unit_tier", 0)) < int(summary.get("unit_tier_max", 2))
	return true
