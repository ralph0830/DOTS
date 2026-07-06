class_name WaveData
extends Resource
## WAVE 1개의 적 구성 정의.
## Phase 7 임시: 단순한 적 스폰 타이밍/수. Phase 8에서 다양한 적 종류/보스 확장.

@export var wave_num: int = 1
## 적 유닛 ID 목록 (스폰 순서). Phase 7 임시: 모두 동일 적("goblin").
@export var enemy_ids: PackedStringArray = []
## 스폰 간격 (초)
@export var spawn_interval: float = 2.0
## WAVE 시작 전 대기 시간 (초)
@export var initial_delay: float = 3.0
