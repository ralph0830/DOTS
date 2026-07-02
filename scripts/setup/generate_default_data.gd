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
# 저배당(ruby/sapphire) 자주, emerald 보통, dragon 드물게, unicorn(Wild) 1개, chest(Scatter) 1개.
const REEL_STRIPS: Array = [
	["ruby", "sapphire", "emerald", "ruby", "sapphire", "emerald", "dragon", "ruby", "sapphire", "emerald", "ruby", "sapphire", "unicorn", "ruby", "sapphire", "emerald", "ruby", "sapphire", "dragon", "emerald", "ruby", "sapphire", "chest", "ruby", "emerald", "sapphire", "ruby", "emerald", "sapphire", "ruby"],
	["sapphire", "ruby", "emerald", "sapphire", "emerald", "ruby", "sapphire", "dragon", "ruby", "emerald", "sapphire", "ruby", "emerald", "sapphire", "unicorn", "ruby", "sapphire", "emerald", "ruby", "dragon", "sapphire", "emerald", "ruby", "sapphire", "emerald", "ruby", "sapphire", "chest", "emerald", "ruby"],
	["emerald", "ruby", "sapphire", "emerald", "ruby", "sapphire", "emerald", "ruby", "dragon", "sapphire", "emerald", "ruby", "sapphire", "emerald", "unicorn", "ruby", "sapphire", "emerald", "ruby", "dragon", "sapphire", "emerald", "ruby", "chest", "sapphire", "emerald", "ruby", "sapphire", "emerald", "ruby"],
	["ruby", "emerald", "sapphire", "ruby", "emerald", "dragon", "sapphire", "ruby", "emerald", "sapphire", "ruby", "emerald", "unicorn", "sapphire", "ruby", "emerald", "sapphire", "ruby", "dragon", "emerald", "sapphire", "ruby", "emerald", "chest", "sapphire", "ruby", "emerald", "sapphire", "ruby", "emerald"],
	["sapphire", "emerald", "ruby", "sapphire", "emerald", "ruby", "dragon", "sapphire", "emerald", "ruby", "sapphire", "emerald", "unicorn", "ruby", "sapphire", "emerald", "ruby", "sapphire", "dragon", "emerald", "ruby", "sapphire", "chest", "emerald", "ruby", "sapphire", "emerald", "ruby", "sapphire", "emerald"],
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
	# id -> [kind, display_name, color, shape, payout 배열]
	var defs := {
		"ruby": [SymbolData.Kind.NORMAL, "Ruby", Color(0.86, 0.12, 0.20), SymbolData.Shape.DIAMOND, [0, 0, 0, 4, 12, 30]],
		"sapphire": [SymbolData.Kind.NORMAL, "Sapphire", Color(0.15, 0.36, 0.95), SymbolData.Shape.CIRCLE, [0, 0, 0, 4, 12, 30]],
		"emerald": [SymbolData.Kind.NORMAL, "Emerald", Color(0.10, 0.78, 0.42), SymbolData.Shape.HEX, [0, 0, 0, 5, 15, 40]],
		"dragon": [SymbolData.Kind.NORMAL, "Dragon", Color(0.62, 0.15, 0.78), SymbolData.Shape.STAR, [0, 0, 0, 12, 60, 400]],
		"unicorn": [SymbolData.Kind.WILD, "Unicorn (Wild)", Color(0.95, 0.85, 1.0), SymbolData.Shape.STAR, [0, 0, 0, 12, 60, 400]],
		"chest": [SymbolData.Kind.SCATTER, "Chest (Scatter)", Color(1.0, 0.80, 0.15), SymbolData.Shape.SQUARE, [0, 0, 0, 0, 0, 0]],
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
		_save(s, SYMBOL_DIR + id + ".tres")
		out[id] = s
	return out


func _build_reels(sym: Dictionary) -> Array:
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
	var p := Paytable.new()
	p.scatter_free_spins_base = 8
	p.scatter_free_spins_per_extra = 4
	p.free_spin_multiplier = 2.0
	p.scatter_credit_mult_base = 2.0
	p.scatter_credit_mult_per_extra = 1.0
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
