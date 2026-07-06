# DOTS Android 모바일 테스트 가이드

> 빌드된 APK를 안드로이드 폰에 설치해 실기 테스트하는 절차.
> **최종 갱신: 2026-07-03** (환경 구축 완료)

---

## 1. 환경 요약 (이미 구축됨)

| 항목 | 경로/값 |
|---|---|
| **JDK 17** | `C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot` |
| **Android SDK** | `%LOCALAPPDATA%\Android\Sdk` (build-tools 36.1.0, platform 36, NDK 29) |
| **ADB** | `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe` |
| **debug keystore** | `C:\Project\DOTS\android\debug.keystore` (비밀번호: `android`) |
| **내보내기 프리셋** | `export_presets.cfg` (Android Debug, Gradle 비활성화) |
| **APK 출력** | `build/DOTS-debug.apk` (~58MB) |

---

## 2. 빠른 테스트 (3단계)

### 단계 1: 폰 USB 디버깅 활성화

안드로이드 폰에서:
1. **설정 → 휴대전화 정보(또는 소프트웨어 정보)**
2. **빌드 번호** 7회 탭 → 개발자 옵션 활성화
3. **설정 → 개발자 옵션 → USB 디버깅** 켜기
4. USB 케이블로 PC 연결
5. 폰에 "USB 디버깅을 허용하시겠습니까?" → **허용**

### 단계 2: APK 빌드 + 설치 (bat 파일 사용)

바탕화면 `DOTS_test.bat` 실행:
- **[6] Build Android APK** → `build/DOTS-debug.apk` 생성 (약 1분)
- **[7] Install APK to Phone** → 연결된 폰에 자동 설치

### 단계 3: 폰에서 실행

- 폰 앱 서랍에서 **DOTS** 아이콘 탭
- 또는 CMD에서: `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe shell am start -n com.ralph.dots/com.godot.game.GodotApp`

---

## 3. 수동 명령 (bat 없이)

### APK 빌드

```bash
GODOT="/c/Users/RalphPark/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7-stable_win64.exe"
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-17.0.19.10-hotspot"
export ANDROID_SDK_ROOT="$LOCALAPPDATA/Android/Sdk"
export PATH="$JAVA_HOME/bin:$PATH"

"$GODOT" --headless --path "C:\Project\DOTS" --export-debug "Android Debug" "C:\Project\DOTS\build\DOTS-debug.apk"
```

### 기기 확인 + 설치

```bash
ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"

# 연결된 기기 목록
"$ADB" devices

# APK 설치 (기존 버전 교체)
"$ADB" install -r build/DOTS-debug.apk

# 직접 실행
"$ADB" shell am start -n com.ralph.dots/com.godot.game.GodotApp
```

---

## 4. 트러블슈팅

### `adb devices`에 기기가 안 보임
- USB 케이블이 **데이터 전송용**인지 확인 (충전 전용 케이블은 안 됨)
- 폰에서 USB 모드를 **파일 전송(MTP)** 로 변경
- USB 드라이버 설치 확인 (삼성/ LG 등 제조사별 USB 드라이버)
- `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe kill-server` 후 재시도

### `Install failed [INSTALL_FAILED_UPDATE_INCOMPATIBLE]`
- 폰에서 기존 DOTS 앱을 완전히 제거 후 재설치
- 또는 `adb uninstall com.ralph.dots` 후 설치

### 빌드 에러: "Java SDK path required"
- `editor_settings-4.7.tres`의 `export/android/java_sdk_path` 확인
- 경로에 `bin/java.exe`가 있어야 함

### 빌드 에러: "ETC2/ASTC texture compression required"
- `project.godot`에 `textures/vram_compression/import_etc2_astc=true` 있어야 함 (이미 설정됨)

### 앱이 실행되자마자 크래시
- `adb logcat | grep godot` 로 로그 확인
- 주로 SafeArea/해상도 문제 — `project.godot`의 orientation=1(세로) 확인

---

## 5. 실기 테스트 체크리스트

모바일에서 확인해야 할 항목:

- [ ] **세로 화면**으로 고정되는가 (가로 회전 안 됨)
- [ ] **터치 버튼**(SPIN/BET±/AUTO)이 손가락으로 잘 작동하는가
- [ ] **SafeArea**: 노치/홈 인디케이터 영역에 UI가 안 겹치는가
- [ ] **도트 심볼**이 선명하게 보이는가 (픽셀아트 품질)
- [ ] **사운드**가 재생되는가 (spin/win/big_win/jackpot)
- [ ] **자동스핀**이 터치로 토글되는가
- [ ] **성능**: 스핀/이펙트가 부드럽게 동작하는가 (드롭 프레임 없음)
- [ ] **잭팟/프리스핀** 연출이 정상 표시되는가

---

## 6. 빌드 설정 메모

`export_presets.cfg`의 Android Debug 프리셋:
- `gradle_build/use_gradle_build=false` — Gradle 대신 기본 APK 템플릿 사용 (빠르고 안정적)
- `package/unique_name="com.ralph.dots"` — 앱 패키지명
- `architectures/arm64-v8a=true` — 64비트 ARM (최신 폰)
- `architectures/armeabi-v7a=true` — 32비트 ARM (구형 폰 호환)
- `keystore/debug` — debug.keystore로 자동 서명

> **참고**: 배포(Play Store)용은 release 빌드 + release keystore 필요. 테스트용은 debug 빌드 충분.
