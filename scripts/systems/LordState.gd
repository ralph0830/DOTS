extends Node
## LordState — 성주(Lord)의 현재 강화 상태를 추적하는 autoload (Phase 8-B).
## ChoiceEffect.apply() 의 적용 대상. 영혼 게이지 레벨업 선택지가 여기에 누적된다.
##
## 현재 프로토타입: 알베르트(강철의 공작) 고정 — 안정성/방어/꽝 보정 특화.
## Phase 10-C 에서 성주 3종(필립/아우렐리아) 추가 시 확장.
##
## 상태 카테고리 (PRD §3.3 알베르트 기준):
##   - unit_tier: 기사/방패병 티어 (0=훈련병 → 1=정규직 → 2=왕실 근위대)
##   - miss_compensation: 꽝 보정 강화 레벨 (미니언 수/품질)
##   - defense_artifacts: 수비형 유물 목록

# --- 상태 ---
var lord_id: StringName = &"albert"        # 현재 성주 (프로토타입은 알베르트 고정)
var lord_display_name: String = "강철의 공작, 알베르트"
var lord_description: String = "안정성 / 방어 및 꽝 보정 특화"

# 알베르트 선택지 카테고리별 강화 레벨 (0부터 시작, 선택 시 +1).
var unit_tier: int = 0                     # 기사/방패병 체급 진화 티어
var unit_tier_max: int = 2                 # 만렙 (훈련병→정규직→왕실 근위대)
var miss_compensation: int = 0             # 꽝 보정 강화 레벨
var miss_compensation_max: int = 3
var defense_artifacts: Array[StringName] = []  # 획득한 수비형 유물 id 목록

# 선택지 횟수 추적 (디버그/밸런스용).
var choices_taken_total: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 게임 시작 시 리셋 (SoulGauge.initialize 와 함께 호출).
func reset() -> void:
	unit_tier = 0
	miss_compensation = 0
	defense_artifacts.clear()
	choices_taken_total = 0


## 기사/방패병 티어 진화 (알베르트 선택지 1).
func upgrade_unit_tier() -> bool:
	if unit_tier >= unit_tier_max:
		return false
	unit_tier += 1
	choices_taken_total += 1
	print("[LordState] 유닛 체급 진화 → 티어 %d/%d" % [unit_tier, unit_tier_max])
	return true


## 꽝 보정 강화 (알베르트 선택지 2).
func upgrade_miss_compensation() -> bool:
	if miss_compensation >= miss_compensation_max:
		return false
	miss_compensation += 1
	choices_taken_total += 1
	print("[LordState] 꽝 보정 강화 → 레벨 %d/%d" % [miss_compensation, miss_compensation_max])
	return true


## 수비형 유물 획득 (알베르트 선택지 3).
func add_defense_artifact(artifact_id: StringName) -> void:
	if defense_artifacts.has(artifact_id):
		return
	defense_artifacts.append(artifact_id)
	choices_taken_total += 1
	print("[LordState] 수비형 유물 획득 → %s (총 %d개)" % [artifact_id, defense_artifacts.size()])


## 현재 상태 요약 (UI 표시용).
func get_state_summary() -> Dictionary:
	return {
		"lord_id": lord_id,
		"lord_name": lord_display_name,
		"unit_tier": unit_tier,
		"unit_tier_max": unit_tier_max,
		"miss_compensation": miss_compensation,
		"miss_compensation_max": miss_compensation_max,
		"defense_artifacts": defense_artifacts.duplicate(),
		"choices_taken": choices_taken_total,
	}


# --- 선택지 풀 (Phase 8-B) ---
# 알베르트 선택지 3종. 향후 성주별 풀 분리 시 LordData 로 이관.
# preload 로 모바일 export 안전 확보 (SymbolMechanic 버그와 동일 패턴 회피).
const _UnitEvolutionEffect_ := preload("res://scripts/data/effects/UnitEvolutionEffect.gd")
const _MissCompensationEffect_ := preload("res://scripts/data/effects/MissCompensationEffect.gd")
const _DefenseArtifactEffect_ := preload("res://scripts/data/effects/DefenseArtifactEffect.gd")
const _LevelUpChoice_ := preload("res://scripts/data/LevelUpChoice.gd")


## 알베르트 전체 선택지 풀 생성. 매 호출마다 새 인스턴스 (중복 선택 방지용 고유 effect).
func _build_albert_pool() -> Array:
	var pool: Array[LevelUpChoice] = []
	# 선택지 1: 유닛 체급 진화
	var c1: LevelUpChoice = _LevelUpChoice_.new()
	c1.id = &"unit_evolution"
	c1.display_name = "유닛 체급 진화"
	c1.description = "기사/방패병 티어 +1\n(훈련병 → 정규직 → 왕실 근위대)"
	c1.icon_color = Color(0.25, 0.55, 0.95)
	c1.category = &"unit"
	c1.effect = _UnitEvolutionEffect_.new()
	pool.append(c1)
	# 선택지 2: 꽝 보정 강화
	var c2: LevelUpChoice = _LevelUpChoice_.new()
	c2.id = &"miss_boost"
	c2.display_name = "꽝 보정 강화"
	c2.description = "꽝 시 미니언 수/품질 강화\n(라인 붕괴 방지)"
	c2.icon_color = Color(0.65, 0.65, 0.70)
	c2.category = &"miss"
	c2.effect = _MissCompensationEffect_.new()
	pool.append(c2)
	# 선택지 3: 수비형 유물 (가시 바리케이드)
	var c3: LevelUpChoice = _LevelUpChoice_.new()
	c3.id = &"spike_barricade"
	c3.display_name = "가시 바리케이드"
	c3.description = "기지 앞 가시 바리케이드 설치\n(접근 적에게 도트 데미지)"
	c3.icon_color = Color(0.8, 0.3, 0.2)
	c3.category = &"artifact"
	var eff3 := _DefenseArtifactEffect_.new()
	eff3.artifact_id = &"spike_barricade"
	c3.effect = eff3
	pool.append(c3)
	# 선택지 4: 마력 보호막 (수비 유물 2종째)
	var c4: LevelUpChoice = _LevelUpChoice_.new()
	c4.id = &"magic_shield"
	c4.display_name = "마력 보호막"
	c4.description = "기지 마력 보호막 활성화\n(일정량 피해 흡수)"
	c4.icon_color = Color(0.4, 0.7, 1.0)
	c4.category = &"artifact"
	var eff4 := _DefenseArtifactEffect_.new()
	eff4.artifact_id = &"magic_shield"
	c4.effect = eff4
	pool.append(c4)
	return pool


## 현재 상태에서 선택 가능한 선택지 3장을 무작위 추출.
## 만렙/중복 등은 can_choose() 로 필터링 후 추출.
func roll_choices(count: int = 3) -> Array:
	var pool := _build_albert_pool()
	# can_choose 필터링 (만렙 선택지 제외).
	var available: Array = []
	for c in pool:
		var choice: LevelUpChoice = c
		if choice.effect != null and choice.effect.has_method("can_choose") and choice.effect.can_choose(self):
			available.append(choice)
	# 무작위 셔플 후 count 개 추출 (풀이 count 미만이면 전체).
	available.shuffle()
	var result: Array = []
	for i in range(min(count, available.size())):
		result.append(available[i])
	return result
