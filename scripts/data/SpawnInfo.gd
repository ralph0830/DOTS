class_name SpawnInfo
extends Resource
## 단일 웨이브 내 스폰 그룹 템플릿. 특정 타임라인 구간(start~end) 동안 spawn_delay 주기로 반복 스폰.
## docs/WAVE_MANAGER.md 명세. monster_id 로 UnitRegistry 에서 UnitData 를 조회해 BattleField.spawn_enemy.
## 단일 Resource + @export 스칼라 필드라 모바일 직렬화 안전 (PackedArray 회피).

@export var monster_id: StringName = &"goblin"   # UnitRegistry 적 유닛 ID
@export var start_time: float = 0.0              # 웨이브 시작 후 등장 시점(초)
@export var end_time: float = 20.0               # 등장 종료 시점(초)
@export var spawn_delay: float = 4.0             # 스폰 주기(초)
@export var count_per_tick: int = 1              # 1주기(tick)당 동시 스폰 수
