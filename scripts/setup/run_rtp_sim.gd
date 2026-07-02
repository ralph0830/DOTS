extends Node
## 헤드리스 RTP/히트율 검증 (씬 실행 기반).
## 실행: godot --headless --path <project> res://scenes/setup/SimScene.tscn
## 코어 로직(SlotMachine + SpinEvaluator + WinCalculator)이 뷰 없이 정상 동작하는지 확인.
## 주의: 결과는 멤버 변수 _last_result 에 보관(람다 쓰기 캡처 한계 회피).

const SPIN_COUNT := 20000

var _last_result: SpinResult = null


func _ready() -> void:
	var config: SlotConfig = GameConfig.config
	assert(config != null, "[sim] SlotConfig 로드 실패 — 데이터 생성 스크립트를 먼저 실행하세요.")
	WalletManager.initialize(config)
	JackpotSystem.initialize(config)

	var sm := SlotMachine.new()
	add_child(sm)
	sm.initialize(config)

	# 헤드리스 드라이버: spin_complete 수신 시 5개 릴을 즉시 정지 처리(뷰 대역).
	sm.spin_complete.connect(func(_grid):
		for i in range(config.reel_count):
			sm.on_reel_stopped(i))
	# 결과 수신은 멤버 함수로(람다에서 외부 로컬 변수 쓰기가 반영되지 않기 때문).
	sm.evaluation_completed.connect(_on_eval)

	var total_bet := 0
	var total_win := 0
	var wins := 0
	var big_wins := 0
	var free_spins := 0
	var max_win := 0
	var top_ups := 0

	var match_dist := {3: 0, 4: 0, 5: 0}
	for i in range(SPIN_COUNT):
		if not sm.can_spin():
			WalletManager.add_credit(1_000_000)   # 자금 부족 시 충전(측정에 영향 없음)
			top_ups += 1
		var bet := WalletManager.current_bet
		sm.request_spin()
		total_bet += bet
		if _last_result != null:
			if _last_result.total_win > 0:
				wins += 1
				total_win += _last_result.total_win
				max_win = maxi(max_win, _last_result.total_win)
				if _last_result.is_big_win(bet):
					big_wins += 1
				free_spins += _last_result.free_spins_awarded
				for lw in _last_result.line_wins:
					if match_dist.has(lw.match_count):
						match_dist[lw.match_count] += 1
			_last_result = null

	_print_report(total_bet, total_win, wins, big_wins, free_spins, max_win, top_ups)
	print("매치 분포: 3매치=%d / 4매치=%d / 5매치=%d" % [match_dist[3], match_dist[4], match_dist[5]])
	get_tree().quit()


func _on_eval(r: SpinResult) -> void:
	_last_result = r


func _print_report(total_bet: int, total_win: int, wins: int, big_wins: int, free_spins: int, max_win: int, top_ups: int) -> void:
	var rtp := (float(total_win) / float(total_bet) * 100.0) if total_bet > 0 else 0.0
	var hit := float(wins) / float(SPIN_COUNT) * 100.0
	print("")
	print("========================================")
	print(" 슬롯 RTP / 히트율 시뮬레이션 (%d 스핀)" % SPIN_COUNT)
	print("========================================")
	print("총 베팅:        %d" % total_bet)
	print("총 당첨:        %d" % total_win)
	print("RTP:            %.2f%%" % rtp)
	print("히트율:         %.2f%% (%d/%d)" % [hit, wins, SPIN_COUNT])
	print("빅윈(≥15x벳):   %d회" % big_wins)
	print("최대 당첨:      %d" % max_win)
	print("프리스핀 부여:  %d회 (실제 사용은 Phase 4)" % free_spins)
	print("자금 충전:      %d회" % top_ups)
	print("========================================")
	if rtp < 85.0:
		print("[경고] RTP가 너무 낮음 — 고배당 심볼(dragon/unicorn) 빈도 또는 배수를 올리세요.")
	elif rtp > 105.0:
		print("[경고] RTP가 너무 높음 — 고배당 심볼 빈도/배수를 낮추거나 저배당 빈도를 올리세요.")
	else:
		print("[OK] RTP가 합리적 범위(85~105%%) 내. (목표는 이후 밸런싱으로 92~96%% 튜닝)")
