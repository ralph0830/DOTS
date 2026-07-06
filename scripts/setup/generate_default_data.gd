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

# 5개 릴 스트립(각 30 심볼). 빈도 = 출현 확률 → RTP/변동성 결정.
# Phase 8: 유닛 4종(knight/archer/mage/skull)만 배치. Wild/Scatter/Bonus 제거.
# 4종끼리만 매칭 → 3매치 확률 ~40% (기존 7종 대비 4배 상승). skull=꽝(매칭은 되나 payout 0).
# 각 릴마다 지배 심볼을 다르게 배치해 5릴 연속 동일 매치(과도한 빅윈)를 억제.
const REEL_STRIPS: Array = [
	# 릴0: knight 지배 + skull 꽝 다수 (탱커 라인)
	["knight", "knight", "skull", "knight", "archer", "knight", "skull", "knight", "mage", "knight", "knight", "skull", "knight", "archer", "knight", "skull", "knight", "knight", "mage", "knight", "skull", "knight", "archer", "knight", "skull", "knight", "knight", "mage", "knight", "skull"],
	# 릴1: archer 지배
	["archer", "skull", "archer", "archer", "knight", "archer", "skull", "archer", "mage", "archer", "skull", "archer", "archer", "knight", "archer", "skull", "archer", "archer", "mage", "archer", "skull", "archer", "knight", "archer", "skull", "archer", "mage", "archer", "skull", "archer"],
	# 릴2: mage 지배 (마법사 라인 — 중앙 릴)
	["mage", "archer", "mage", "skull", "mage", "knight", "mage", "skull", "mage", "mage", "archer", "mage", "skull", "mage", "knight", "mage", "skull", "mage", "archer", "mage", "skull", "mage", "mage", "knight", "mage", "skull", "mage", "archer", "mage", "skull"],
	# 릴3: archer+knight 혼합
	["archer", "knight", "archer", "skull", "knight", "archer", "mage", "skull", "archer", "knight", "archer", "skull", "mage", "knight", "archer", "skull", "knight", "archer", "skull", "mage", "archer", "knight", "skull", "archer", "knight", "mage", "skull", "archer", "knight", "skull"],
	# 릴4: knight+mage 비중 (고배당 5매치 기회)
	["knight", "mage", "knight", "skull", "knight", "archer", "mage", "knight", "skull", "knight", "mage", "archer", "knight", "skull", "mage", "knight", "archer", "skull", "knight", "mage", "knight", "skull", "mage", "archer", "knight", "skull", "knight", "mage", "archer", "skull"],
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
	print("[setup] 기본 슬롯 데이터 생성 완료: 심볼 %d, 릴 %d, 페이라인 %d" % [sym.size(), reels.size(), paylines.size()])
	quit()


func _ensure_dirs() -> void:
	for d in [SYMBOL_DIR, REEL_DIR, PAYLINE_DIR, PAYTABLE_DIR, CONFIG_DIR]:
		DirAccess.make_dir_recursive_absolute(d)


func _build_symbols() -> Dictionary:
	# Phase 8: 유닛 4종. id -> [kind, display_name, color, shape, payout 배열, unit_id]
	# knight=기사(탱커,파랑), archer=궁수(딜러,초록), mage=마법사(딜러,보라), skull=해골(꽝,회색).
	# payout: [0,0,0, 3매치, 4매치, 5매치]. skull은 꽝이라 payout 0 (매칭은 됨).
	# unit_id: 매칭 시 소환할 유닛. skull은 소환 없음(빈 문자열) → UnitSpawner가 꽝 보정 미니언.
	# Phase 8 밸런스: 4종 축소로 히트율 ~47%. payout 배수 조정으로 RTP 92~96% 목표.
	var defs := {
		"knight": [SymbolData.Kind.NORMAL, "Knight", Color(0.25, 0.55, 0.95), SymbolData.Shape.KNIGHT, [0, 0, 0, 25, 80, 250], &"knight"],
		"archer": [SymbolData.Kind.NORMAL, "Archer", Color(0.30, 0.85, 0.45), SymbolData.Shape.ARCHER, [0, 0, 0, 20, 60, 180], &"archer"],
		"mage":   [SymbolData.Kind.NORMAL, "Mage",   Color(0.70, 0.35, 0.95), SymbolData.Shape.MAGE,   [0, 0, 0, 30, 100, 350], &"mage"],
		"skull":  [SymbolData.Kind.NORMAL, "Skull",  Color(0.65, 0.65, 0.70), SymbolData.Shape.SKULL,  [0, 0, 0, 1, 2, 3], &"skull"],
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
		s.payout = PackedInt32Array(d[4])
		s.unit_id = d[5]
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
		pl.row_per_reel = PackedInt32Array(PAYLINES[i])
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
