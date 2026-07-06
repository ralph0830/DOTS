# DOTS — 모바일 세로 슬롯머신 개발 TODO

> Godot 4.7 + GDScript · 세로 1080×1920 · 5릴 × 3행 / 20라인 · 판타지·보석 테마 · 풀 메타(Wild/Scatter/프리스핀/잭팟)
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

## 3. 향후 TODO

### 🔴 단기 (Phase 5 잔여 — 기능 완성)

> **2026-07-03: Phase 6 작업으로 단기 TODO 대부분 완료.** 아래는 완료 이력.

- [x] **#13 사운드 SFX** ✅ (Phase 6 완료) — **프로시저럴 합성**으로 구현(외부 에셋 0).
  - `AudioManager.gd`에 파형 생성기 3종(`_make_tone`/`_make_sweep`/`_make_chord`) 추가 — AudioStreamWAV + 16-bit PCM(PackedByteArray.encode_s16).
  - SFX 5종: spin_start(스윕), win(상승스윕), big_win(C5+E5+G5 화음), jackpot(4음 팡파레), free_spins(스윕).
  - EventBus 구독: spin_started / evaluation_completed(has_win 분기) / big_win / jackpot_won / free_spins_started.
  - 헤드리스 가드(`DisplayServer.get_name()=="headless"`) → 시뮬 성능 보호 + WASAPI 에러 방지.
- [ ] **RNG 재현성 확보** — `SlotMachine.gd:30`이 `rng_seed=0`일 때 `randi()` 무작위 시드 사용. 밸런싱/디버그 시 0이 아닌 시드 고정 또는 시드 입력 옵션.
- [x] **CameraShake 검증 후 제거** ✅ (2026-07-03) — Phase 6에서 Camera2D 기반 CameraShake를 활성화했으나 **Control 기반 UI 씬에서 Camera2D 활성화 시 2D 좌표계가 변해 모든 UI가 화면 밖으로 밀려 보이지 않는 치명 버그 발생**. 원래 인라인 릴 영역 tween 방식이 Control UI에 맞는 정답이므로 CameraShake.gd 파일 제거 + 인라인 tween으로 원복.
- [x] **🚨 잭팟 save 시뮬 왜곡 수정** ✅ (Phase 6 완료) — `JackpotSystem.reset_to_seeds()` 공개 메서드 추가 + `run_rtp_sim.gd`에서 `initialize()` 직후 호출. 검증: GRAND=500000 누적 조건에서도 RTP 90~98%(정상) — 이전 같은 조건 시 110%+ 왜곡 방지 확인.
- [x] **EventBus 시그널 정리** ✅ (Phase 6 완료):
  - `celebration_finished` 삭제(데드), `clear_highlights` 삭제(orphan — `spin_started`로 PaylineOverlay 이미 처리).
  - `WalletManager`에 `_emit_credit()`/`_emit_bet()` 헬퍼 추가 → 자체 시그널 + EventBus forward 동시 발행(BonusManager 모범 패턴과 일원화). HUD의 autoload 직접 접근 우회 해소.

### 🟡 중기 (폴리싱 / 에셋 / 품질)
- [x] **에셋 교체** ✅ (2026-07-03 완전 완료) — ComfyUI(사용자 서버 ralphpark.com:2202)로 **도트/픽셀아트 심볼 7종 생성** (귀엽고 아기자기한 16-bit 스타일, 180×180 투명 PNG). `assets/sprites/{id}_transparent_180.png` 배치 + `generate_default_data.gd`에서 texture 자동 로드(`ResourceLoader.exists` 폴백). 프로시저럴 도형 → 실제 아트 자동 교체 파이프라인 완성.
  - 생성 파이프라인: `tools/comfyui/comfy_gem.py`(SDXL+pixel-art LoRA→flood-fill 투명변환), `comfy_dots_symbols.py`(7종 일괄), `seed_explore.py`(시드 탐색). 가이드: `docs/COMFYUI_GUIDE.md`.
  - **투명도 번짐 해결** (2026-07-03): 이전 darkness 기반 알고리즘이 심볼 내부 하이라이트까지 반투명화(13%) → **flood-fill 기반 배경 검출**로 교체. 모서리에서 순백 픽셀만 BFS 탐색하여 외부 배경만 투명화, 심볼 내부는 불투명 유지 (번짐 1.8%).
  - **시드 최적화** (2026-07-03): unicorn(0.8%→43.3%), rune(0.5%→33.8%) — 각 8개 시드 탐색 후 최적 선택 (unicorn=500, rune=300).
