extends SceneTree
## 기본 슬롯 데이터를 생성해 resources/ 아래 .tres 파일로 저장하는 셋업 스크립트.
## 실행: godot --headless --script res://scripts/setup/generate_default_data.gd --path <project>
## 재실행 시 기존 .tres를 덮어쓴다(밸런스 튜닝 후 재생성 용이).
##
## 주의: 최초 실행 시 GameConfig autoload가 default_slot.tres 를 못 찾아 에러를 출력하지만,
## 이 스크립트는 autoload에 의존하지 않고 직접 리소스를 생성하므로 정상 동작한다.

const SYMBOL_DIR := "res://resources/symbols/"
const REEL_DIR := "res://resources/reels/"
const PAYLINE_DIR := "res://resources/paylines/"
const PAYTABLE_DIR := "res://resources/paytables/"
const CONFIG_DIR := "res://resources/config/"
const PAYTABLE_PATH := PAYTABLE_DIR + "default_paytable.tres"
const CONFIG_PATH := CONFIG_DIR + "default_slot.tres"
# Phase 8-C: 유닛 데이터 .tres 디렉토리 (에디터 인스펙터로 밸런스 튜닝).
const UNIT_ALLY_DIR := "res://resources/units/ally/"
const UNIT_ENEMY_DIR := "res://resources/units/enemy/"

# 5개 릴 스트립(각 20 심볼). 빈도 = 출현 확률 → RTP/변동성 결정.
# Phase 8: 유닛 4종(knight/archer/mage/skull)만 배치. Wild/Scatter/Bonus 제거.
# 핵심: 모든 릴이 4종을 "동일 비율"로 배치 → 어떤 심볼이든 5개 릴에서
# 같은 행에 나올 확률이 균등 → 왼쪽부터 연속 매칭(3/4/5)이 자주 발생.
# skull(꽝)은 비율을 약간 낮게 (15%) — 매칭은 되지만 payout 최소.
const REEL_STRIPS: Array = [
	# 릴0~4 모두 동일 패턴: knight/archer/mage 균등 + skull 약간 적게.
	# 20칸 = knight 6, archer 6, mage 5, skull 3.
	["knight", "archer", "mage", "knight", "archer", "skull", "mage", "knight",
	 "archer", "mage", "knight", "archer", "mage", "knight", "archer", "mage",
	 "knight", "skull", "mage", "skull"],
	["archer", "mage", "knight", "archer", "mage", "knight", "skull", "archer",
	 "mage", "knight", "archer", "mage", "knight", "archer", "skull", "mage",
	 "knight", "archer", "mage", "skull"],
	["mage", "knight", "archer", "mage", "knight", "archer", "mage", "skull",
	 "knight", "archer", "mage", "knight", "archer", "mage", "knight", "skull",
	 "archer", "mage", "knight", "skull"],
	["knight", "archer", "mage", "knight", "skull", "archer", "mage", "knight",
	 "archer", "mage", "knight", "archer", "skull", "mage", "knight", "archer",
	 "mage", "knight", "skull", "mage"],
	["archer", "mage", "knight", "archer", "mage", "knight", "archer", "mage",
	 "skull", "knight", "archer", "mage", "knight", "archer", "mage", "knight",
	 "skull", "archer", "mage", "skull"],
]

# 20 페이라인 패턴 (각 값 = 행 인덱스 0/1/2, 길이 5)
const PAYLINES: Array = [
	[1, 1, 1, 1, 1], [0, 0, 0, 0, 0], [2, 2, 2, 2, 2],
	[0, 1, 2, 1, 0], [2, 1, 0, 1, 2], [0, 0, 1, 2, 2],
	[2, 2, 1, 0, 0], [1, 0, 0, 0, 1], [1, 2, 2, 2, 1],
	[0, 1, 1, 1, 0], [2, 1, 1, 1, 2], [1, 0, 1, 2, 1],
	[1, 2, 1, 0, 1], [0, 1, 0, 1, 0], [2, 1, 2, 1, 2],
	[0, 0, 1, 0, 0], [2, 2, 1, 2, 2], [1, 1, 0, 1, 1],
	[1, 1, 2, 1, 1], [0, 2, 0, 2, 0],
]


func _init() -> void:
	_ensure_dirs()
	var sym := _build_symbols()
	var reels := _build_reels(sym)
	var paylines := _build_paylines()
	var paytable := _build_paytable()
	_build_config(sym, reels, paylines, paytable)
	_build_units()   # Phase 8-C: 유닛 데이터 .tres 생성
	print("[setup] 기본 슬롯 데이터 생성 완료: 심볼 %d, 릴 %d, 페이라인 %d" % [sym.size(), reels.size(), paylines.size()])
	quit()


