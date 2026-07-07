class_name BuildStamp
extends RefCounted
## 빌드 식별용 스탬프 — DOTS_test.bat 이 매 빌드마다 현재 시각으로 덮어쓴다.
## 기본값("DEV") 은 bat 빌드를 거치지 않은 상태(데스크톱 에디터 실행 등).
## GameConfig 가 시작 시 [BUILD] 로 출력 → adb logcat 으로 "이 APK가 언제 빌드됐나" 확인.
## 용도: 모바일에서 "코드는 고쳤는데 반영 안 됨" 현상(stale APK) 자가 진단.
const BUILD_TIME := "DEV (bat 빌드 전)"
