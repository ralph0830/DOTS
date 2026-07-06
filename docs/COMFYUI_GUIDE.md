# ComfyUI 이미지 생성 파이프라인 가이드

> DOTS 프로젝트용 도트/픽셀아트 에셋 생성 자동화.
> 로컬 ComfyUI 서버(사용자 소유)의 저장된 워크플로우를 API로 제어하여 게임 에셋을 생성.
> **최종 갱신: 2026-07-03** (검증 완료)

---

## 1. 환경 개요

### 서버 접속 정보

| 항목 | 값 |
|---|---|
| **SSH** | `ssh -p 2202 ralph@ralphpark.com` |
| **ComfyUI 웹 UI** | https://comfy.ralphpark.com |
| **API 엔드포인트** | `http://localhost:8188` (서버 내부) |
| **ComfyUI 버전** | 0.15.1 |
| **설치 경로** | `/opt/ComfyUI` |
| **실행 계정** | `comfyui` (systemd 서비스) |

### 하드웨어 제약 (중요)

| 항목 | 값 | 영향 |
|---|---|---|
| **GPU** | NVIDIA GTX 1060 6GB | VRAM 작아 큰 모델/해상도 제한 |
| **체크포인트** | `Unstable20V112BRunDiffusion.safetensors` (6.9GB, **SDXL 기반**) | 1024×1024가 기본 해상도 |
| **LoRA** | `pixel-art-xl-v1.1.safetensors` (170MB) | 픽셀아트 스타일 특화 |
| **VAE** | `sdxl_vae.safetensors` | SDXL 전용 |

### 성능 벤치마크 (실측, 2026-07-03)

| 해상도 | 소요 시간 | 안정성 | 비고 |
|---|---|---|---|
| 512×512 | **36초** | 매우 안정 | 권장 (DOTS 심볼용) |
| 768×768 | 76초 | 안정 | |
| 1024×1024 | 138초 | 한계 근처 | 마케팅용 1장씩만 |

> **주의**: 1024 이상에서 SSH 연결이 끊길 수 있음. `nohup` 백그라운드 실행 권장 (아래 참조).

---

## 2. 스크립트 (tools/comfyui/)

| 스크립트 | 용도 | 상태 |
|---|---|---|
| `comfy_gem.py` | **단일 심볼 생성 (권장)** — SDXL 생성 → PIL 투명변환 | ✅ 검증 완료 |
| `comfy_dots_symbols.py` | DOTS 심볼 7종 일괄 생성 (`comfy_gem.py` 반복 호출) | ✅ 검증 완료 |
| `comfy_pixel.py` | 팔레트 변환 포함 버전 (GAMEBOY 4색) | 보존 (참고용) |

> **스크립트는 서버 `/opt/ComfyUI/`에도 동일하게 배포되어 있음.**
> 로컬 `tools/comfyui/`는 소스 관리용, 서버가 실제 실행.

---

## 3. 핵심 워크플로우: comfy_gem.py 사용법

### 단일 심볼 생성 (가장 자주 쓰는 패턴)

```bash
# 서버에서 실행
ssh -p 2202 ralph@ralphpark.com 'cd /opt/ComfyUI && python3 comfy_gem.py \
  --prompt "single red ruby gemstone, faceted crystal, glossy, centered, solid pure white background, 16-bit pixel art, cute game icon" \
  --out-size 180 \
  --seed 42 \
  --prefix ruby'
```

### 파라미터 전체 목록

