class_name HUD
extends CanvasLayer
## HUD: 크레딧/베팅/당첨 표시 + 스핀 버튼. EventBus 구독으로 갱신(코어 직접 참조 없음).

var _credit_label: Label
var _bet_label: Label
var _win_label: Label


func _ready() -> void:
	_build_ui()
	EventBus.credit_changed.connect(_on_credit)
	EventBus.bet_changed.connect(_on_bet)
	EventBus.evaluation_completed.connect(_on_eval)
	# 초기 표시
	_on_credit(WalletManager.credit)
	_on_bet(WalletManager.current_bet)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_credit_label = _make_label(root, "CREDIT  0", Vector2(60, 80), 44, Color(1.0, 0.9, 0.3))
	_win_label = _make_label(root, "", Vector2(60, 150), 56, Color(0.5, 1.0, 0.6))
	_bet_label = _make_label(root, "BET  0", Vector2(60, 1790), 40, Color.WHITE)

	# 스핀 버튼(하단 우측, 터치 큼)
	var btn := Button.new()
	btn.text = "SPIN"
	btn.size = Vector2(320, 170)
	btn.position = Vector2(700, 1730)
	btn.add_theme_font_size_override("font_size", 52)
	btn.pressed.connect(func() -> void: EventBus.spin_requested.emit())
	root.add_child(btn)


func _make_label(parent: Control, text: String, pos: Vector2, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func _on_credit(c: int) -> void:
	_credit_label.text = "CREDIT  %d" % c


func _on_bet(b: int) -> void:
	_bet_label.text = "BET  %d" % b


func _on_eval(r: SpinResult) -> void:
	_win_label.text = ("WIN  %d" % r.total_win) if r.total_win > 0 else ""
