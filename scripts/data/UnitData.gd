class_name UnitData
extends Resource
## 유닛/적 1종의 정적 속성을 정의하는 데이터 리소스.
## Phase 7 임시: 텍스처 없이 프로시저럴 도형으로 렌더링 (size/shape/color).
## Phase 9에서 ComfyUI 실루엣 PNG로 교체 (texture 필드).

# 역할 — 아군 3종 + 적
enum Role { TANK, DEALER, SUPPORTER, MINION, ENEMY }

@export var unit_id: StringName = &""
@export var display_name: String = ""
@export var role: Role = Role.DEALER
# 전투 스탯
@export var max_hp: int = 30
@export var attack: int = 8
@export var attack_interval: float = 1.0   # 공격 쿨타임(초)
@export var move_speed: float = 60.0       # px/초
@export var attack_range: float = 70.0     # 공격 사거리(px)
## Phase 8-A: 이 유닛(주로 적)을 처치했을 때 얻는 영혼(EXP) 보상.
## 아군 유닛은 보통 0. SoulGauge 가 enemy_killed 시그널에서 이 값을 읽어 게이지 충전.
@export var exp_reward: int = 0
# 임시 렌더링 (프로시저럴 도형)
enum Shape { CIRCLE, SQUARE, TRIANGLE, DIAMOND }
@export var shape: Shape = Shape.CIRCLE
@export var color: Color = Color.WHITE
@export var size: float = 60.0             # 도형 지름(px)
# ★에셋 교체 포인트: null이면 프로시저럴 도형, 텍스처 할당 시 실제 아트.
@export var texture: Texture2D
