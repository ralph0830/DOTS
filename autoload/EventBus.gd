extends Node
## EventBus — 전역 시그널 허브.
## 코어(SlotMachine/Wallet/Jackpot)는 여기 시그널을 emit 하고,
## 뷰/이펙트/오디오는 connect 하여 수신. 직접 참조 대신 느슨한 결합.
## 2026-07-03: 사용처 없는 데드 시그널 정리(celebration_finished, clear_highlights).

# --- 스핀 라이프사이클 ---
signal spin_requested()
signal spin_started(bet: int)
signal spin_complete(grid: Array)              # 5x3 결과 그리드(SymbolData)
signal evaluation_completed(result: SpinResult)

# --- 크레딧 / 베팅 ---
# WalletManager 자체 시그널과 동일 이름 — WalletManager 가 매 emit 시 EventBus 로 forward 한다.
signal credit_changed(credit: int)
signal bet_changed(bet: int)

# --- 자동스핀 ---
signal auto_spin_changed(enabled: bool)

# --- 당첨 시각화 ---
signal highlight_wins(result: SpinResult)      # 당첨 라인/셀 하이라이트 요청
# (clear_highlights 제거 — PaylineOverlay 는 spin_started 구독으로 이미 clear 처리 중.)

# --- 이펙트 트리거 ---
signal big_win(amount: int)
signal free_spins_started(count: int, multiplier: float)
signal free_spins_changed(remaining: int, multiplier: float)
signal free_spins_ended()
signal jackpot_won(tier: int, amount: int)
