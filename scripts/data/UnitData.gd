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
## 적 처치 시 지급되는 CREDIT 보상 (아군은 보통 0). WalletManager.add_credit 으로 즉시 지급.
@export var credit_reward: int = 0
# 임시 렌더링 (프로시저럴 도형)
enum Shape { CIRCLE, SQUARE, TRIANGLE, DIAMOND }
@export var shape: Shape = Shape.CIRCLE
@export var color: Color = Color.WHITE
# 도형 크기 — 가로/세로 별도 (에디터 튜닝). 스프라이트 없이 도형만 렌더링.
@export var size_w: float = 60.0   # 가로(px) — 도형/이미지 공통 크기
@export var size_h: float = 60.0   # 세로(px) — 도형/이미지 공통 크기
# 이미지 교체 포인트 — texture 할당 시 도형 대신 이미지를 size_w/h 에 맞춰 그림. null 이면 도형.
@export var texture: Texture2D

# --- 행동 패턴 (Phase 9) ---
# MELEE=돌격(같은 진영 통과 허용, 항상 전진), RANGED=간격 유지+사거리 공격,
# SUPPORT=확장(힐러 등 — 현재 RANGED-like 폴백).
# is_ranged(bool)는 deprecated 보존(.tres 호환) — behavior 로 마이그레이션.
enum Behavior { MELEE, RANGED, SUPPORT }
@export var behavior: Behavior = Behavior.MELEE

# --- 투사체 (Phase 9: 원거리 공격) ---
# is_ranged=true 면 투사체를 발사해 타격. 아니면 근접 즉시 타격.
# 개별 @export (PackedArray 회피 — 모바일 직렬화 안전).
@export var is_ranged: bool = false
@export var projectile_speed: float = 220.0   # 투사체 속도 (px/초)
@export var projectile_size: float = 12.0      # 투사체 지름 (px)
@export var projectile_color: Color = Color.WHITE
@export var projectile_texture: Texture2D      # 차후 이미지 교체 (현재 미사용)


## 이 유닛이 원거리(RANGED) 행동인지 — behavior 또는 구 is_ranged 호환.
func is_ranged_unit() -> bool:
	return behavior == Behavior.RANGED or is_ranged