| 파라미터 | 기본값 | 설명 |
|---|---|---|
| `--prompt` | 루비 예시 | 긍정 프롬프트 (심볼 종류/스타일) |
| `--negative` | `realistic, photorealistic, 3d, text, watermark, blurry` | 부정 프롬프트 |
| `--gen-size` | `512` | SDXL 생성 해상도 (8의 배수 강제, 작을수록 빠름) |
| `--out-size` | `100` | 최종 출력 해상도 (PIL NEAREST 리사이즈, DOTS 심볼은 180) |
| `--seed` | `42` | 재현성 (같은 시드 = 같은 결과) |
| `--steps` | `20` | 품질/속도 트레이드오프 (10~30) |
| `--threshold` | `235` | 배경색 임계값 (R,G,B 모두 이值 이상=배경, 230~245 권장). 높일수록 엄격(배경 좁게), 낮출수록 관대 |
| `--feather` | `2` | 경계 안티앨리어싱 페더링 폭(픽셀). 0=페더링 없음(계단 현상), 2~3 권장 |
| `--prefix` | `gem` | 출력 파일명 접두사 |

### 출력 파일 (항상 2개)

```
/opt/ComfyUI/output/{prefix}_solid_{out-size}.png         # 흰 배경 (RGB)
/opt/ComfyUI/output/{prefix}_transparent_{out-size}.png   # 투명 배경 (RGBA) ← 게임용
```

### 로컬로 가져오기

```bash
scp -P 2202 ralph@ralphpark.com:/opt/ComfyUI/output/{prefix}_transparent_180.png assets/sprites/
```

---

## 4. 파이프라인 내부 구조 (이해용)

```
1. workflow.json 로드 (사용자 저장 워크플로우, /opt/ComfyUI/user/default/workflows/)
   └─ 14개 노드: Checkpoint → LoRA → EmptyLatent → CLIP± → KSampler → VAEDecode

2. UI JSON → API JSON 변환 (comfy_gem.py 내 build_simple_api())
   └─ PixelArt Palette Converter 노드는 제외 (단순 저장)

3. /prompt API 제출 → 완료 대기 (/history 폴링)

4. PIL 후처리 (make_transparent)
   ├─ NEAREST 리사이즈 (픽셀 보존)
   └─ 흰색→알파 변환 (밝기 기반 부드러운 마스킹, 안티앨리어싱 경계 처리)

5. PNG 저장 (RGB + RGBA 2종)
```

### 해결한 4가지 기술 제약

| 제약 | 해결책 |
|---|---|
| SDXL은 8의 배수 해상도만 (100×100 불가) | 512×512 생성 → PIL NEAREST 리사이즈 |
| ComfyUI IMAGE는 RGB만 (알파 없음) | PIL로 투명 변환 (flood-fill 기반) |
| Palette Converter는 GAMEBOY 4색 고정 | Converter 생략, 풀컬러 픽셀아트 유지 |
| **투명도가 심볼 내부 하이라이트까지 번짐** | **flood-fill 기반 배경 검출** — 모서리에서 순백 픽셀만 BFS 탐색하여 '외부 배경'만 투명화. 심볼 내부 밝은 영역은 모서리와 연결되지 않아 불투명 유지 (번짐 13%→1.8%) |

---

## 5. DOTS 심볼 7종 일괄 생성

### 한 번에 모두 재생성

```bash
# 백그라운드 실행 필수 (SSH 끊김 방지)
ssh -p 2202 ralph@ralphpark.com 'cd /opt/ComfyUI && \
  nohup python3 comfy_dots_symbols.py > /tmp/dots_gen.log 2>&1 &'

# 진행 상황 확인
ssh -p 2202 ralph@ralphpark.com 'tail -5 /tmp/dots_gen.log'
```

### 심볼별 프롬프트 (comfy_dots_symbols.py 내장)

| 심볼 | 시드 | 프롬프트 키워드 |
|---|---|---|
| ruby | 42 | red ruby gemstone, faceted crystal, glossy |
| sapphire | 43 | blue sapphire gem, faceted, glossy |
| emerald | 44 | green emerald gemstone, hexagonal cut |
| dragon | 45 | cute baby dragon head, purple, chibi kawaii |
| unicorn | **500** | cute baby unicorn, full body, rainbow horn, chibi kawaii (시드 탐색으로 최적화) |
| chest | 47 | treasure chest, golden coins spilling |
| rune | **300** | large glowing magic rune stone, purple crystal (시드 탐색으로 최적화) |

