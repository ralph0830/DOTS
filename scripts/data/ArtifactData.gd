class_name ArtifactData
extends Resource
## 유물 1종의 정적 데이터 (Phase 8-E).
## 향후 resources/artifacts/*.tres 로 데이터화. 현재는 ArtifactManager 가 코드 생성.
##
## open-structure:
##   - effect_type: 유물 효과 카테고리 (문자열 키). 새 유물 타입 추가 시 enum 대신 문자열 사용.
##   - params: 효과별 파라미터 (damage/absorb_rate/absorb_max 등). Dictionary 로 유연한 확장.
##
## effect_type 종류 (Phase 8-E 현재):
##   "spike"  — 가시 바리케이드: 기지 근처 적에게 도트 데미지. params: {damage, tick_interval, range}
##   "shield" — 마력 보호막: 기지 피해 흡수. params: {absorb_rate, absorb_max}

@export var id: StringName = &""                       # 고유 식별자
@export var display_name: String = ""                  # UI 표시명
@export var description: String = ""                   # 설명
@export var effect_type: StringName = &"spike"         # 효과 카테고리
@export var params: Dictionary = {}                    # 효과 파라미터 (damage/absorb_rate/absorb_max 등)
