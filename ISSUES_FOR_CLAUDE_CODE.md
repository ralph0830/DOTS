# DOTS 프로젝트 — 3가지 문제 해결 요청

> Godot 4.7 (GDScript) 모바일 세로 슬롯머신 디펜스 게임.
> 프로젝트 경로: `C:\Project\DOTS`
> 작성일: 2026-07-08

해결해야 할 문제 3가지. 우선순위 순으로 나열.

---

## 문제 1 (가장 시급): APK 빌드가 막힘

### 증상

```
godot --headless --path <project> --export-debug "Android Debug" <apk>
```

명령이 3분 이상 타임아웃에 걸리며 APK를 생성하지 못함.

### 이전에는 성공했음

- 2026-07-07 13:43에 동일 명령으로 **12초 만에 APK 빌드 성공**했었음
- 그때 `.godot/exported/133200997/` 폴더에 캐시가 이미 존재했음

### 현재 상황

- `.godot/exported/` 폴더를 `rm -rf`로 삭제한 후부터 빌드가 막힘
- `--export-pack "Android Debug" build/test.pck` (PCK만 생성)는 **60초에 성공** (exit 0, 11.6MB PCK 생성됨)
- `.godot/exported/133200997/` 폴더도 PCK 생성 후 생성됨
- 하지만 `--export-debug` (APK 생성)는 여전히 3분 타임아웃 실패

### 시도한 것들 (전부 실패)

1. `scripts/view/SlotMachineView.gd` `_ready()`에 headless 가드 추가:
   ```gdscript
   if DisplayServer.get_name() == &"headless":
       process_mode = Node.PROCESS_MODE_DISABLED
       return
   ```
   → 게임 로직은 멈춤 (WAVE 로그 안 나옴) but 여전히 빌드 안 됨

2. `--headless` 없이 GUI 모드로 export → 게임 로직이 돌아서 더 느림

3. `.godot/imported` 전체 재임포트 → 정상 완료 but 빌드 여전히 안 됨

4. `export_presets.cfg`에서 `include_filter` 추가/제거 → 영향 없음

### 확인된 사항

- Android export template 정상 설치됨:
  `%APPDATA%/Godot/export_templates/4.7.stable/android_debug.apk` 존재
- `gradle_build/use_gradle_build=false` (Gradle 비활성화)
- Godot 에디터 빌드 (winget 설치), `--export-debug`는 "E (에디터 빌드 전용)" 기능
- headless 모드에서:
  - `OS.has_feature("template_debug")` = **false**
  - `OS.has_feature("editor")` = **true**
  - `DisplayServer.get_name()` = **"headless"**

### 질문

- 왜 PCK는 생성되는데 APK는 안 될까?
- APK 서명/zipalign 단계가 headless에서 블로킹되는 것인가?
- `.godot/exported/` 캐시를 안전하게 재생성하는 방법이 있는가?
- 빌드를 성공시키는 방법을 제시해줄 것.

---

## 문제 2: 런타임 로드 .tres가 APK에서 제외됨

### 증상

폰(logcat)에서:
```
[UnitRegistry] 아군 .tres 없음 — 코드 생성 폴백
```
→ 유닛이 .tres의 texture/스탯이 아닌 **코드 폴백 기본값**으로 렌더링됨.

### 근본 원인 (APK 내부 검증으로 확정)

`unzip -l build/DOTS-debug.apk` 확인 결과:

```
assets/resources/units/ally/knight.tres.remap     ← .remap 파일은 있음
```

.remap 파일 내용:
```
[remap]
path="res://.godot/exported/133200997/export-...-knight.res"
```

하지만 이 경로의 `.res` 파일이 APK에 **존재하지 않음**.

비교: `default_slot.tres`, `payline_*.tres`는 `.res`로 변환되어 APK에 정상 포함됨.

### 원인 분석

- `scripts/systems/UnitRegistry.gd`가 런타임 `DirAccess` + `load()`로만 `.tres` 접근
- Godot export는 **컴파일 타임에 참조되는 리소스만** PCK에 포함
- `default_slot.tres`는 `GameConfig` autoload이 참조, payline은 `default_slot`이 참조 → 전이적 포함
- `units/*.tres`는 아무 코드도 `preload`/`load`로 직접 참조 안 함 → "사용 안 됨"으로 제외

### 시도한 것들

1. `export_presets.cfg`에 `include_filter="resources/units/*.tres"` 추가
   → 빌드가 더 느려져서 제거 (문제 1과 충돌)

2. `UnitRegistry.gd`에 `preload` 상수 배열 추가:
   ```gdscript
   const _PRELOAD_ALLIES: Array = [
       preload("res://resources/units/ally/knight.tres"),
       # ...
   ]
   ```
   → 이것도 빌드 막힘에 영향 준 것 같아 제거한 상태

### 질문

- Godot 4.7에서 런타임 `DirAccess`/`load()`로 접근하는 `.tres`를 export에 강제 포함시키는 가장 깔끔한 방법은?
- `resources/units/*.tres`가 APK에 포함되도록 수정해줄 것.
- 같은 문제가 `resources/choices/*.tres` (`LordState` 선택지 풀)에도 잠재적 발생 가능.

---

## 문제 3: VICTORY/DEFEAT 창이 화면 중앙이 아닌 좌상단에 표시됨

### 증상

게임오버 시 VICTORY/DEFEAT 오버레이가 화면 중앙이 아닌 **왼쪽 상단에 붙어서** 표시됨.

### 현재 코드 (`scripts/view/GameOverOverlay.gd`)

```gdscript
func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    # ... 배경 ColorRect ...
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    center.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # 추가함
    center.size_flags_vertical = Control.SIZE_EXPAND_FILL    # 추가함
    add_child(center)
    var vbox := VBoxContainer.new()
    vbox.custom_minimum_size = Vector2(700, 0)
    center.add_child(vbox)
```