### 일괄 다운로드

```bash
for sym in ruby sapphire emerald dragon unicorn chest rune; do
  scp -P 2202 ralph@ralphpark.com:/opt/ComfyUI/output/${sym}_transparent_180.png assets/sprites/
done
```

---

## 6. 게임 적용 파이프라인 (자동)

생성된 PNG는 `generate_default_data.gd`가 자동으로 연결:

```gdscript
# scripts/setup/generate_default_data.gd _build_symbols() 내부
var tex_path := "res://assets/sprites/%s_transparent_180.png" % id
if ResourceLoader.exists(tex_path):
    s.texture = load(tex_path)
```

### 적용 절차 (이미지 교체 후)

```bash
GODOT="/c/Users/RalphPark/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7-stable_win64.exe"

# 1. PNG import (ResourceLoader.exists 작동을 위해)
"$GODOT" --headless --import --path "C:\Project\DOTS"

# 2. 데이터 재생성 (texture 필드 채움)
"$GODOT" --headless --script "res://scripts/setup/generate_default_data.gd" --path "C:\Project\DOTS"

# 3. 결과 확인
grep "texture\|sprites" resources/symbols/ruby.tres
```

> **폴백**: PNG 파일을 지우면 자동으로 프로시저럴 도형(SymbolView._draw_shape)으로 돌아감 — 안전.

---

## 7. 문제 해결 (트러블슈팅)

### SSH 연결이 자꾸 끊김 (1024×1024 생성 시)

**원인**: VRAM 극한 사용 시 sshd가 일시 응답 불가.

**해결**: `nohup` 백그라운드 실행 + 로그 폴링
```bash
ssh -p 2202 ralph@ralphpark.com 'cd /opt/ComfyUI && nohup python3 comfy_gem.py ... > /tmp/gen.log 2>&1 &'
sleep 60; ssh -p 2202 ralph@ralphpark.com 'tail /tmp/gen.log'
```

### ComfyUI 프로세스 죽었는지 확인

```bash
ssh -p 2202 ralph@ralphpark.com 'ps aux | grep "main.py.*listen" | grep -v grep'
# 없으면 재시작:
ssh -p 2202 ralph@ralphpark.com 'sudo systemctl restart comfyui'
```

### texture가 .tres에 반영되지 않음

**원인**: PNG가 import되지 않아 `ResourceLoader.exists()`가 false.

**해결**: 먼저 import 후 데이터 재생성 (위 6절 순서 준수).

### 투명 배경 가장자리에 흰 테두리 (fringe) 또는 심볼 내부가 반투명해짐

**두 가지 다른 문제** (2026-07-03 알고리즘 개선으로 해결):

1. **흰 테두리 (fringe)**: 경계 안티앨리어싱. `--feather` 값으로 조절 (기본 2).
2. **심볼 내부가 반투명해짐** (이전 darkness 기반 알고리즘의 치명적 결함):
   - 원인: `255 - min(R,G,B)` 공식이 밝은 하이라이트(분홍/연노랑)를 배경으로 오인
   - **해결**: flood-fill 기반 배경 검출로 교체. 모서리에서 순백 픽셀만 BFS 탐색하므로 심볼 내부 밝은 영역은 절대 투명해지지 않음.
   - 효과: ruby 중간 알파 픽셀 4210개(13%) → 678개(1.8%)로 6배 감소

#### 투명도 알고리즘 상세 (make_transparent, comfy_gem.py)

**이전 알고리즘 (darkness 기반, 삭제됨)**:
```
darkness = 255 - min(R,G,B)        # 픽셀이 어두울수록 전경
알파 = (darkness - 210) * 스케일   # 어두운 것만 불투명
```
문제: 루비의 밝은 하이라이트 RGB(255,180,180) → min(B)=180 → darkness=75 → **알파 0~중간값(반투명)**. 심볼 내부의 광택/밝은 색이 모두 반투명으로 번짐.

