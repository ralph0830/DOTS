class_name SlotConfig
extends Resource
## 게임 전체 파라미터와 하위 리소스 참조의 루트 컨테이너.
## 이 리소스 하나로 게임 한 종(그리드/심볼/릴/페이라인/보상)을 통째로 교체 가능.
## 인스턴스는 resources/config/default_slot.tres.

@export var reel_count: int = 5
@export var row_count: int = 3
@export var payline_count: int = 20

# --- 베팅 ---
@export var base_bet_steps: PackedFloat32Array = [10.0, 25.0, 50.0, 100.0, 250.0, 500.0]
@export var default_bet_index: int = 2

# --- 잭팟 누적 풀 ---
@export var jackpot_contribution_rate: float = 0.02   # 베팅의 2%가 잭팟 풀에 누적
@export var jackpot_seed_mini: int = 1000
@export var jackpot_seed_minor: int = 5000
@export var jackpot_seed_major: int = 25000
@export var jackpot_seed_grand: int = 100000

# --- RNG ---
@export var rng_seed: int = 0    # 0 = 실행마다 무작위, 양수 = 재현 가능(검증용)

# --- 하위 데이터 참조 ---
@export var reels: Array[ReelStrip] = []        # reel_count 개의 릴 스트립
@export var symbols: Array[SymbolData] = []     # 전체 심볼 레퍼런스
@export var paytable: Paytable
@export var paylines: Array[Payline] = []       # payline_count 개의 페이라인


## 시작 크레딧(기본값). 실제 영속 크레딧은 WalletManager가 관리.
@export var starting_credit: int = 10000
