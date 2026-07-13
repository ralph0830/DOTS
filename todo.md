# DOTS — 모바일 세로 슬롯머신 개발 TODO

> Godot 4.7 + GDScript · 세로 1080×1920 · 5릴 × 3행 / 20라인 · **토템 스핀 디펜스**(파타폰 실루엣 + 뱀서식 3지선다 + 단일 라인 디펜스)
> **설계 철학**: open-structure(데이터 주도 + EventBus 느슨한 결합 + 플러그인 체인) — 새 심볼·평가 규칙·이펙트를 **코어 수정 없이** 추가 가능.

---

## 0. 기술 스택 & 환경

| 항목 | 값 |
|---|---|
| 엔진 | Godot 4.7 stable (winget 설치) |
| 언어 | GDScript |
| 렌더러 | gl_compatibility (모바일 호환) |
| 해상도 | 세로 1080×1920 (stretch 모드) |
| Godot exe | `C:\Users\RalphPark\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64.exe` |
| git bash | `/c/Users/RalphPark/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7-stable_win64.exe` |
| 원격 저장소 | https://github.com/ralph0830/DOTS.git |

---

## 1. 아키텍처 (5 레이어 + open-structure)

```
Data    (scripts/data/, resources/*.tres)  — Resource 기반 정적 데이터. 코딩 없이 튜닝.
Core    (scripts/core/)                    — 뷰无关 순수 로직. 헤드리스 검증 대상.
View    (scripts/view/, scenes/slot/)      — 씬/렌더링. EventBus 구독 갱신.
Effects (scripts/effects/)                 — 파티클/셰이더/Tween/진동 연출.
Systems (scripts/systems/ + autoload)      — 보너스·잭팟·지갑·오디오 전역 상태.
```

**통신 규칙**: 코어 ↔ 뷰/이펙트/오디오는 직접 참조 대신 `EventBus` 시그널만.

**open-structure 확장점**:
- `EvaluationPass` 체인 — 새 평가 규칙 플러그인 (`WinCalculator.default_passes`).
- `SymbolMechanic` — 새 심볼 메카닉 (`for_kind()` 팩토리). `SymbolData.tres`의 `mechanic` 필드 할당으로 코어 수정 0.
- `SlotMachine.add_result_modifier(Callable)` — 결과 후처리 훅(프리스핀 배수·잭팟 반영).

**autoload 순서** (`project.godot`): GameConfig → EventBus → WalletManager → JackpotSystem → AudioManager → GameManager → ParticleBudget → SlowMotion → BonusManager.

---

## 2. 완료된 작업 (Phase 1 ~ Phase 5)

### ✅ Phase 1 — 코어 스핀 (헤드리스 검증)
- **데이터 모델** (`scripts/data/`):
  - `SymbolData.gd` — id/kind(NORMAL·WILD·SCATTER·BONUS)/display_name/color/shape/payout/texture(교체 포인트)/mechanic.
  - `ReelStrip.gd` — symbols(중복=가중치), random_start_index(rng).
  - `Payline.gd` — id/row_per_reel/debug_color.
  - `Paytable.gd` — 라인 지불 + scatter 보상(free_spins/multiplier) + 잭팟 트리거.
  - `SlotConfig.gd` — 루트 컨테이너. `resources/config/default_slot.tres` 1개로 게임 통째 교체.
  - `SpinResult.gd` — total_win/line_wins/scatter_win/free_spins_awarded/jackpot_tier/winning_positions.
  - `SymbolMechanic.gd` + `mechanics/` — 평가 위임(participates_in_line/can_be_line_target/is_substitutable/matches).
- **코어 로직** (`scripts/core/`):
  - `SlotMachine.gd` — 상태머신(IDLE→SPINNING→STOPPING→EVALUATING). 프리스핀 베팅 우회, 평가 순서(emit→add_win), jackpot_won emit.
  - `SpinEvaluator.gd` — 단일 페이라인 평가. 왼쪽부터 연속 매치, mechanic 위임(kind 하드코딩 없음).
  - `WinCalculator.gd` — 평가 오케스트레이터. default_passes = [Line, Scatter, Jackpot].
  - `EvaluationPass.gd` + `passes/LineEvaluationPass.gd` + `passes/ScatterEvaluationPass.gd`.