**새 알고리즘 (flood-fill 기반, 현재 사용)**:
1. 모서리(상하좌우 가장자리)에서 시작
2. R,G,B 모두 ≥ threshold(235)인 픽셀만 따라 **BFS 탐색** (4방향 연결)
3. 탐색된 영역 = "외부 배경" → 알파 0
4. 탐색되지 않은 모든 픽셀 = "심볼 또는 심볼 내부" → **알파 255 (완전 불투명)**
5. 경계 페더링: 배경 외곽에서 심볼 방향으로 N픽셀(`--feather`) 확장, 밝기 비례 부분 투명

**핵심**: 심볼 내부의 밝은 하이라이트는 모서리와 연결되지 않으므로 **절대 배경으로 인식되지 않음**. 번짐 완전 차단.

**정량 개선 (모든 심볼)**:

| 심볼 | 이전 중간 알파 (번짐) | 새 중간 알파 | 개선율 |
|---|---|---|---|
| ruby | 13.0% | **1.8%** | 7.2배 ↓ |
| sapphire | 7.2% | **5.0%** | 1.4배 ↓ |
| emerald | 23.7% | **2.8%** | 8.5배 ↓ |
| dragon | 10.5% | **4.2%** | 2.5배 ↓ |
| unicorn | 4.8% | **3.1%** | 1.5배 ↓ |
| chest | 9.1% | **1.8%** | 5.1배 ↓ |
| rune | 3.4% | **4.4%** | 비슷 (원본 작아서 한계) |

`--threshold`는 배경색 임계값 (기본 235). 높일수록 엄격 (배경만 좁게 인식), 낮출수록 관대.

### 심볼이 너무 작게 그려짐 (unicorn, rune 사례 — 해결됨)

**원인**: LoRA가 "뿔"/"룬 스톤"을 작은 오브젝트로 해석. 초기 시드(46, 48)에서 불투명 픽셀 0.8%, 0.5%로 심변이 거의 보이지 않았음.

**해결: 시드 탐색 + 프롬프트 강화** (`tools/comfyui/seed_explore.py` 사용)

각 심볼 8개 시드(100~800) 생성 후 **불투명 픽셀 비율 + 색상 다양성**으로 자동 평가:

| 심볼 | 초기 시드 | 최적 시드 | 불투명 픽셀 비율 | 개선 |
|---|---|---|---|---|
| **unicorn** | 46 (0.8%) | **500** | **43.3%** (색상 344종) | **54배 증가** |
| **rune** | 48 (0.5%) | **300** | **73.6%** (색상 149종) | **147배 증가** |

프롬프트도 함께 개선:
- unicorn: `"cute baby unicorn, full body, big head, fills frame"` (단순 "뿔" → 전신)
- rune: `"large glowing magic rune stone, fills frame, big purple crystal"` (크기 강조)

**해결책 (재사용시)**:
1. **시드 탐색**: `seed_explore.py`로 8개 시드 자동 비교 (`python3 seed_explore.py` 커스터마이즈)
2. **프롬프트 강조**: `"large centered, fills frame, close-up"` 추가
3. **negative 강화**: `"tiny, small, distant, multiple objects"` 추가

---

## 8. 빠른 참조 (치트시트)

### 원클릭: DOTS 심볼 1개 생성→적용

```bash
# 1) 생성 (서버)
ssh -p 2202 ralph@ralphpark.com 'cd /opt/ComfyUI && python3 comfy_gem.py \
  --prompt "single red ruby gemstone, faceted, glossy, centered, solid white background, 16-bit pixel art, cute" \
  --out-size 180 --seed 42 --prefix ruby'

# 2) 다운로드
scp -P 2202 ralph@ralphpark.com:/opt/ComfyUI/output/ruby_transparent_180.png assets/sprites/

# 3) 적용 (로컬 Godot)
GODOT="/c/Users/RalphPark/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7-stable_win64.exe"
"$GODOT" --headless --import --path "C:\Project\DOTS"
"$GODOT" --headless --script "res://scripts/setup/generate_default_data.gd" --path "C:\Project\DOTS"

# 4) 확인 (bat 파일 [1]번 또는 캡처)
"$GODOT" --path "C:\Project\DOTS" "res://scenes/setup/CaptureTest.tscn"
```