func _ensure_dirs() -> void:
	for d in [SYMBOL_DIR, REEL_DIR, PAYLINE_DIR, PAYTABLE_DIR, CONFIG_DIR, UNIT_ALLY_DIR, UNIT_ENEMY_DIR]:
		DirAccess.make_dir_recursive_absolute(d)


func _build_symbols() -> Dictionary:
	# Phase 8: 유닛 4종. id -> [kind, display_name, color, shape, payout_3, payout_4, payout_5, unit_id]
	# knight=기사(탱커,파랑), archer=궁수(딜러,초록), mage=마법사(딜러,보라), skull=해골(꽝,회색).
	# payout_3/4/5: 3/4/5매치 당첨 배수. skull은 꽝이라 payout 최소 (매칭은 됨).
	# PackedInt32Array 대신 개별 int (Godot 4.7 모바일 export 직렬화 버그 회피).
	var defs := {
		"knight": [SymbolData.Kind.NORMAL, "Knight", Color(0.25, 0.55, 0.95), SymbolData.Shape.KNIGHT, 6, 20, 60, &"knight"],
		"archer": [SymbolData.Kind.NORMAL, "Archer", Color(0.30, 0.85, 0.45), SymbolData.Shape.ARCHER, 5, 15, 45, &"archer"],
		"mage":   [SymbolData.Kind.NORMAL, "Mage",   Color(0.70, 0.35, 0.95), SymbolData.Shape.MAGE, 8, 25, 80, &"mage"],
		"skull":  [SymbolData.Kind.NORMAL, "Skull",  Color(0.65, 0.65, 0.70), SymbolData.Shape.SKULL, 1, 2, 3, &"skull"],
	}
	var out := {}
	for id in defs:
		var d: Array = defs[id]
		var s := SymbolData.new()
		s.id = StringName(id)
		s.kind = d[0]
		s.display_name = d[1]
		s.color = d[2]
		s.shape = d[3]
		s.payout_3 = d[4]
		s.payout_4 = d[5]
		s.payout_5 = d[6]
		s.unit_id = d[7]
		# 에셋 교체: assets/sprites/{id}_transparent_180.png 가 있으면 texture 로드.
		# null이면 프로시저럴 도형(SymbolView._draw) 폴백. 텍스처 할당 시 자동으로 실제 아트 적용.
		var tex_path := "res://assets/sprites/%s_transparent_180.png" % id
		if ResourceLoader.exists(tex_path):
			s.texture = load(tex_path)
		_save(s, SYMBOL_DIR + id + ".tres")
		out[id] = s
	return out


func _build_reels(sym: Dictionary) -> Array:
	# Phase 8: 4종 유닛만. Bonus/Wild 추가 없음.
	var reels: Array = []
	for i in range(REEL_STRIPS.size()):
		var strip := ReelStrip.new()
		for id in REEL_STRIPS[i]:
			strip.symbols.append(sym[id])
		_save(strip, REEL_DIR + "reel_%d.tres" % i)
		reels.append(strip)
	return reels


func _build_paylines() -> Array:
	var out: Array = []
	for i in range(PAYLINES.size()):
		var pl := Payline.new()
		pl.id = i
		# PackedInt32Array 대신 개별 int로 분해 (모바일 export 직렬화 손실 회피).
		var pattern: Array = PAYLINES[i]
		pl.row_r0 = pattern[0]
		pl.row_r1 = pattern[1]
		pl.row_r2 = pattern[2]
		pl.row_r3 = pattern[3]
		pl.row_r4 = pattern[4]
		pl.debug_color = Color.from_hsv(float(i) / float(PAYLINES.size()), 0.75, 1.0)
		_save(pl, PAYLINE_DIR + "payline_%02d.tres" % i)
		out.append(pl)
	return out


func _build_paytable() -> Paytable:
	# Phase 8: Scatter/Bonus 심볼 제거됨 → 관련 필드는 0/빈 값.
	# 라인 매칭(기사/궁수/마법사)만으로 RTP 형성.
	var p := Paytable.new()
	p.scatter_free_spins_base = 0
	p.scatter_free_spins_per_extra = 0
	p.free_spin_multiplier = 1.0
	p.scatter_credit_mult_base = 0.0
	p.scatter_credit_mult_per_extra = 0.0
	p.bonus_line_jackpot = {}
	_save(p, PAYTABLE_PATH)
	return p


