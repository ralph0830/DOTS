extends Node
## EventBus — 전역 시그널 허브.
## 코어(SlotMachine/Wallet/Jackpot)는 여기 시그널을 emit 하고,
## 뷰/이펙트/오디오는 connect 하여 수신. 직접 참조 대신 느슨한 결합.
## 2026-07-03: 사용처 없는 데드 시그널 정리(celebration_finished, clear_highlights).

# --- 스핀 라이프사이클 ---
signal spin_requested()
signal spin_started(bet: int)
signal spin_complete(grid: Array)              # 5x3 결과 그리드(SymbolData)
signal reel_stopped(reel_index: int)           # 뷰→코어: 릴 정지 보고
signal evaluation_completed(result: SpinResult)
signal state_changed(from: int, to: int)       # 코어→뷰: 코어 상태 전이(IDLE/SPINNING/...)

# --- 크레딧 / 베팅 ---
# WalletManager 자체 시그널과 동일 이름 — WalletManager 가 매 emit 시 EventBus 로 forward 한다.
signal credit_changed(credit: int)
signal bet_changed(bet: int)

# --- 자동스핀 ---
# auto_spin_changed: enabled(bool) + remaining(int). remaining = -1 무한, 0 끔, N 남은 횟수.
signal auto_spin_changed(enabled: bool, remaining: int)

# --- 당첨 시각화 ---
signal highlight_wins(result: SpinResult)      # 당첨 라인/셀 하이라이트 요청
# (clear_highlights 제거 — PaylineOverlay 는 spin_started 구독으로 이미 clear 처리 중.)

# --- 이펙트 트리거 ---
signal big_win(amount: int)
signal free_spins_started(count: int, multiplier: float)
signal free_spins_changed(remaining: int, multiplier: float)
signal free_spins_ended()
signal jackpot_won(tier: int, amount: int)

# --- 전투 / 디펜스 (Phase 7: 토템 스핀 디펜스) ---
signal unit_spawned(unit_id: StringName, count: int)   # 슬롯 매칭 → 유닛 소환
signal enemy_spawned(enemy_id: StringName)             # WAVE → 적 스폰
signal enemy_killed(enemy_id: StringName)              # 적 처치
signal unit_died(unit_id: StringName)                  # 아군 유닛 사망
signal base_damaged(amount: int)                       # 아군 기지 피해
signal base_hp_changed(ally_hp: int, ally_max: int, enemy_hp: int, enemy_max: int)  # 양 기지 HP 동기화
signal wave_started(wave_num: int)                     # WAVE 시작
signal wave_cleared(wave_num: int)                     # WAVE 클리어
signal game_over(victory: bool)                        # 게임 종료 (승리/패배)
# DEBUG: 게임 초기화 완료 (각 매니저 상태를 화면에 표시하기 위함).
signal game_initialized(state: Dictionary)
