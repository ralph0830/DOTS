class_name WaveData
extends Resource
## 단일 웨이브 세션 정보. spawn_list(타임라인 스폰 그룹) + 보스전 트리거.
## docs/WAVE_MANAGER.md 명세. spawn_list: Array[SpawnInfo] typed Array[Resource] — 모바일 직렬화 안전.

@export var wave_number: int = 1
@export var description: String = ""
@export var spawn_list: Array[SpawnInfo] = []
@export var is_boss_wave: bool = false
@export var boss_id: StringName = &"boss"        # 보스 웨이브 시 소환할 보스 ID