## Phase 8-C: 유닛 데이터 .tres 생성 (에디터 인스펙터로 밸런스 튜닝용).
## 아군 4종(ally/) + 적 3종(enemy/). UnitRegistry 가 이 파일들을 런타임에 로드.
## 밸런스 튜닝 시 이 함수 재실행으로 초기화, 또는 에디터에서 직접 필드 수정.
func _build_units() -> void:
	var ally_count := 0
	var enemy_count := 0
	# --- 아군 4종 ---
	# [id, name, role, hp, atk, interval, spd, range, shape, color, size, exp]
	ally_count += _save_unit(UNIT_ALLY_DIR, "knight", "Knight", UnitData.Role.TANK,
		80, 8, 1.0, 45.0, 55.0, UnitData.Shape.SQUARE, Color(0.25, 0.55, 0.95), 64.0, 0)
	ally_count += _save_unit(UNIT_ALLY_DIR, "archer", "Archer", UnitData.Role.DEALER,
		30, 12, 0.9, 70.0, 120.0, UnitData.Shape.TRIANGLE, Color(0.30, 0.85, 0.45), 56.0, 0)
	ally_count += _save_unit(UNIT_ALLY_DIR, "mage", "Mage", UnitData.Role.DEALER,
		40, 18, 1.1, 60.0, 90.0, UnitData.Shape.DIAMOND, Color(0.70, 0.35, 0.95), 60.0, 0)
	ally_count += _save_unit(UNIT_ALLY_DIR, "minion", "Minion", UnitData.Role.MINION,
		20, 5, 1.0, 55.0, 50.0, UnitData.Shape.CIRCLE, Color(0.6, 0.6, 0.6), 50.0, 0)
	# skull 심볼 매칭 → 미니언과 동일 (별도 파일 없이 UnitRegistry에서 alias).
	# --- 적 3종 ---
	enemy_count += _save_unit(UNIT_ENEMY_DIR, "goblin", "Goblin", UnitData.Role.ENEMY,
		20, 6, 1.0, 50.0, 50.0, UnitData.Shape.CIRCLE, Color(0.8, 0.2, 0.2), 60.0, 1)
	enemy_count += _save_unit(UNIT_ENEMY_DIR, "orc", "Orc", UnitData.Role.ENEMY,
		40, 10, 1.0, 40.0, 60.0, UnitData.Shape.SQUARE, Color(0.7, 0.3, 0.1), 60.0, 3)
	enemy_count += _save_unit(UNIT_ENEMY_DIR, "boss", "Boss", UnitData.Role.ENEMY,
		150, 20, 1.2, 35.0, 80.0, UnitData.Shape.DIAMOND, Color(0.9, 0.1, 0.3), 80.0, 10)
	print("[setup] 유닛 데이터 생성: 아군 %d종, 적 %d종" % [ally_count, enemy_count])


## UnitData 인스턴스 생성 + .tres 저장 헬퍼.
func _save_unit(dir: String, id: String, display_name: String, role: UnitData.Role,
		hp: int, atk: int, interval: float, spd: float, rng: float,
		shape: UnitData.Shape, col: Color, sz: float, exp: int) -> int:
	var u := UnitData.new()
	u.unit_id = StringName(id)
	u.display_name = display_name
	u.role = role
	u.max_hp = hp
	u.attack = atk
	u.attack_interval = interval
	u.move_speed = spd
	u.attack_range = rng
	u.shape = shape
	u.color = col
	u.size = sz
	u.exp_reward = exp
	_save(u, dir + id + ".tres")
	return 1


func _build_config(sym: Dictionary, reels: Array, paylines: Array, paytable: Paytable) -> void:
	var c := SlotConfig.new()
	c.reel_count = 5
	c.row_count = 3
	c.payline_count = 20
	c.base_bet_steps = PackedFloat32Array([10.0, 25.0, 50.0, 100.0, 250.0, 500.0])
	c.default_bet_index = 2
	c.jackpot_contribution_rate = 0.02
	c.jackpot_seed_mini = 1000
	c.jackpot_seed_minor = 5000
	c.jackpot_seed_major = 25000
	c.jackpot_seed_grand = 100000
	c.rng_seed = 0
	c.starting_credit = 10000
	# typed array(Array[ReelStrip] 등)에는 일반 Array 직접 할당 불가 → 명시 변환
	var typed_reels: Array[ReelStrip] = []
	for r in reels:
		typed_reels.append(r)
	c.reels = typed_reels

	var typed_symbols: Array[SymbolData] = []
	for s in sym.values():
		typed_symbols.append(s)
	c.symbols = typed_symbols

	c.paytable = paytable

	var typed_paylines: Array[Payline] = []
	for p in paylines:
		typed_paylines.append(p)
	c.paylines = typed_paylines
	_save(c, CONFIG_PATH)


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("[setup] 저장 실패: %s (err=%d)" % [path, err])
