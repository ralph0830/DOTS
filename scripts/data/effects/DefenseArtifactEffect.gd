class_name DefenseArtifactEffect
extends ChoiceEffect
## 알베르트 선택지 3: 수비형 유물 (Phase 8-B).
## 가시 바리케이드/마력 보호막 등 수비 패시브 획득. LordState.defense_artifacts 에 추가.
## 현재는 상태만 갱신. ArtifactManager(Phase 8-E)에서 실제 효과 적용.

@export var artifact_id: StringName = &"spike_barricade"   # 획득할 유물 id


func apply(lord: Node) -> void:
	super.apply(lord)
	if lord.has_method("add_defense_artifact"):
		lord.add_defense_artifact(artifact_id)
