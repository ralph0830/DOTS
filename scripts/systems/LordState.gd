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

# P1 카드 효과 상태.
var elite_backup: bool = false        # 꽝 시 정예 유닛 소환
var elite_unit_id: StringName = &"knight"   # 정예 백업 유닛 ID (config화 — 하드코딩 제거)
var refund_on_miss: bool = false      # 꽝 시 베팅 50% 환급
var reroll_charges: int = 0           # 무상 리롤 잔여 횟수
var all_in_enabled: bool = false      # 100% 베팅 + 매칭 10배
var judgment_day_enabled: bool = false # 5매칭 시 전적 50% 피해
var multiplier: int = 1   # 배수(1/2/3) — 베팅+소환 양쪽 (배수 토글)

# 선택지 횟수 추적 (디버그/밸런스용).
var choices_taken_total: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 게임 시작 시 리셋 (SoulGauge.initialize 와 함께 호출).
func reset() -> void:
	unit_tier = 0
	miss_compensation = 0
	defense_artifacts.clear()
	elite_backup = false
	refund_on_miss = false
	reroll_charges = 0
	all_in_enabled = false
	judgment_day_enabled = false
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
		"elite_backup": elite_backup,
		"refund_on_miss": refund_on_miss,
		"reroll_charges": reroll_charges,
		"all_in_enabled": all_in_enabled,
		"judgment_day_enabled": judgment_day_enabled,
		"choices_taken": choices_taken_total,
	}


# --- 선택지 풀 (Phase 8-B) ---
# 알베르트 선택지 3종. 향후 성주별 풀 분리 시 LordData 로 이관.
# preload 로 모바일 export 안전 확보 (SymbolMechanic 버그와 동일 패턴 회피).
const _UnitEvolutionEffect_ := preload("res://scripts/data/effects/UnitEvolutionEffect.gd")
const _MissCompensationEffect_ := preload("res://scripts/data/effects/MissCompensationEffect.gd")
const _DefenseArtifactEffect_ := preload("res://scripts/data/effects/DefenseArtifactEffect.gd")
const _EliteBackupEffect_ := preload("res://scripts/data/effects/EliteBackupEffect.gd")
const _RefundOnMissEffect_ := preload("res://scripts/data/effects/RefundOnMissEffect.gd")
const _AllInEffect_ := preload("res://scripts/data/effects/AllInEffect.gd")
const _JudgmentDayEffect_ := preload("res://scripts/data/effects/JudgmentDayEffect.gd")
const _RerollEffect_ := preload("res://scripts/data/effects/RerollEffect.gd")
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
	c2.min_level = 1
	c2.max_level = 10
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
	# === P1 카드 (레벨 구간별) ===
	# 정예 백업 (초반 1-10) — 꽝 시 최고 티어 유닛 소환
	var c5: LevelUpChoice = _LevelUpChoice_.new()
	c5.id = &"elite_backup"
	c5.display_name = "정예 백업"
	c5.description = "꽝 시 미니언 대신\n최고 티어 유닛 1마리 소환"
	c5.icon_color = Color(0.95, 0.75, 0.3)
	c5.category = &"miss"
	c5.min_level = 1
	c5.max_level = 10
	c5.effect = _EliteBackupEffect_.new()
	pool.append(c5)
	# 재활용 주술 (초반 1-10) — 꽝 시 베팅 50% 환급
	var c6: LevelUpChoice = _LevelUpChoice_.new()
	c6.id = &"refund_on_miss"
	c6.display_name = "재활용 주술"
	c6.description = "꽝 시 베팅의 50% 환급\n(리스크 완화)"
	c6.icon_color = Color(0.3, 0.9, 0.7)
	c6.category = &"miss"
	c6.min_level = 1
	c6.max_level = 10
	c6.effect = _RefundOnMissEffect_.new()
	pool.append(c6)
	# 스핀 리롤러 (초반 1-10) — 무상 리롤 +3회
	var c7: LevelUpChoice = _LevelUpChoice_.new()
	c7.id = &"reroll"
	c7.display_name = "스핀 리롤러"
	c7.description = "무상 리롤 버튼 +3회\n(나쁜 결과 다시 돌리기)"
	c7.icon_color = Color(0.7, 0.6, 1.0)
	c7.category = &"system"
	c7.min_level = 1
	c7.max_level = 10
	c7.effect = _RerollEffect_.new()
	pool.append(c7)
	# 중력 왜곡석 (중반 11-25) — 중앙 적 둔화
	var c8: LevelUpChoice = _LevelUpChoice_.new()
	c8.id = &"gravity_field"
	c8.display_name = "중력 왜곡석"
	c8.description = "화면 중앙 중력장 형성\n(적 이동속도 25% 둔화)"
	c8.icon_color = Color(0.5, 0.3, 0.9)
	c8.category = &"artifact"
	c8.min_level = 11
	c8.max_level = 25
	var eff8 := _DefenseArtifactEffect_.new()
	eff8.artifact_id = &"gravity_field"
	c8.effect = eff8
	pool.append(c8)
	# 올 인 (후반 26+) — 100% 베팅 + 매칭 10배
	var c9: LevelUpChoice = _LevelUpChoice_.new()
	c9.id = &"all_in"
	c9.display_name = "올 인"
	c9.description = "보유 GOLD 100% 베팅\n(매칭 시 소환 10배, 꽝 시 전액 상실)"
	c9.icon_color = Color(1.0, 0.85, 0.2)
	c9.category = &"rule"
	c9.min_level = 26
	c9.max_level = 999
	c9.effect = _AllInEffect_.new()
	pool.append(c9)
	# 심판의 날 (후반 26+) — 5매칭 시 전적 50% 피해
	var c10: LevelUpChoice = _LevelUpChoice_.new()
	c10.id = &"judgment_day"
	c10.display_name = "심판의 날"
	c10.description = "5매칭(잭팟) 시\n필드 모든 적 현재체력 50% 피해"
	c10.icon_color = Color(1.0, 0.4, 0.4)
	c10.category = &"rule"
	c10.min_level = 26
	c10.max_level = 999
	c10.effect = _JudgmentDayEffect_.new()
	pool.append(c10)
	return pool


## 현재 상태에서 선택 가능한 선택지 3장을 무작위 추출.
## 만렙/중복 등은 can_choose() 로 필터링 후 추출.
func roll_choices(count: int = 3) -> Array:
	var pool := _build_albert_pool()
	# 현재 레벨 (SoulGauge) — 레벨 구간 필터링용.
	var level := 1
	var sg := get_node_or_null("/root/SoulGauge")
	if sg != null and "level" in sg:
		level = sg.level
	# 레벨 구간 + can_choose 필터링.
	var available: Array = []
	for c in pool:
		var choice: LevelUpChoice = c
		if level < choice.min_level or level > choice.max_level:
			continue
		if choice.effect != null and choice.effect.has_method("can_choose") and choice.effect.can_choose(self):
			available.append(choice)
	# 무작위 셔플 후 count 개 추출 (풀이 count 미만이면 전체).
	available.shuffle()
	var result: Array = []
	for i in range(min(count, available.size())):
		result.append(available[i])
	return result
