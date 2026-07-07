class_name DefenseArtifactEffect
extends ChoiceEffect
## 알베르트 선택지 3: 수비형 유물 (Phase 8-B/E).
## 가시 바리케이드/마력 보호막 등 수비 패시브 획득.
## Phase 8-E: LordState 에 id 저장 + ArtifactManager 에 실제 효과 등록.

@export var artifact_id: StringName = &"spike_barricade"   # 획득할 유물 id


func apply(lord: Node) -> void:
	super.apply(lord)
	# LordState 에 유물 id 기록 (UI/상태 표시용).
	if lord.has_method("add_defense_artifact"):
		lord.add_defense_artifact(artifact_id)
	# ArtifactManager 에 실제 효과 등록 (전장 데미지/흡수 발동).
	var am := lord.get_node_or_null("/root/ArtifactManager")
	if am != null and am.has_method("register"):
		am.register(artifact_id)