### 프롬프트 스타일 키워드 (복사-붙여넣기용)

**보석류** (ruby/sapphire/emerald):
```
single {COLOR} {GEM} gemstone, faceted crystal, glossy shine, sparkly highlight,
centered composition, solid pure white background, 16-bit pixel art,
cute kawaii game icon, fantasy RPG asset
```

**캐릭터** (dragon/unicorn):
```
cute {CREATURE}, chibi kawaii style, big friendly eyes,
centered, solid pure white background, 16-bit pixel art, fantasy RPG creature icon
```

**아이템** (chest/rune):
```
{ITEM}, cute chibi style, centered, solid pure white background,
16-bit pixel art, fantasy RPG item icon
```

### 팔레트 옵션 (comfy_pixel.py 사용 시, GAMEBOY 변환 원할 때)

서버 팔레트 파일 위치: `/opt/ComfyUI/custom_nodes/ComfyUI-PixelArt-Detector/palettes/1x/`

| 팔레트 | 분위기 |
|---|---|
| `31-1x.png` | 기본 (현재 사용 중) |
| `nintendo-entertainment-system-1x.png` | NES 레트로 |
| `links-awakening-sgb-1x.png` | 젤다 풍 |
| `midnight-ablaze-1x.png` | 따뜻한 불꽃 톤 |
| `mist-gb-1x.png` | 몽환 안개 |

---

## 9. 파일 위치 요약

| 위치 | 내용 |
|---|---|
| `tools/comfyui/comfy_gem.py` | 단일 생성 스크립트 (소스) |
| `tools/comfyui/comfy_dots_symbols.py` | 7종 일괄 스크립트 (소스) |
| `tools/comfyui/comfy_pixel.py` | 팔레트 변환 버전 (소스) |
| `/opt/ComfyUI/comfy_gem.py` | 서버 배포본 (실행용) |
| `/opt/ComfyUI/user/default/workflows/workflow.json` | 사용자 원본 워크플로우 (수정 금지) |
| `assets/sprites/{id}_transparent_180.png` | 생성된 게임 에셋 |
| `docs/COMFYUI_GUIDE.md` | 이 문서 |

---

## 10. 검증 이력

| 날짜 | 작업 | 결과 |
|---|---|---|
| 2026-07-03 | 워크플로우 분석 + API 제어 검증 | ✅ 루비 생성 성공 |
| 2026-07-03 | 해상도 벤치마크 (512/768/1024) | ✅ 512 권장 확정 |
| 2026-07-03 | 투명 배경 변환 검증 | ✅ RGBA, 프린지 없음 |
| 2026-07-03 | DOTS 심볼 7종 일괄 생성 | ✅ 7/7 성공 (4분 13초) |
| 2026-07-03 | 게임 적용 + 캡처 검증 | ✅ texture 자동 연결 확인 |
| 2026-07-03 | **투명도 번짐 해결** — flood-fill 알고리즘 교체 | ✅ 심볼 내부 번짐 13%→1.8% (7배 감소). 모든 심볼 정량 개선 |
| 2026-07-03 | **unicorn/rune 시드 최적화** — seed_explore.py | ✅ unicorn 0.8%→43.3% (54배), rune 0.5%→73.6% (147배). 최종 7종 재생성 + 게임 적용 완료 |

---

_이 가이드는 실제 검증된 명령어와 파라미터만 포함합니다. 새로운 스타일 시도 시 이 문서의 "프롬프트 스타일 키워드" 섹션을 수정하여 팀과 공유하세요._