- **autoload**: EventBus, GameConfig, WalletManager(영속 user://wallet.save), JackpotSystem, AudioManager.
- **검증**: 헤드리스 N회 스핀 → RTP/히트율/잔액보존 어설트 통과.

### ✅ Phase 2 — 시각 파이프라인
- `SymbolView.gd` — `_draw()` 프로시저럴 도형/색상. texture != null 시 자동 교체.
- `ReelView.gd` — 무한 스크롤(_physics_process) + 감속 tween(TWEEN_PROCESS_PHYSICS). POOL_SIZE=4(ROWS+1 버퍼). stop_at에서 pool[1..ROWS] 미리 배치 → _cycle_one 후 자연 착지(점프 없음).
- `SlotMachineView.gd` — 코어-뷰 중개. 빅윈 시 릴 영역 진동. 당첨 심볼 하이라이트.
- `HUD.gd`(초기) — 크레딧/베팅/당첨 + SPIN 버튼.
- `PaylineOverlay.gd` — 당첨 Line2D 동적 생성.
- **검증**: 임포트/컴파일 에러 0.

### ✅ Phase 3 — 이펙트 스택 (병렬 에이전트 팀)
- `WinEffects.gd` — 당첨 폭발 파티클(GPUParticles2D).
- `ParticleBudget.gd` (autoload) — 총 활성 한도(기본 400), 디바이스 티어별 자동 축소.
- `FloatingText.gd` — 당첨금 롤업 카운트.
- `CameraShake.gd` / `SlowMotion.gd` (autoload) — 진동/슬로우모션(CameraShake는 현재 미사용).
- `BackgroundFX.gd` — CanvasItem 셰이더(시간기반 색/UV).
- 전부 EventBus 구독, `_physics_process`/`TWEEN_PROCESS_PHYSICS`(헤드리스 대응).
- **검증**: 캡처 스크립트 + analyze_image로 화려함 확인.

### ✅ Phase 4 — 보너스/잭팫 (병렬 에이전트 팀) — 커밋 `bf251fe`
- `BonusManager.gd` (autoload) — 프리스핀 카운터/멀티플라이어/재트리거. is_free_spin/award/consume_one.
- `JackpotEvaluationPass.gd` — BONUS(rune) 심볼 왼쪽부터 연속 카운트 → `bonus_line_jackpot={5:GRAND}` 트리거.
- `JackpotFX.gd` + `JackpotOverlay.tscn` — 잭팟 전체화면 연출.
- 코어 통합: SlotMachine 프리스핀 베팅 우회(`_is_free_spin`) + 평가 순서(emit→add_win) + `jackpot_won` emit.
- BONUS 룬 심볼 추가(각 릴 1개).
- **당첨 라인 4·5매치 버그 조사 → 버그 아님 확증**: 코어 `SpinEvaluator`가 positions에 4-5개 정상 추가. 4·5매치 강제 캡처 + analyze_image로 선이 4·5개 릴 가로지름 확인. → PaylineOverlay 가시성 강화(라인별 고유 `debug_color`/width 16/z_index 10).

### ✅ Phase 5 — 폴리싱/밸런싱 — 커밋 `50e726a`
- **#12 RTP/히트율 밸런싱** (balancer 에이전트 + 메인 정밀 재검증):
  - **비대칭 릴 분포**(릴0 ruby / 릴1 sapphire / 릴2 emerald / 릴3 혼합 / 릴4 emerald 지배) → 동일 심볼 5릴 연속 매치 급감 → **히트율 87%→~32%**.
  - dragon(고배당) 모든 릴에 균등 3~4개 배치 + unicorn(WILD) 동급 배수 동기화.
  - 최종 payout: ruby/sapphire `[0,0,0,6,20,60]`, emerald `[0,0,0,9,30,100]`, dragon/unicorn `[0,0,0,30,345,2350]`.
  - 100,000스핀 평균 **RTP ~95.2%**(92.77~97.69), 히트율 ~32% → 92~96% 밴드 내(유일한 조합).
- **#14 모바일 SafeArea/터치**:
  - HUD Container 기반 재작성. `DisplayServer.get_display_safe_area()`를 design 해상도 비율로 환산해 offset 적용(노치/홈 인디케이터 대응).
  - 하단 2행(베팅 ±/AUTO / SPIN). 터치 버튼 120px+.
- **#15 자동스핀**:
  - EventBus `auto_spin_changed` 시그널. SlotMachineView `_maybe_auto_spin()`(IDLE + 자금/프리스핀 가드). 평가 후 0.9초 연쇄, 자금 부족 시 자동 정지, 프리스핀도 자동 연쇄. 5스핀 연쇄 검증 통과.

### 커밋 히스토리
```
50e726a feat: Phase 5 밸런싱 + 모바일 SafeArea + 자동스핀
bf251fe feat: Phase 4 보너스/잭팫 시스템 + 당첨 라인 가시성 개선
e1ec34c feat: DOTS 슬롯머신 Phase 1-3 (코어/뷰/이펙트)
```

---

## 2.5. 프로젝트 테스트 결과 (2026-07-03 검증)

> Phase 5 완료 후 전수 테스트 재실행. 환경: Godot 4.7 stable (5b4e0cb0f), Windows.

### 임포트 / 컴파일 검증
- `godot --headless --import` → **exit 0, 에러/경고 0건** ✅
- 전체 GDScript 43개 파일(약 3,194줄) 정상 파싱, autoload 9개 정상 등록.

### RTP/히트율 시뮬레이션 (20000스핀 × 2회)

| 런 | 사전 조건 | RTP | 히트율 | 빅윈 | 최대 당첨 | 잭팟 발생 |
|---|---|---|---|---|---|---|
| 누적 save(이전) | `jackpot.save` 그대로 | **102.77%** ⚠️ | 32.70% | 212 | **100000** | GRAND 1회+ |
| **RUN 1** (save 클리어) | `jackpot.save`/`wallet.save` 삭제 | **93.73%** ✅ | 32.10% | 203 | 11930 | 없음 |
| **RUN 2** (save 클리어) | 동일 | **92.79%** ✅ | 32.63% | 203 | 11998 | 없음 |

**결론**: 순수 라인/스캐터 RTP는 **92.8~93.7% 밴드**(목표 92~96% 내). 두 런 편차 ±0.94%p로 안정적.

### 🚨 신규 발견 버그: 잭팟 save 파일이 시뮬레이션을 왜곡

**현상**: `jackpot.save`가 누적된 상태에서 시뮬 돌리면 GRAND 풀(100000)이 1회 지급되어 **RTP가 +9%p 왜곡**(93% → 102%).

**근본 원인** (`scripts/autoload/JackpotSystem.gd:25-37` `initialize()`):
- `initialize()`가 `pools[i] < _seeds[i]`일 때만 시드로 리셋 → 저장된(누적된) 풀을 그대로 유지.
- 시뮬/밸런싱 시 이전 실행의 누적 풀이 새 시뮬에 섞여 들어감.
- 게임 플레이에서는 의도된 동작(영속 잭팟)이나, **검증 시에는 치명적**: 측정마다 결과가 달라져 밸런스 회귀 감지 불가.

**대응 방안** (단기 TODO로 이관):
- 시뮬 스크립트(`run_rtp_sim.gd`) 시작 시 `JackpotSystem._reset_to_seeds()` 호출로 매 측정 동일 초기상태 보장.
- 또는 `SlotConfig.rng_seed`와 병행해 "검증 모드" 플래그 도입(save 무시).

### GUI 캡처 테스트
- `captures/` 폴더에 기존 캡처 존재(spin_1/2.png, match_4/5.png, auto_1~5.png — Phase 4/5에서 생성).
- 헤드리스 실행 시 타임아웃(GUI 렌더링 불가 → todo.md 기존 기재 "헤드리스 검증 한계"와 일치). 뷰/타이밍은 에디터 실행으로만 검증 가능.

---

## 2.6. open-structure 감사 결과 (2026-07-03)

> AGENTS.md에 명시된 3가지 확장점 + EventBus 결합도 전수 조사 (병렬 에이전트 2개 수행).

### 확장점 평가

| 확장점 | 상태 | OCP | 핵심 증거 | 발견 이슈 |
|---|---|---|---|---|
| **A. EvaluationPass 체인** | ✅ 완료 | 만족 | `WinCalculator.gd:41-42` 제네릭 루프, `EvaluationPass.gd:12` 단일 인터페이스, 3패스 정확 구현 | ⚠️ `JackpotEvaluationPass.gd:42-45`가 `JackpotSystem` 전역 상태 직접 소비(코어 격리 부분 위반) |
| **B. SymbolMechanic 플러그인** | ✅ 완료 | 만족 | `SpinEvaluator.gd`에 `Kind` 분기 **0건**, 4개 위임 메서드(`SymbolData.gd:43-58`), `effective_mechanic()` 폴백 | ⚠️ `.tres` 7개 중 **0개**가 `mechanic` 필드 사용 → 확장점 선언됐으나 실증 없음 |
| **C. result_modifier 훅** | ⚠️ 부분 | N/A | 정의/실행은 정확(`SlotMachine.gd:34-36,92-94`), 시점도 명세 일치 | 🚨 **등록 호출자 0건(데드 훅)**; `BonusManager._on_eval` EventBus 경로가 실질적 후처리 단독 담당 → 기능 중복 |

### EventBus 시그널 생태계

- **사용중 시그널**(9): `spin_requested`, `spin_started`, `evaluation_completed`, `auto_spin_changed`, `highlight_wins`, `big_win`, `free_spins_changed`, `free_spins_ended`, `jackpot_won`
- 🚨 **데드 시그널**(2): `celebration_finished`(emit/구독 둘 다 없음), `clear_highlights`(구독자만, emit 없음 → orphan)
- ⚠️ **연결 끊김**(2): `credit_changed`, `bet_changed` — `WalletManager`가 자체 시그널만 emit하고 EventBus로 forward 안 함 → HUD가 `_ready()`에서 직접 `WalletManager.credit` 읽기로 우회 중
- ⚠️ **EventBus 채널 미사용**(1): `free_spins_started` — `BonusManager`가 emit하나 구독자 없음(HUD는 `free_spins_changed`만 구독)
- 📝 **중복 emit**: `SlotMachine`이 자체 시그널 + EventBus 시그널 동시 emit(`spin_started/spin_complete/evaluation_completed`) — 자체 채널은 setup 테스트만 사용

### 레이어 분리 / 결합도

✅ **레이어 분리 규칙 100% 준수**:
- `scripts/core/` → view/effects/systems 직접 참조 **0건**
- view/effects/systems → 코어 `new()`/직접 호출은 `SlotMachineView`(명시 예외)와 setup 테스트만
- autoload 9개 정적 상호참조 **0건** → 초기화 순서 의존성/순환 참조 제로

⚠️ **느슨한 결합 일관성 미흡**:
- 지갑/베팅 도메인이 autoload 직접 접근으로 우회(`HUD.gd:96,112`가 `WalletManager.change_bet` 직접 호출 → `bet_changed` 시그널이 있음에도 EventBus 안 거침)
- `BonusManager`의 "자체 시그널 + EventBus forward" 이중 emit이 모범 패턴(`BonusManager.gd:48-66`) — `WalletManager`/`JackpotSystem`은 forward 누락

### 📝 정리 대상(dead code)

| 항목 | 위치 | 상태 |
|---|---|---|
| `CameraShake.gd` (116줄) | `scripts/effects/` | 구현 완료但 씬에 인스턴스화 0건 → `SlotMachineView._on_big_win` 인라인 tween과 기능 중복 |
| `AudioManager.gd` SFX 풀 | `autoload/` | `_sfx_pool` 비어있음 → `play_sfx`/`register_stream` 호출 0건 (#13 대기) |
| `GameManager.gd` | `autoload/` | 점수/일시정지 로직 → 슬롯 도메인 무관 boilerplate |
| `result_modifier` 훅 | `SlotMachine.gd:34-36` | 등록 호출자 0건 → 데드 훅 |
| 미사용 시그널 4종 | EventBus/JackpotSystem/SlotMachine | `celebration_finished`, `clear_highlights`(orphan), `pool_changed`, `state_changed` |

**총평**: 구조적 레이어 분리 목표는 사실상 완수. 단 EventBus를 유일 통신 채널로 만드는 일관성 목표가 부족(지갑 도메인 우회 + 데드 시그널 4종). 잭팟 save 왜곡 버그와 함께 **검증 신뢰성 + 코드 위생** 측면의 정리가 다음 우선순위.

---

## 3. 향후 TODO — 토템 스핀 디펜스 확장

> **2026-07-06: 슬롯머신 MVP(Phase 1~6) 완성 → GDD 기반 디펜스 게임으로 확장 결정.**
> GDD(`GDD.md`): 파타폰 실루엣 아트 + 뱀서식 3지선다 로그라이크 + 단일 라인 디펜스.
> 슬롯 코어(EventBus + EvaluationPass + SymbolMechanic)는 그대로 재사용, 전투/디펜스 계층 신규 구축.

### 📊 재사용 매핑 요약

| 계층 | 재사용 | 신규 |
|---|---|---|
| 슬롯 코어 (`scripts/core/`) | ✅ EvaluationPass 체인, SymbolMechanic, WinCalculator | 유닛 소환 Pass, 꽝 보정 Pass |
| 데이터 (`scripts/data/`) | ✅ ReelStrip, SymbolData(texture/mechanic) | UnitData, LevelUpChoice |
| 뷰 (`scripts/view/`) | ✅ ReelView(무한스크롤), SymbolView(실루엣 texture) | BattleFieldView, LevelUpUI, HUD 재설계 |
| 이펙트 (`scripts/effects/`) | ✅ WinEffects, SlowMotion, FloatingText, JackpotFX, ParticleBudget | 눈동자 애니메이션, 토템 연출 |
| autoload | ✅ EventBus(확장), AudioManager(SFX 추가), WalletManager(영혼/골드) | GameManager(WAVE/런), ArtifactManager, MetaProgression |

---

### 🎨 모바일 세로형 상하 분할 (1080×1920) — Phase 7 구현 상태

```
┌─────────────────────────────────────┐  ← SafeArea top (y=0)
│  WAVE 3   기지████░░   영혼●●●  토템│  상태바 (Phase 8 추가 예정)
├─────────────────────────────────────┤
│                                     │
│  ▣ 아군기지 (HP 100/100)            │
│  ▣▣▶ ▶▶ ▶ ═══전투═══ ◀◀ ◀ ◀▣▣   │  전투 필드 (55% = 1056px, y=0~1056)
│       ▶▶    (frontline)   ◀◀      │  단일 라인, 좌→우 진격 ✅ 구현됨
│  ▣▣▶         ⚡낙뢰         ◀▣    │
│                                     │
│  ─────── 피버 ▓▓▓░░░ ──────       │  (Phase 8-G 추가 예정)
├─────────────────────────────────────┤  ← 분할선 (y=1056)
│  CREDIT 10000  BET 50  WIN 0    ⚙  │  정보 바 ✅ 구현됨
│        ┌───┬───┬───┬───┬───┐        │
│  🎰   │🛡 │🏹 │🧙 │💀 │🛡 │        │  슬롯 영역 (45% = 864px, y=1056~1920)
│  토템 │🛡 │🏹 │🧙 │💀 │🛡 │  5릴   │  5릴 × 3행 ✅ 구현됨 (심볼 4종)
│  눈👁️ │🛡 │🏹 │🧙 │💀 │🛡 │        │
│        └───┴───┴───┴───┴───┘        │
│  [-] [+]                [AUTO]      │  하단 컨트롤 ✅ 구현됨
│                    [SPIN]           │
└─────────────────────────────────────┘  ← SafeArea bottom (y=1920)

[3지선다 모달 — 레벨업시만 풀스크린 오버레이] (Phase 8-B)
  ┌─────┐  ┌─────┐  ┌─────┐
  │ 🛡️  │  │ 🏹  │  │ ⚡  │   각 240×360px 터치 카드
  │방패병│  │창병  │  │유물  │   JackpotFX 오버레이 패턴 재사용
  └─────┘  └─────┘  └─────┘
```

---

### 🔴 Phase 7 — 프로토타입 1: 슬롯 & 라인전 검증 (MVP) ✅ 완료

> 목표: 슬롯 스핀 → 유닛 소환 → 단일 라인 전투 루프 검증 (더미 실루엣).
> **2026-07-07 완료** — 슬롯 심볼 4종(기사/궁수/마법사/해골) 재설계 + 모바일 직렬화 버그 2종 해결.

- [x] **P7-1 유닛 엔티티** (`scripts/battle/Unit.gd` + `UnitData.gd`) ✅
  - Area2D 기반. 체력/공격력/이동속도/사거리. 아군(좌→우)/적(우→좌) 진격.
  - `UnitData.gd` (Resource): `unit_id`, `role`(TANK/DEALER/SUPPORTER/MINION/ENEMY), 스탯, shape/color/size(프로시저럴 도형).
  - `SymbolData`에 `unit_id` 필드 추가 → 매칭 시 해당 유닛 소환.
- [x] **P7-2 라인 디펜스 필드** (`scripts/battle/BattleField.gd`) ✅
  - Node2D. 단일 레인. 아군 기지(좌단) / 적 포탈(우단).
  - 유닛 충돌 시 전투 해상(area_entered). 양 기지 체력 시스템(base_hp/enemy_base_hp).
- [x] **P7-3 유닛 생산 파이프라인** (`scripts/battle/UnitSpawner.gd`) ✅
  - `EventBus.evaluation_completed` 구독 → SpinResult 매칭 결과를 유닛 소환으로 변환.
  - `SymbolData.unit_id` → UnitData 인스턴스화. 매칭 수 비례 소환량(3매치=1기, 4=2, 5=3).
  - **꽝(Miss) 보정**: 매치 0개 시 최소 미니언 1기 소환 (GDD 핵심).
- [x] **P7-4 적/WAVE 시스템** (`scripts/battle/WaveManager.gd`) ✅
  - WAVE별 적 스폰 타이밍/종류/수. 적 포탈에서 스폰.
  - 적 3종(goblin/orc/boss). 5WAVE마다 보스. WAVE 번호 비례 적 수 증가.
- [x] **P7-5 유닛 전투 AI** (`scripts/battle/Unit.gd`) ✅
  - Area2D 간 area_entered 감지 → 타겟 지정 → 사거리 내 공격 / 전방 이동.
  - 사망 시 died 시그널 + queue_free. EventBus.enemy_killed/unit_died emit.
- [x] **P7-6 레이아웃 전환** — `SlotMachineView` 상단/하단 분할 배치. ✅
  - 상단 전투 55%(1056px) / 하단 슬롯 45%(864px).
  - HUD 재설계: CREDIT/BET/WIN 정보 바(릴 아래) + SPIN/BET±/AUTO 버튼.
- [x] **P7-7 EventBus 확장** — 전투 시그널 9종 추가. ✅
  - `unit_spawned`, `enemy_spawned`, `enemy_killed`, `unit_died`, `base_damaged`,
    `base_hp_changed`, `wave_started`, `wave_cleared`, `game_over`, `game_initialized`.
- [x] **P7 테스트**: 스핀→유닛 소환→라인전 루프 캡처 검증. 기지 파괴/방어 시나리오. ✅

#### 🐛 Phase 7 해결된 주요 버그

| 버그 | 원인 | 해결 | 커밋 |
|---|---|---|---|
| **유닛 전투 미동작** | Area2D 간 감지를 body_entered로 시도 (PhysicsBody2D 전용) | area_entered/area_exited + monitorable/monitoring 활성화 + 사거리 기반 충돌 영역 | `518a5ab` |
| **승리 루프** | WaveManager 첫 WAVE 시작 조건 누락 → 적 스폰 안 됨 → 아군이 적 기지 무조건 파괴 | WAVE 시작 조건 2분할 (첫 WAVE: 타이머≥0, 다음 WAVE: 타이머≥DURATION) | `cf68750` |
| **초기화 안 됨** | 각 매니저가 제각각 _ready 초기화 + 저장값 로드 | `_initialize_all()` 통합 (credit 10000, HP 100/100, WAVE 리셋, 자동스핀 끔) | `0915e3b` |
| **모바일 매칭 0% (치명적)** | Godot 4.7에서 `@export PackedInt32Array`가 Resource 바이너리 export 시 빈 배열로 직렬화 손실 → payout/payline 데이터가 모바일에서 0/빈 값 로드 | **3곳 모두 개별 int 필드로 분해**: `SymbolData.payout_3/4/5`, `Payline.row_r0~r4` | `7c53931` + Claude Code |
| **mechanic 모바일 로딩 실패** | `SymbolMechanic.for_kind()`가 class_name lazy 참조 → 모바일 APK 런타임 첫 호출 시 서브클래스 미로드 → 잘못된 폴백 | preload 강제 로드 + 무상태 싱글톤 레지스트리 패턴 + `get_tags()` 태그 조회(`is X` 타입 체크 대체) | Claude Code |

#### 📊 Phase 7 밸런스 (5000스핀 시뮬)

| 항목 | 값 | 비고 |
|---|---|---|
| 심볼 | 4종 (knight/archer/mage/skull) | 보석 7종 → 유닛 4종 축소 |
| 히트율 | 83.82% | 4종 균등 배치 (각 릴 knight 6/archer 6/mage 5/skull 3) |
| RTP | 94.58% | 목표 92~96% 달성 |
| payout | knight[6,20,60] archer[5,15,45] mage[8,25,80] skull[1,2,3] | skull=꽝(최소 payout) |
| 매치 분포 | 3매치 5136 / 4매치 1448 / 5매치 532 | 균형 |

### 🟡 Phase 8 — 프로토타입 2: 3지선다 빌드업 검증 (PRD §3.3, GDD §4)

> 목표: 뱀서식 3지선다로 기하급수적 성장 카타르시스 검증.
> **PRD 기준**: 성주 알베르트 1명 구현, 영혼 게이지 → 3지선다 주술 카드 → 릴 개조/유물/유닛 진화.

#### P8-A 영혼 게이지 & 레벨업 트리거 ✅ 완료 (2026-07-07)
- [x] **P8-A1 영혼 게이지 시스템** (`scripts/systems/SoulGauge.gd` autoload) ✅
  - 적 처치 시 영혼(EXP) 획득 — `EventBus.enemy_killed(enemy_id, exp_reward)` 시그널 페이로드 확장.
  - 게이지 임계값: `10 + level*5` (Lv1=15, Lv2=20...) — 로그라이크 표준 레벨 비례 곡선.
  - 100% 도달 시 `level_up_available` emit + `_level_up_pending` 가드 (중복 레벨업 방지).
  - GameManager.score(점수)와 soul(EXP)/level(레벨) 분리 — 단일 책임 원칙.
- [x] **P8-A2 EventBus 시그널 3종 추가** ✅
  - `soul_changed(value, maximum, level)` — HUD 게이지바 갱신용.
  - `level_up_available(level)` — LevelUpUI(Phase 8-B) 표시 트리거.
  - `level_up_completed(new_level)` — 선택지 적용 후 게임 재개.
- [x] **P8-A3 데이터 확장** ✅
  - `UnitData.exp_reward` 필드 추가 (개별 int — 모바일 직렬화 안전).
  - WaveManager 적 데이터에 exp_reward 세팅 (goblin=1, orc=3, boss=10).
- [ ] **P8-A4 레벨업 일시정지 처리** — LevelUpUI 표시 중 `get_tree().paused` + `PROCESS_MODE_WHEN_PAUSED`. (Phase 8-B에서 구현)

##### P8-A 검증 (데스크톱, 2026-07-07)
- 임포트 PASS (에러 0)
- RTP 시뮬: 99.46% (코어 영향 0 — 영혼 게이지는 평가 로직에 간섭 안 함)
- 캡처: 초기화 `soul=0/15 lv1` 정상, 적 처치 시 `EXP +1 → soul=1/15...` 누적 확인 ✅

#### P8-B 3지선다 주술 카드 UI (`scripts/view/LevelUpUI.gd`) ✅ 완료 (2026-07-07)
- [x] **P8-B1 카드 오버레이** — GameOverOverlay 패턴 재사용 (Control + z_index=100 + MOUSE_FILTER_STOP). 3장 카드 280×420px 터치. ✅
- [x] **P8-B2 카드 생성 로직** — `LordState.roll_choices(3)` 에서 무작위 3장 추출. `can_choose()` 필터링 (만렙 제외). ✅
- [x] **P8-B3 카드 터치 처리** — 선택 시 `ChoiceEffect.apply(lord)` 실행 → 게임 재개. ✅
- [x] **P8-B4 레벨업 일시정지** — `level_up_available` 수신 시 `get_tree().paused = true`. LevelUpUI는 `PROCESS_MODE_WHEN_PAUSED`로 동작. ✅

##### P8-B 아키텍처 (open-structure)
- **ChoiceEffect** (`scripts/data/ChoiceEffect.gd`, Resource 베이스) — EvaluationPass 패턴. `apply(lord)`/`can_choose(lord)` 메서드. 서브클래싱으로 새 효과 추가.
- **구체 ChoiceEffect 3종** (`scripts/data/effects/`):
  - `UnitEvolutionEffect` — 기사/방패병 티어 +1 (알베르트 선택지 1).
  - `MissCompensationEffect` — 꽝 보정 강화 +1 (선택지 2).
  - `DefenseArtifactEffect` — 수비형 유물 획득 (선택지 3, spike_barricade/magic_shield).
- **LevelUpChoice** (`scripts/data/LevelUpChoice.gd`, Resource) — 카드 메타(id/표시명/설명/아이콘 색상) + effect 필드.
- **LordState** (`scripts/systems/LordState.gd`, autoload) — 성주 강화 상태 추적 + 선택지 풀 관리. ChoiceEffect.apply()의 적용 대상.
- **LevelUpUI** (`scripts/view/LevelUpUI.gd`) — 3카드 HBox 레이아웃. 터치 시 효과 적용 + `SoulGauge.complete_level_up()` 호출.

##### P8-B 검증 (데스크톱, 2026-07-07)
- 임포트 PASS (에러 0)
- 캡처 (임계치 3으로 임시 낮춤): 게이지 100% → `[SoulGauge] 레벨업 가능!` → `[LevelUpUI] 카드 3장: ["가시 바리케이드", "유닛 체급 진화", "마력 보호막"]` ✅
- 일시정지 정상 동작 (게임 멈춤, UI 표시됨) ✅

#### P8-C 선택지 데이터/플러그인 구조 (`scripts/data/LevelUpChoice.gd`) ✅ 완료 (2026-07-07)
- [x] **P8-C1 ChoiceEffect 플러그인 인터페이스** (`scripts/data/ChoiceEffect.gd`) — EvaluationPass 패턴. `apply(lord)`/`can_choose(lord)` 메서드. ✅
- [x] **P8-C2 선택지 카테고리 3종** (PRD §3.3 알베르트 기준): ✅
  - **유닛 체급 진화** (`UnitEvolutionEffect`) — 기사/방패병 티어 업.
  - **꽝 보정 강화** (`MissCompensationEffect`) — 미니언 마리수 증가.
  - **수비형 유물** (`DefenseArtifactEffect`) — 가시 바리케이드, 마력 보호막.
- [ ] **P8-C3 선택지 풀 데이터화** — `resources/choices/*.tres` (향후 성주별 풀 분리).
- [x] **P8-C4 UnitRegistry autoload** (`scripts/systems/UnitRegistry.gd`) — 아군/적 UnitData 중앙 관리. ✅
  - UnitSpawner/WaveManager 하드코딩 데이터 제거, UnitRegistry 조회로 통합.
  - LordState 티어업 연동: `get_ally_unit()` 호출 시 티어 반영 스탯 반환 (HP +30%/atk +20% per tier).
  - **Phase 8-C+: UnitData .tres 파일화** — `resources/units/{ally,enemy}/*.tres` (에디터 인스펙터로 밸런스 튜닝). 코드 생성 폴백 내장.
- [x] **P8-C5 슬롯 보상 분리** — `SlotMachine._evaluate()`에서 `WalletManager.add_win()` 제거. ✅
  - 슬롯은 순수 유닛 생산 수단 (PRD/GDD 정합).
  - CREDIT는 스핀 베팅 비용(place_bet)으로만 감소.
  - WalletManager에서 total_won/add_win 제거 (도박 잔재 정리).
- [x] **P8-C6 유닛 관리 EditorPlugin** (`addons/unit_manager/`) ✅ (2026-07-07)
  - **EditorPlugin** — `unit_manager_plugin.gd`. 하단 패널 "유닛 관리" 탭 추가. `add_control_to_bottom_panel` + `make_bottom_panel_item_visible`.
  - **Control 패널** — `unit_manager_panel.gd` (@tool). 한 화면에서 모든 UnitData(.tres) 편집.
    - 아군/적 섹션 분리 + 프로시저럴 도형 미리보기 + SpinBox/OptionButton 인라인 편집.
    - 행: 이름/역할/HP/공격/공속/이속/사거/EXP/도형/크기. "💾 모두 저장"/"🔄 새로고침" 버튼.
  - **`unit_preview_rect.gd`** — 분리된 @tool 도형 미리보기 (inner class 대신 별도 파일 — 에디터 _draw() 호출 보장).
  - **DOTS_test.bat** 메뉴 6: Godot 에디터로 유닛 수치 조정 진입.

##### P8-C6 패널 빈 화면 버그 해결 (2026-07-07)
- **현상**: EditorPlugin 패널이 펼쳐진 상태로 빈 화면 표시. Output 로그엔 "로드 완료: 아군 4, 적 3"이 5회 정상 출력됨.
- **근본 원인**: `VBoxContainer`에 `set_anchors_preset(PRESET_FULL_RECT)` 미설정 → 루트 dock의 expand 공간을 받지 못해 ScrollContainer 높이가 0 → 행이 렌더링되어도 화면에 보이지 않음. 이전 5회 시도(_loaded/_loading 플래그, visibility_changed, free/queue_free, make_bottom_panel_item_visible, set_anchors_preset)는 전부 로드 시점/중복 방지 영역이라 레이아웃(크기 0) 문제에 닿지 않아 실패.
- **해결**: (1) vbox에 `PRESET_FULL_RECT` 부여, (2) `_table_container`에 `SIZE_EXPAND_FILL`, (3) `_scroll`에 `custom_minimum_size=(0,120)` 안전장치, (4) `_PreviewRect` inner class를 별도 @tool 파일로 분리(_draw() 호출 보장), (5) DEBUG 로그로 이진 탐색 가능하게.
- **검증**: 에디터 재시작 → 유닛 관리 탭 → 7행(아군 4 + 적 3) 정상 표시 확인. DEBUG=false로 토글.

##### P8-C/D 검증 (데스크톱, 2026-07-07)
- 임포트 PASS (에러 0)
- RTP 시뮬: 94.88% (코어 영향 0)
- 캡처: CREDIT 10000→9950→9900...→9600 (스핀당 -50만, **당첨 시 증가 없음** ✅)
- UnitSpawner: LordState.miss_compensation 반영 (꽝 시 미니언 1+comp명 소환)
- WaveManager: UnitRegistry.get_enemy_unit() 정상 동작

#### P8-D 릴 개조 시스템 (`scripts/systems/ReelModifier.gd`)
- [ ] **P8-D1 런타임 ReelStrip 조작** — 심볼 추가/교체/제거. 원본 훼손 방지용 가변 복사본 래퍼.
- [ ] **P8-D2 칸 멀티플라이어** — 특정 릴 위치에 [X2]/[X3] 배수 부여. 소환 수 배수 적용.
- [ ] **P8-D3 5번째 줄 배수 릴** (필립 성주 전용 — Phase 10). 알베르트는 심볼 교체 위주.

#### P8-E 유물/패시브 시스템 (`scripts/systems/ArtifactManager.gd` autoload) ✅ 완료 (2026-07-07)
- [x] **P8-E1 유물 데이터** (`scripts/data/ArtifactData.gd`) — id/display_name/description/effect_type/params. ✅
- [x] **P8-E2 알베르트 수비 유물 2종** ✅
  - **가시 바리케이드** (spike_barricade): 기지 근처(x<150) 적에게 도트 데미지 (5 dmg / 0.5초).
  - **마력 보호막** (magic_shield): 기지 피해의 50% 흡수 (최대 50).
- [x] **P8-E3 유물 트리거 통합** ✅
  - `DefenseArtifactEffect.apply()` → `ArtifactManager.register(id)` 호출.
  - 가시 바리케이드: `_physics_process`에서 BattleField 적 유닛 조회 → 데미지.
  - 마력 보호막: `EventBus.base_damaged` 구독 → 피해 회복(치료) 형태로 흡수.
  - 유물 효과 로그 출력 (`[ArtifactManager] 가시 바리케이드: 적 N체에 M 데미지`).

##### P8-E 아키텍처
- **ArtifactData** (Resource) — 유물 메타데이터. effect_type 문자열 키 + params Dictionary (확장성).
- **ArtifactManager** (autoload) — 활성 유물 목록 + 실제 전장 효과 발동.
- **DefenseArtifactEffect** (ChoiceEffect 서브클래스) — LordState.add_defense_artifact + ArtifactManager.register 동시 호출.
- LordState는 유물 id 저장만 (UI 표시용), ArtifactManager가 실제 효과 담당 (관심사 분리).

#### P8-F 시너지 진화 (`scripts/data/EvolutionRecipe.gd` + `EvolutionPass.gd`)
- [ ] **P8-F1 진화 조건 데이터** — 유닛 만렙 + 유물 만렙 조합 → 진화 유닛 해금.
- [ ] **P8-F2 EvolutionPass** — `JackpotEvaluationPass` 조건 평가 패턴 재사용. `WinCalculator` 체인에 추가.
- [ ] **P8-F3 진화 유닛 소환** — 진화 조건 달성 시 해당 심볼 매칭 → 진화 유닛으로 소환 교체.

#### P8-G 피버 타임 (`scripts/systems/FeverManager.gd`)
- [ ] **P8-G1 피버 게이지** — 빅윈/잭팟 시 충전. `EventBus.big_win`/`jackpot_won` 구독.
- [ ] **P8-G2 피버 모드** — 발동 시 스핀 쿨타임 0, 연타 스핀 가능. `BonusManager` 상태머신 패턴 참고.
- [ ] **P8-G3 피버 연출** — 네온 컬러 풀화면 틴트 + BSM 고속 재생.

#### P8-H 성주(Lord) 시스템 기초 (`scripts/data/LordData.gd`)
- [ ] **P8-H1 LordData 리소스** — id/display_name/passive_id/choice_pool_ids.
- [ ] **P8-H2 알베르트 데이터 생성** — 꽝 보정 강화 + 수비형 유물 풀 + 기사/방패병 진화 풀.
- [ ] **P8-H3 성주 선택 적용** — 게임 시작 시 선택(프로토타입은 알베르트 고정). `SlotMachineView._initialize_all`에 성주 로드 통합.

- [ ] **P8 테스트**: 3지선다 → 릴 개조 → 유닛 진화 → 30 WAVE 생존 밸런스 캡처 검증. 피버 타임 카타르시스 체감.

---

### 🟣 Phase 8.5 — 전투 피드백 + 코드 전수 리뷰 (2026-07-08, 폰 검증 완료)

> 4도메인(전투/슬롯코어/시스템/뷰) 병렬 에이전트 리뷰 + 핵심 항목 코드 직접 검증 + 폰 테스트 피드백 반영.
> 59개 스크립트 전수 조사. 에이전트 오판 1건(`_pick_target` — 왼쪽우선 매칭은 업계 표준)은 제외.

#### P8.5-A 코드 전수 리뷰 — 8개 버그 수정 (폰 검증 완료)

| 버그 | 원인 | 해결 |
|---|---|---|
| **음소거 미동작** | HUD가 `master_muted=on` 직접 설정 후 `toggle_mute()`(내부 `not` 반전) 호출 → 항상 false로 돌아가 음소거 자체 안 됨 | `AudioManager.set_muted(on)` setter 추가, HUD에서 사용 |
| **유닛 새 적 무시** | 타겟 사망해도 `_target`이 null 리셋 안 됨 → `_on_area_entered`의 `_target==null` 체크가 dangling 참조로 막힘 | `_physics_process`에서 `is_instance_valid` 실패 시 null 리셋 + 사망 시 `monitoring=false` |
| **재시작 프리스핀 잔류** | `_initialize_all`이 BonusManager reset 누락 → 새 런에 멀티플라이어/잔여 프리스핀 전이 | `BonusManager.reset()` 추가 + `_initialize_all` 연동 |
| **game_over 후 전투 계속** | WaveManager만 정지, Unit은 계속 움직임 | BattleField가 자식 Unit `set_physics_process(false)`, reset_run에서 복원 |
| **game_over+AUTO 슬롯 계속** | 슬롯 코어가 game_over 모름 → AUTO가 계속 스핀→소환→유닛 이동 | SlotMachine(request_spin 가드)/UnitSpawner(소환 가드)/SlotMachineView(AUTO 중단) game_over 구독 + reset_game_over 복원 |
| **reset_run 중복 emit** | `_emit_hp()` 후 또 `base_hp_changed` emit | 중복 라인 제거 |
| **base_bet_steps 폴백 약함** | 모바일 직렬화 손실 시 `[50]` 고정 → BET± 무의미 | 코드 기본값 6종 전체 폴백 |
| **소환 오프셋 방향** | 좌측(-x) 오프셋 → 다중 소환 시 기지 뒤(화면 밖)로 밀림 | 진행 방향(+x)으로 수정 |

**교훈**: (1) 재시작 플로우에 상태 보유 autoload 빠짐없이 나열 — 주기적 감사. (2) toggle(반전) API와 set API 섞지 말 것. (3) 캐시한 노드 참조는 사용 전 `is_instance_valid` + 무효면 null 리셋. (4) game_over는 전투뿐 아니라 슬롯(입력→생산 루프)까지 전부 멈춰야 — AUTO는 사용자 개입 없이 도므로 코어 레벨에서 막아야.

#### P8.5-B 전투 이펙트 3종 + 체력바 (폰 검증 완료)

- [x] **히트 점멸** — Unit `_hit_flash`(0~1) + `_draw` tint. texture/도형 양쪽 색상 `lerp(base, RED, flash)`, 체력바는 제외. 0.15초. 연속/동시 타격 시 1.0 리셋. `take_damage`에서 `_flash_hit()`.
- [x] **데미지 숫자** — 신규 `scripts/effects/DamageNumberLayer.gd`(Node2D, BattleField 자식). Label 풀(POOL_SIZE 12, 가장 오래된 것 재사용). `EventBus.damage_dealt(pos, amount, is_target_enemy)` 구독. 적=노랑/아군=빨강. 1초 상승+페이드. `clear()`로 reset_run 정리.
- [x] **원거리 투사체** — 신규 `scripts/battle/Projectile.gd`(**Node2D**, Area2D 아님 — 단일 라인이라 충돌 영역 불필요, 모바일 오버헤드 최소). target 직접 추적(`is_instance_valid`), 도달(≤12px) 시 `take_damage`. target 사망 시 증발. 궁수(260px/s, 초록, 10)/마법사(200, 보라, 14). boss는 근접 유지.
- [x] **체력바 고정** — `bar_w = clampf(data.size * 1.6, 50.0, 100.0)`.
- [x] **공격 분기** — `Unit._physics_process`에서 `if data.is_ranged: _fire_projectile(target) else: take_damage(attack)`. 원거리는 발사 시점 데미지 없음.
- [x] **UnitData 필드** — `is_ranged/projectile_speed/projectile_color/projectile_size/projectile_texture` 추가(개별 @export, PackedArray 회피). `_clone_unit`/`_make`/폴백/`generate_default_data` 4곳 동기화. 단 `.tres` 수동 튜닝값 보존 위해 generate_default_data는 **실행하지 않고** .tres에 수동 추가.

**신규 파일**: `scripts/battle/Projectile.gd`, `scripts/effects/DamageNumberLayer.gd`
**수정 파일**: Unit.gd, UnitData.gd, UnitRegistry.gd, BattleField.gd, EventBus.gd, AudioManager.gd, HUD.gd, SlotMachineView.gd, SlotMachine.gd, UnitSpawner.gd, WalletManager.gd, generate_default_data.gd, archer.tres, mage.tres
**검증**: 폰에서 투사체/점멸/데미지숫자/체력바/근접/소리/AUTO-game_over 정지 모두 확인.

---

### 🟢 Phase 9 — 비주얼 폴리싱 (파타폰 아트, PRD §5, GDD §2)

> 목표: 실루엣 아트 + 눈동자 + 네온 포인트 컬러 + 진화 연출 + 토템 슬롯.

#### P9-A 파타폰 실루엣 아트 (ComfyUI)
- [ ] **P9-A1 유닛 실루엣 7종** — ComfyUI 파이프라인(`tools/comfyui/`)으로 흑백 실루엣 PNG 생성.
  - 기사/궁수/마법사/중갑 방패병/성직자/도적/공성 골렘 + 진화형 7종 = 14종.
- [ ] **P9-A2 적 실루엣** — goblin/orc/boss + WAVE별 신규 적(네크로맨서/드래곤 등).
- [ ] **P9-A3 토템 슬롯머신 실루엣** — 살아숨쉬는 원시 토템 생명체 형상.
- [ ] **P9-A4 배경 실루엣** — 부족 마을/전장/보스룸 3종.
- [ ] **P9-A5 `SymbolView.texture` 교체** — `UnitData.texture`에 PNG 할당. null 폴백(도형) 유지.

#### P9-B 눈동자(Eye) 애니메이션 (`scripts/battle/EyeAnimator.gd`)
- [ ] **P9-B1 눈동자 노드** — 유닛/토템에 자식 Node2D. 스프라이트 또는 draw_arc.
- [ ] **P9-B2 시선 추적** — 스핀 중 릴을 향해 눈동자 이동. `EventBus.spin_started` 트리거.
- [ ] **P9-B3 감정 연출** — 잭팟 시 눈동자 점화(네온 Red/Yellow). `EventBus.jackpot_won`/`big_win` 트리거.
- [ ] **P9-B4 안광 동기화** — PRD §5 요구: 전 유닛 + 성주 UI 눈동자가 동시에 슬롯 응시.

#### P9-C 토템 슬롯 연출 (`scripts/view/TotemView.gd`)
- [ ] **P9-C1 토템 입 벌림** — 스핀 시 토템 애니메이션. `SymbolView` 대체 또는 확장.
- [ ] **P9-C2 유닛 뱉어내기 연출** — 매칭 성공 시 토템 입에서 유닛 분출 파티클.
- [ ] **P9-C3 잭팟 황홀 연출** — 5매칭 시 토템 눈 불타오름 + 대량 분출.

#### P9-D 네온 포인트 컬러 시스템
- [ ] **P9-D1 컬러 팔레트 정의** — 흑백 베이스 + 네온(Red/Cyan/Yellow) 매핑 데이터.
- [ ] **P9-D2 셰이더/이펙트 적용** — 잭팟/스킬 이펙트에 네온 컬러. `WinEffects`/`JackpotFX` 색상 조정.
- [ ] **P9-D3 실루엣+네온 톤 검증** — 캡처로 포인트 컬러 강도 체크.

#### P9-E 진화 연출
- [ ] **P9-E1 진화 유닛 외형 교체** — 진화 발동 시 실루엣 텍스처 교체 + 네온 아우라.
- [ ] **P9-E2 진화 컷신** — 짧은 풀스크린 플래시 + 진화 유닛 특写. `JackpotFX` 패턴.

- [ ] **P9 테스트**: 파타폰 톤 비주얼 + 눈동자 동기화 + 진화 연출 캡처/폰 검증.

---

### 🔵 Phase 10 — 유닛 7종 확장 + 성주 3종 + BM/배포 (PRD §3.2, §3.3, §4)

> 목표: PRD 전체 스펙 구현 + 메타 시스템 + Android/iOS 배포.

#### P10-A 유닛 7종 완전 구현 (PRD §3.2)
- [ ] **P10-A1 중갑 방패병(Iron Shielder)** — 순수 탱커. 5매칭 시 '철벽 진형'(원거리 투사체 100% 차단).
- [ ] **P10-A2 성직자(Cleric)** — 힐러/버퍼. 단일 힐. 5매칭 시 '성역'(광역 힐+공증).
- [ ] **P10-A3 도적(Rogue)** — 침투/극딜. 고이동. 5매칭 시 엘리트 텔레포트 암살.
- [ ] **P10-A4 공성 골렘(Siege Golem)** — 조커. 소환 확률 극악. 5매칭 시 전선 밀어버리기.
- [ ] **P10-A5 기사/궁수/마법사 5매칭 잭팟 효과** — 현재는 일반 소환만. PRD 기준 성기사/일제사격/메테오 연출 추가.

#### P10-B 소환 계수 PRD 정합 (PRD §3.1)
- [ ] **P10-B1 계수 조정** — 현재 3=x1, 4=x2, 5=x3 → **PRD 기준 3=x1, 4=x3, 5=x8**.
  - `UnitSpawner._on_evaluation_completed`의 `count := lw.match_count - 2` 로직 변경.
  - 밸런스 시뮬(RTP) 재검증 필수 — 5매칭 빈도와 계수 곱이 RTP 변동 주원인.

#### P10-C 성주 3종 완전 구현 (PRD §3.3)
- [ ] **P10-C1 필립(황금의 백찻)** — 하이리스크 하이리턴. 5번째 줄 배수 릴 / 물량 폭발 / 속도형 유물.
- [ ] **P10-C2 아우렐리아(대마법학자)** — 시너지 진화 특화. 마법 강화 / 공격형 유물 / 군대 최종 진화 확률 극대화.
- [ ] **P10-C3 성주 선택 UI** — 게임 시작 시 3종 카드 선택 화면. 알베르트 해금, 나머지는 순차 해금 또는 즉시.

#### P10-D 아웃게임 메타 (GDD §5.2)
- [ ] **P10-D1 부족 토템 연구소** — 명예 점수로 영구 버프 해금. `WalletManager` 영속 패턴 재사용.
- [ ] **P10-D2 심볼 도감** — 수집한 유닛 성급(Star) 진화. 베이스 능력치 영구 상향.
- [ ] **P10-D3 명예 점수 시스템** — WAVE 클리어/보스 격파 시 획득. 영속 저장.

#### P10-E BM (비즈니스 모델, PRD §4)
- [ ] **P10-E1 테마/슬롯 스킨 가챠** — 네온 컬러 팩 / 성주 실루엣 스킨 / 잭팟 연출 팩.
- [ ] **P10-E2 확률 제어 소모품** — "다음 3회 꽝 확률 0%" / "5매칭 확정권" 등 일회성 아이템.
- [ ] **P10-E3 편의성 정기권** — 광고 제거 / 무료 부활 / 3지선다 리롤권 패스.
- [ ] **P10-E4 인게임 재화 판매** — 칩/골드 상시 판매.

#### P10-F 배포 (Android/iOS)
- [ ] **P10-F1 Android Release 빌드** — `.aab` 출시용. 커스텀 keystore. `export_presets.cfg` Release 프리셋.
- [ ] **P10-F2 iOS 빌드** — macOS 환경 필요. Provisioning profile. (환경 확인 필요)
- [ ] **P10-F3 Google Play Console 등록** — 패키지 `com.ralph.dots`. 스토어 등록 정보/스크린샷.
- [ ] **P10-F4 CI** — 헤드리스 임포트 + RTP 시뮬 + 전투 시뮬 자동화 (GitHub Actions).

#### P10-G 로컬라이제이션 & QA
- [ ] **P10-G1 CSV 번역** — HUD/메시지/유닛명 ko/en 2개국어.
- [ ] **P10-G2 밸런스 최종 튜닝** — 100,000스핀 시뮬로 RTP 92~96% 확정.
- [ ] **P10-G3 크래시 테스트** — 다양한 디바이스 해상도/비율 대응. SafeArea 최종 검증.

- [ ] **P10 테스트**: 정식 출시 기준 전수 검증 (RTP/핑거스핀/세로가로/크래시).

---

### 📝 슬롯머신 완성 이력 (Phase 1~6, 보존)

> 아래는 토템 스핀 디펜스 확장 전 슬롯머신 단독 MVP 완성 이력.

- [x] **#13 사운드 SFX** ✅ (Phase 6) — 프로시저럴 합성(파형 3종 + SFX 5종 + 헤드리스 가드).
- [x] **RNG 재현성** ✅ (2026-07-06) — `FIXED_SEED` 상수 (0=무작위, 양수=재현).
- [x] **CameraShake 제거** ✅ (Phase 6) — Control UI에서 Camera2D 좌표계 변형 버그 → 인라인 tween 원복.
- [x] **잭팟 save 시뮬 왜곡 수정** ✅ (Phase 6) — `reset_to_seeds()` 추가.
- [x] **EventBus 시그널 정리** ✅ (Phase 6) — 데드 시그널 2종 삭제 + WalletManager forward.
- [x] **에셋 교체** ✅ (2026-07-03) — ComfyUI 도트 심볼 7종 (180×180 투명 PNG). flood-fill 투명변환(번짐 13%→1.8%).
- [x] **배경 아트** ✅ (2026-07-06) — 판타지 배경 3종 (mystic/treasure/enchanted).
- [x] **자동스핀 고도화** ✅ (2026-07-06) — 버튼 순환(×10/25/50/∞) + 손실 한도 50%.
- [x] **설정 패널** ✅ (2026-07-06) — ⚙ 버튼 → 사운드 볼륨/음소거/크레딧 리셋.
- [x] **모바일 성능 최적화** ✅ (이미 구현) — ParticleBudget 티어 분류, SymbolView 풀링, gl_compatibility.
- [x] **Android 빌드 환경** ✅ (2026-07-03) — APK 빌드 성공 (58MB), 실기 테스트 PASS.

### 📝 Phase 7 디펜스 확장 이력 (2026-07-07)

- [x] **상하 분할 레이아웃** ✅ — 전투 55%(1056px) / 슬롯 45%(864px). BattleFieldView + BattleField(Node2D).
- [x] **유닛/적 엔티티** ✅ — Unit.gd(Area2D) + UnitData.gd. 프로시저럴 도형(방패/활/마법진/해골).
- [x] **슬롯→유닛 생산 파이프라인** ✅ — UnitSpawner가 evaluation_completed 구독 → 매칭 결과를 유닛 소환.
- [x] **WAVE 시스템** ✅ — WaveManager. 적 3종 + 보스(5WAVE마다). WAVE 비례 적 수 증가.
- [x] **양 기지 HP 표시** ✅ — BattleFieldView HP 바 + 숫자 라벨. base_hp_changed 시그널로 실시간 갱신.
- [x] **슬롯 심볼 4종 재설계** ✅ — 보석 7종 → 유닛 4종(knight/archer/mage/skull). 4종 균등 릴 배치.
- [x] **통합 초기화** ✅ — `_initialize_all()` (credit/battle/wave/auto 모두 결정론적 리셋).
- [x] **승리/패배 화면** ✅ — GameOverOverlay. 탭 시 리스타트.
- [x] **CREDIT 디버그 머니** ✅ — CREDIT 탭 시 +1000 (출시 전 제거 예정).
- [x] **모바일 직렬화 버그 2종 해결** ✅ — PackedInt32Array 손실(payout/payline) + mechanic lazy 로드. **치명적 버그**.

---

## 4. 기술 부채 / 주의점

| 항목 | 상세 | 대응 |
|---|---|---|
| **dragon 5매치 변동성** | 2350배가 RTP 변동 지배. 20000스핀 ±5%, 100000스핀도 ±2~3%. 저배당 ±1 미세조정이 노이즈에 묻힘. | 정밀 튜닝 시 100,000스핀+ 검증 필수. 시드 고정. 변동성 완화 원하면 dragon 빈도↑·배수↓로 분산 축소(설계 변경). |
| **RNG 비재현성** | `rng_seed=0` → 매 시뮬 무작위 시드. | 시드 고정 옵션화(단기 TODO 잔여). |
| **✅ 잭팟 save 시뮬 왜곡** (2026-07-03 해결) | `JackpotSystem.initialize()`가 누적 풀 유지 → 시뮬 시 GRAND(100000) 1회 지급이 RTP를 +9%p 왜곡(93→102%). | **해결**: `reset_to_seeds()` 추가 + 시뮬에서 호출. 게임 플레이 영속 동작은 유지. |
| **헤드리스 검증 한계** | 더미 DisplayServer로 main loop 프레임 1회 후 멈춤. | 코어(동기)는 헤드리스 RTP 시뮬 가능. 뷰/타이밍(스크롤·감속·tween)은 **에디터/GUI 실행으로만** 확인. `_physics_process` + `TWEEN_PROCESS_PHYSICS` 필수. |
| **헤드리스 100k스핀 타임아웃** (2026-07-03) | 100,000스핀 시뮬이 5분 초과로 미완료. 동기 루프가 단일 프레임에서 실행되어 매우 느림. | 기본 20,000스핀 권장. 100k 필요 시 프레임 분할 또는 `await` 삽입 검토. |
| **✅ AudioManager SFX** (2026-07-03 해결) | autoload만 있고 재생 로직 없음. | **해결**: 프로시저럴 파형 합성으로 SFX 5종 구축(spin/win/big_win/jackpot/free_spins). 헤드리스 가드로 시뮬 영향 0. |
| **✅ CameraShake 제거** (2026-07-03 해결) | Phase 3 구현 후 연결 안 됨. Camera2D 활성화 시 Control UI 좌표계 변형으로 화면 안 보임 버그 발생. | **해결**: CameraShake.gd 파일 제거 + 인라인 릴 영역 tween 으로 원복(Control UI 정답). 빅윈 진동은 인라인 tween 유지. |
| **result_modifier 데드 훅** (2026-07-03) | `SlotMachine.add_result_modifier()` 등록 호출자 0건. `BonusManager._on_eval`이 실질 후처리 단독 담당으로 기능 중복. | open-structure 확장점으로 **유지 결정**(2026-07-03). 장기 TODO에서 데모 추가 예정. |
| **✅ EventBus 시그널 정리** (2026-07-03 해결) | `celebration_finished`, `clear_highlights`(orphan), `credit_changed`/`bet_changed` forward 누락. | **해결**: 데드 시그널 2종 삭제, WalletManager forward 일원화. `pool_changed`/`state_changed`는 잔존(자체 시그널, 영향 낮음). |
| **GameManager 슬롯 무관** (2026-07-03) | 점수/일시정지 로직이 슬롯 도메인과 무관한 boilerplate. | **유지 결정**(2026-07-03): 향후 메인메뉴/레벨 확장 대비. |
| **WASAPI 에러(헤드리스)** | Godot 헤드리스 실행 시 오디오 드라이버 init 실패 경고 → dummy 폴백. | 정상(무시). GUI 모드에선 문제 없음. AudioManager 헤드리스 가드로 이제 미발생. |
| **✅ HUD SafeArea offset 폭주** (2026-07-03 해결) | `DisplayServer.get_display_safe_area()` 가 모니터 전체 기준이라 작은 창(데스크톱)에서 offset 이 폭주 → HUD 전체가 화면 밖으로 밀려 버튼이 안 보임. | **해결**: 데스크톱(Android/iOS 외)은 offset 0, 모바일만 창 내부 비율로 안전 계산(safe 영역이 창 밖이면 무시). |
| **✅ 모바일 PackedInt32Array 직렬화 손실** (2026-07-07 해결, **치명적**) | Godot 4.7에서 `@export var x: PackedInt32Array` 가 Resource 바이너리 export(.res) 시 빈 배열로 직렬화 손실. 데스크톱 .tres는 정상이지만 모바일 APK에서만 빈 값 로드. **SymbolData.payout**(모든 심볼 payout 0 → 매칭돼도 당첨 인식 안 됨), **Payline.row_per_reel**(get_row()가 -1 → 모든 라인 매칭 실패) 2곳 영향. | **해결**: 개별 int 필드로 분해. `SymbolData.payout_3/4/5`, `Payline.row_r0~r4`. `get_payout()`/`get_row()` match 문 분기. |
| **✅ 모바일 SymbolMechanic lazy 로드 실패** (2026-07-07 해결) | `SymbolMechanic.for_kind()` 가 class_name 전역 식별자로 서브클래스를 lazy 참조 → 모바일 APK 런타임 첫 호출 시점에 서브클래스 스크립트가 아직 로드되지 않아 잘못된 폴백 메카닉 반환 → 매칭 실패. 데스크톱은 에디터가 글로벌 클래스 DB를 사전 완성하므로 정상 동작. | **해결**: (1) 서브클래스를 `preload` 로 컴파일 타임 강제 로드. (2) match 분기 대신 Dictionary 레지스트리로 OCP 확보. (3) `is ScatterMechanic`/`is BonusMechanic` 타입 체크를 `get_tags()` 태그 조회로 대체. |
| **⚠️ APK 재설치 시 데이터 찌꺼기** (2026-07-07) | `adb install -r` 은 user:// 저장 데이터를 유지. 코드 변경 후 APK 복사만 하고 폰에서 재실행하면 이전 버전 캐시/데이터가 남아 "코드는 고쳤는데 안 고쳐진 것처럼" 보이는 함정. | **권장**: 코드 변경 후 폰 테스트 시 `adb shell pm clear com.ralph.dots` 로 user:// 초기화 후 재실행. 또는 APK 복사 후 반드시 재설치. |
| **⚠️ DBG print 잔존 주의** (2026-07-07) | 디버그용 print가 production 코드에 남으면 로그 노이즈 + 성능 저하. | 현재 GameConfig/SlotMachine/SpinEvaluator/HUD/SlotMachineView/WaveManager에서 모두 제거 완료. 새 디버그 print는 커밋 전 제거. |
| **⚠️ EditorPlugin @tool 레이아웃 주의** (2026-07-07 해결) | `add_control_to_bottom_panel` 로 추가한 Control은 루트 dock에서 크기를 받지만, 그 자식 VBoxContainer에 `PRESET_FULL_RECT` 미설정 시 expand 공간이 전달되지 않아 ScrollContainer 높이가 0이 되고 행이 보이지 않는 함정. 로그는 정상 출력되어 디버깅을 혼란스럽게 함. | **해결**: VBoxContainer에 `set_anchors_preset(PRESET_FULL_RECT)` + 자식 컨테이너 `SIZE_EXPAND_FILL` + 최소 높이 안전장치. inner class 대신 별도 @tool 파일로 _draw() 보장. |
| **✅ 음소거 이중 반전** (2026-07-08 해결) | HUD가 `master_muted=on` 직접 설정 후 `toggle_mute()`(내부 `not` 반전) 호출 → 항상 false → 음소거 자체 안 됨. | **해결**: `AudioManager.set_muted(on)` setter 추가. **교훈**: toggle(반전) API와 set API를 섞지 말 것. |
| **✅ game_over 후 슬롯/전투 계속** (2026-07-08 해결, 폰 발견) | game_over 시 WaveManager만 정지 → Unit 계속 움직임 + AUTO가 살아 슬롯 계속 스핀→소환. | **해결**: BattleField(자식 Unit 정지) + SlotMachine(request_spin 가드) + UnitSpawner(소환 가드) + SlotMachineView(AUTO 중단) game_over 구독 + reset 복원. |
| **✅ Unit `_target` dangling** (2026-07-08 해결) | 타겟 사망해도 `_target` null 리셋 안 됨 → 새 적 무시하고 전진만 함. | **해결**: `_physics_process`에서 `is_instance_valid` 실패 시 null 리셋 + 사망 시 `monitoring=false`. 노드 참조 캐싱은 항상 유효성 체크. |

---

## 5. 검증 명령어 치트시트

> `GODOT="/c/Users/RalphPark/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7-stable_win64.exe"`

```bash
# 데이터 재생성(밸런스 튜닝 후 .tres 갱신)
"$GODOT" --headless --script res://scripts/setup/generate_default_data.gd --path "C:\Project\DOTS"

# 헤드리스 RTP/히트율 시뮬 (코어 검증, 20000스핀 기본)
"$GODOT" --headless --path "C:\Project\DOTS" "res://scenes/setup/SimScene.tscn"

# 헤드리스 임포트(문법/참조 에러 0 확인)
"$GODOT" --headless --import --path "C:\Project\DOTS"

# GUI 캡처 (HUD/레이아웃/당첨라인 시각 검증) → captures/spin_N.png
"$GODOT" --path "C:\Project\DOTS" "res://scenes/setup/CaptureTest.tscn"

# 에디터 실행
"$GODOT" --path "C:\Project\DOTS"
```

- 시뮬 정밀도 올리기: `scripts/setup/run_rtp_sim.gd`의 `SPIN_COUNT` 조정(100000 권장, 느림).
- 캡처 분석: captures 이미지를 Read → CDN URL → analyze_image MCP.

---

## 6. 핵심 파일 맵

```
project.godot                              # 세로 1080×1920, autoload 14개, main_scene
scripts/
  data/      # SymbolData(payout_3/4/5), ReelStrip, Payline(row_r0~4), Paytable, SlotConfig,
             # SpinResult, LineWin, UnitData(is_ranged/projectile_*), LevelUpChoice/ChoiceEffect/effects,
             # ArtifactData, SymbolMechanic(preload 레지스트리) + mechanics/{4종}
  core/      # SlotMachine(game_over 가드), SpinEvaluator, WinCalculator, EvaluationPass,
             # passes/{LineEvaluationPass,ScatterEvaluationPass,JackpotEvaluationPass}
  view/      # SymbolView(유닛 도형), ReelView, SlotMachineView(전투 통합+game_over AUTO 중단), HUD, PaylineOverlay,
             # GameOverOverlay, LevelUpUI
  effects/   # WinEffects, ParticleBudget, FloatingText, SlowMotion, BackgroundFX, JackpotFX, DamageNumberLayer
  battle/    # Unit(Area2D, 점멸/투사체 발사), BattleField(양 기지 HP+DamageNumberLayer 자식), BattleFieldView(HP 바),
             # UnitSpawner(game_over 가드), WaveManager, Projectile(Node2D 투사체)
  systems/   # BonusManager, SoulGauge, LordState, UnitRegistry, ArtifactManager
  setup/     # generate_default_data, run_rtp_sim, run_capture_test, run_view_test
autoload/    # EventBus(전투/디펜스 시그널+damage_dealt+영혼/레벨업+초기화), GameConfig, Layout, WalletManager,
             # JackpotSystem, AudioManager, GameManager, ParticleBudget, SlowMotion, BonusManager, SoulGauge,
             # LordState, UnitRegistry, ArtifactManager
scenes/
  slot/      # SlotMachine, Reel, Symbol, HUD, JackpotOverlay
  setup/     # SimScene, CaptureTest, ViewTest
resources/   # symbols/(knight/archer/mage/skull), reels/, paylines/(row_r0~4), paytables/, config/,
             # units/{ally,enemy}/*.tres (UnitData — EditorPlugin으로 튜닝, archer/mage는 is_ranged+projectile_*)
addons/
  unit_manager/  # EditorPlugin: plugin.cfg, unit_manager_plugin.gd, unit_manager_panel.gd, unit_preview_rect.gd
assets/shaders/  # 배경 셰이더
```

---

_최종 갱신: 2026-07-08 — 코드 전수 리뷰(8 버그 수정) + 전투 이펙트(히트 점멸/데미지 숫자/원거리 투사체/체력바 고정). 폰 검증 완료. 다음: 투사체 이미지 교체, 프리스핀 활성화, 또는 Phase 8-D(릴 개조)._