- [ ] **배경 아트** — BackgroundFX 셰이더 위에 테마 배경 이미지 레이어.
- [ ] **모바일 성능 최적화**
  - ParticleBudget 자동 티어 분류(OS.get_name()/메모리 기반) 검증.
  - 드로우콜 프로파일링, 파티클 캡 조정.
  - SymbolView 인스턴스 풀링 점검.
- [ ] **SafeArea 실기기 검증** — 에디터(데스크톱)에선 offset 0이라 노치 대응이 안 보임. Android/iOS 실기기 또는 에뮬레이터에서 확인.
- [ ] **자동스핀 고도화** — 횟수 지정(10/25/50/무한), 손실 한도, 프리스핀 중 자동스핀 토글 잠금.
- [ ] **잭팟 풀 영속 검증** — `user://jackpot.save` 누적 동작 실기 확인.

### 🟢 장기 (확장 / 배포)
- [ ] **설정/저장 화면** — 사운드 볼륨, 자동스핀 기본값, 크레딧 리셋.
- [ ] **open-structure 확장 예시 추가** (새 메카닉/평가패스 데모):
  - 멀티플라이어 심볼 메카닉(당첨 시 배수 적용).
  - 추가 EvaluationPass(예: 인접 매치 ways 시스템, 캐스케이드 릴).
- [ ] **추가 메타** — 미니게임 보너스, 일일 보너스, 레벨/경험치.
- [ ] **내보내기(빌드)** — Android(.apk/.aab), iOS, WebGL 클라이언트. 모바일 키스토어/프로비저닝.
- [ ] **CI** — 헤드리스 임포트 + RTP 시뮬 자동화(밸런스 회귀 감지).
- [ ] **로컬라이제이션** — HUD/잭팟 메시지 CSV 번역(`*.translation`).

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
project.godot                              # 세로 1080×1920, autoload 9개, main_scene
scripts/
  data/      # SymbolData, ReelStrip, Payline, Paytable, SlotConfig, SpinResult, LineWin,
             # SymbolMechanic + mechanics/{Normal,Wild,Scatter,Bonus}
  core/      # SlotMachine, SpinEvaluator, WinCalculator, EvaluationPass,
             # passes/{LineEvaluationPass,ScatterEvaluationPass,JackpotEvaluationPass}
  view/      # SymbolView, ReelView, SlotMachineView, HUD, PaylineOverlay
  effects/   # WinEffects, ParticleBudget, FloatingText, CameraShake, SlowMotion, BackgroundFX, JackpotFX
  systems/   # BonusManager
  setup/     # generate_default_data, run_rtp_sim, run_capture_test
autoload/    # EventBus, GameConfig, WalletManager, JackpotSystem, AudioManager, GameManager, ParticleBudget, SlowMotion, BonusManager
scenes/
  slot/      # SlotMachine, Reel, Symbol, HUD, JackpotOverlay
  setup/     # SimScene, CaptureTest
resources/   # symbols/, reels/, paylines/, paytables/, config/ (*.tres)
assets/shaders/  # 배경 셰이더
```

---

_최종 갱신: 2026-07-03 (Phase 6 + 화면 렌더링 버그 수정) — 단기 TODO 4건 완료. 추가로 2가지 치명 버그 발견/수정: (1) AudioManager.gd `inti()` 오타(→`int()`)로 autoload 로드 실패, (2) CameraShake(Camera2D) 활성화가 Control UI 좌표계 변형시켜 화면 안 보임 → 파일 제거 + 인라인 tween 원복, (3) HUD SafeArea offset이 모니터 전체 기준이라 데스크톱 작은 창에서 폭주해 버튼이 안 보임 → 데스크톱 offset 0 처리. GUI 캡처로 SPIN/BET/AUTO 버튼 + CREDIT/WIN HUD + 5×3 릴 모두 정상 렌더링 확인 완료._