### 시도한 것

- `CenterContainer`에 `size_flags_horizontal/vertical = SIZE_EXPAND_FILL` 추가
- 그래도 좌상단에 표시됨

### 구조

- `GameOverOverlay`는 `SlotMachineView` (Control, `PRESET_FULL_RECT`)의 자식으로 `add_child` 됨
- `scenes/slot/SlotMachine.tscn`이 main scene, `SlotMachineView`가 루트

### 질문

- `CenterContainer`가 부모를 채우지 못하고 좌상단에 머무는 원인은?
- VICTORY/DEFEAT 텍스트가 화면 중앙에 오도록 수정해줄 것.
- `LevelUpUI.gd` (`scripts/view/LevelUpUI.gd`)도 동일한 패턴/버그이니 같이 수정해줄 것.

---

## 공통 참고사항

- 모든 코드 주석은 **한국어**로 작성
- 모바일(Android)과 데스크톱 양쪽에서 동작해야 함
- `gl_compatibility` 렌더러 고정
- Godot 4.7에서 `PackedInt32Array`를 `@export Resource` 필드에 쓰면 모바일 export 시 빈 배열로 직렬화 손실되는 버그가 있음 (이미 개별 int 필드로 회피함)
- 빌드 확인용 명령어:
  ```bash
  GODOT="C:\Users\RalphPark\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64.exe"
  "$GODOT" --headless --import --path "C:\Project\DOTS"
  "$GODOT" --headless --path "C:\Project\DOTS" --export-debug "Android Debug" "C:\Project\DOTS\build\DOTS-debug.apk"
  ```
- 폰 설치: `adb install --no-incremental build/DOTS-debug.apk` (삼성 Incremental Install 회피)

---

## 우선순위

**문제 1 (빌드)을 최우선으로 해결.** 문제 2와 3은 그 이후에.

---

## 해결 이력

### ✅ 문제 1 해결 (2026-07-08)

**근본 원인**: CLI 옵션 오타. `--export_debug`(언더바)가 아니라 `--export-debug`(하이픈)가 정상.
언더바 버전은 무효 옵션으로 조용히 무시되어 export 단계로 넘어가지 못하고 main scene 로드 후 대기.

**해결**: 하이픈 `--export-debug`로 수정 → **16초 만에 APK 빌드 성공** (69MB, `ADDING: resources.arsc → Signed → DONE`).

**교훈**:
- `.godot/exported/` 캐시 삭제와는 무관했음 (적색 교란).
- Godot CLI 옵션은 도움말(`--help`)에 표시되는 하이픈 형식이 정답.
- ISSUES 파일의 "빌드 확인용 명령어" 예시에 언더바가 그대로 적혀 있어 Claude Code 작업 시 계속 함정이 됨 → 수정 완료.

**수정 파일**:
- `DOTS_test.bat` — DO_BUILD 서브루틴 명령어 하이픈으로 수정 (Claude Code 적용)
- `ISSUES_FOR_CLAUDE_CODE.md` — 예시 명령어 3곳 언더바→하이픈 수정
- `scripts/view/SlotMachineView.gd` — 주석 내 예시 명령어 하이픈 수정

### ✅ 문제 2 해결 (2026-07-08)

**근본 원인**: `scripts/systems/UnitRegistry.gd`가 런타임 `DirAccess` + `load()`로만 `resources/units/{ally,enemy}/*.tres`에 접근 → Godot export 의존성 그래프에 컴파일 타임 참조가 없어 `.res`가 APK에서 제외되고 99바이트 `.remap` 파일만 남음. `export_filter="all_resources"`도 "참조된 모든 리소스"이지 "모든 파일"이 아님.

**해결**: `UnitRegistry`에 `_REQUIRED_ALLIES`/`_REQUIRED_ENEMIES` `preload` 상수 배열 추가 → 컴파일 타임 의존성 엣지 생성 → export에 확정 포함. `initialize()` 순서: preload 확정 멤버 우선 → DirAccess 보완(open-structure 확장) → 코드 폴백.

**검증**: `unzip -l build/DOTS-debug.apk | grep exported/.*knight.res` → `assets/.godot/exported/.../export-...-knight.res` 포함 확인. 폰 logcat에서 "코드 생성 폴백" 메시지 사라짐.

**참고**: `resources/choices/*.tres`(LordState 선택지)는 .tres가 아니라 코드 `_LevelUpChoice_.new()` 동적 생성 + 스크립트 preload로 이미 안전 → 별도 처리 불필요.

### ✅ 문제 3 해결 (2026-07-08)

**근본 원인**: `set_anchors_preset(PRESET_FULL_RECT)`는 **anchors(0,0,1,1)만** 설정하고 **offsets는 건드리지 않음**. offsets가 이전 값으로 남아 부모를 채우지 못함 → CenterContainer가 minimum size(VBox 너비)만큼만 좌상단에 표시. `size_flags=EXPAND_FILL`만으로는 해결 안 됨.

**해결**: `set_anchors_and_offsets_preset(PRESET_FULL_RECT)` 사용(anchors + offsets 모두 설정). 추가로 `_ensure_full_rect()`에서 표시 시점에 `position=ZERO; size=부모size` 명시 적용(lazy layout 타이밍 대비).

**수정 파일**: `scripts/view/GameOverOverlay.gd`, `scripts/view/LevelUpUI.gd`, `scripts/view/SlotMachineView.gd`(오버레이 add_child 전 anchor 설정).

---

## ✅ 3문제 모두 해결 완료 (2026-07-08)

문제 1(빌드), 2(.tres export 제외), 3(오버레이 중앙 정렬) 전부 해결. 폰 검증 완료.
