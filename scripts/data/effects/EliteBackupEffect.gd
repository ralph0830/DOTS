class_name EliteBackupEffect
extends ChoiceEffect
## 정예 백업 (초반) — 슬롯 꽝 시 미니언 대신 현재 최고 티어 유닛 1마리 소환.
## LordState.elite_backup = true. UnitSpawner 가 꽝 분기에서 이 값을 읽어 소환 종류 결정.

func apply(lord: Node) -> void:
	super.apply(lord)
	lord.elite_backup = true


func can_choose(lord: Node) -> bool:
	# 이미 활성화되어 있으면 중복 제외.
	if lord.has_method("get_state_summary"):
		return not bool(lord.get_state_summary().get("elite_backup", false))
	return true
