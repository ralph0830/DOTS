extends Node
## 뷰포트 비례 레이아웃 좌표 헬퍼 — 다양한 세로 해상도/비율(9:16~20:9) 대응.
## 9:16(1080×1920) 기준값과 정확히 동일 (회귀 없음). _process 로 vp 를 매 프레임 갱신하여
## 비율이 바뀌어도 자동 추종(폴드 런타임 전환 시 점프는 허용 — 폴드 대응은 별도).
## class_name 없음 — autoload 이름 "Layout" 으로 전역 접근 (class_name 충돌 회피).
## BattleField/BattleFieldView/SlotMachineView/Unit/HUD 가 공유하는 단일 좌표 소스.

const DESIGN_W := 1080.0
const DESIGN_H := 1920.0

# 상하 margin (SafeArea). TOP=94px(0~94), BOTTOM=96px(화면 비율).
const TOP_MARGIN := 0.0479   # 92px / 1920 (2px 감소)
const BOTTOM_MARGIN := 0.05
# 중앙 콘텐츠 안 전투/미니맵/슬롯/조작.
const BATTLE_RATIO := 0.321   # 참고용 (실제 battle_h는 동적 분배)
const MINIMAP_RATIO := 0.05   # 전투-슬롯 사이 미니맵 영역
const SLOT_RATIO := 0.39      # 참고용 (실제 slot_h는 vp.x 기반 정사형)
const CONTROL_RATIO := 0.1    # 조작계(버튼) 비율
const BATTLE_MIN_RATIO := 0.12   # 전투 최소 보장 비율

# 전투 필드 폭 배수 (좌우 3배) + 뷰 카메라 x (스와이프 offset).
const FIELD_MULT := 3.0
static var _camera_x := 0.0

static var _vp := Vector2(DESIGN_W, DESIGN_H)


func _process(_delta: float) -> void:
	# ★ EXPAND aspect + canvas_items 모드에서 Control.size = window 물리 size.
	#   (예: design 1080×1920, 폰 window 1080×2520 → Control.size = 1080×2520)
	#   content_scale_size(design 1920) ≠ Control.size(폰 2520) 이라
	#   Layout 비율 기반 anchor 가 실제 Control size 와 어긋나 릴 아래 빈 공간이 생김.
	#   따라서 _vp = window.size(Control 실제 size 와 동일) 기준으로 계산한다.
	var win := get_window()
	if win != null:
		var s: Vector2 = win.size
		if s.x > 0.0 and s.y > 0.0:
			_vp = s
			return
	# 폴백: window 미확정 시 visible_rect.
	var vp := get_viewport()
	if vp != null:
		var s2: Vector2 = vp.get_visible_rect().size
		if s2.x > 0.0 and s2.y > 0.0:
			_vp = s2


## 현재 뷰포트 크기(디자인 좌표계 기준 확장).
static func viewport() -> Vector2:
	return _vp


## 전투 영역 높이 — 동적 분배 (margin+미니맵+버튼+슬롯 제외 남은 공간, 최소 BATTLE_MIN_RATIO 보장).
static func battle_h() -> float:
	var used := _vp.y * (TOP_MARGIN + BOTTOM_MARGIN) + minimap_h() + control_h() + slot_h()
	return maxf(_vp.y - used, _vp.y * BATTLE_MIN_RATIO)


## 슬롯 영역 높이 — 가로(vp.x)에 맞춰 정사형(5셀 합 = vp.x). 담을 수 없으면 축소.
static func slot_h() -> float:
	var avail := _vp.y * (1.0 - TOP_MARGIN - BOTTOM_MARGIN) - minimap_h() - control_h() - _vp.y * BATTLE_MIN_RATIO
	return minf(_vp.x, avail)


## 조작계 영역 높이 (버튼).
static func control_h() -> float:
	return _vp.y * CONTROL_RATIO


## 미니맵 영역 높이 (전투-슬롯 사이).
static func minimap_h() -> float:
	return _vp.y * MINIMAP_RATIO


## 미니맵 영역 시작 y (상단 margin + 전투 영역 아래).
static func minimap_top() -> float:
	return _vp.y * TOP_MARGIN + battle_h()


## 슬롯 영역 시작 y (상단 margin + 전투 + 미니맵 아래).
static func slot_top() -> float:
	return _vp.y * TOP_MARGIN + battle_h() + minimap_h()


## 미니맵/슬롯/조작계 영역 비율(anchor 0~1용) — 동적 분배 반영.
static func minimap_top_ratio() -> float:
	return minimap_top() / _vp.y if _vp.y > 0.0 else 0.0


## 조작계 영역 시작 y (상단 margin + 전투+미니맵+슬롯 아래). 동적 slot_h 반영.
static func control_top() -> float:
	return slot_top() + slot_h()


## 슬롯/조작계 영역 비율(anchor 0~1용) — 동적 slot_h 반영.
static func slot_top_ratio() -> float:
	return slot_top() / _vp.y if _vp.y > 0.0 else 0.0


static func control_top_ratio() -> float:
	return control_top() / _vp.y if _vp.y > 0.0 else 0.0


## 릴 셀 크기 — 정사각(1:1) 유지. min(가로, 세로)로 이미지 찌그러짐(뭉개짐) 방지.
static func cell_size() -> float:
	return minf(_vp.x / 5.0, slot_h() / 5.0)


## 릴 셀 가로 — 정사각(셀 크기와 동일).
static func reel_w() -> float:
	return cell_size()


## 릴 셀 세로 — 정사각(셀 크기와 동일).
static func reel_h() -> float:
	return cell_size()


## 전투 라인 y (상단 margin + 전투 영역 중앙 + 50px 아래 — 길을 내려 전투 영역 조정).
static func line_y() -> float:
	return _vp.y * TOP_MARGIN + battle_h() * 0.5 + 50.0


## 아군 소환 위치 x — 본진 좌단.
static func ally_base_x() -> float:
	return _vp.x * 0.05


## 적 소환 위치 x — 적진 우단 (field_w 기반).
static func enemy_portal_x() -> float:
	return field_w() - _vp.x * 0.05


## 적이 아군 기지에 도달한 것으로 판정할 x 임계값.
static func ally_threshold_x() -> float:
	return _vp.x * 0.02


## 아군이 적 기지에 도달한 것으로 판정할 x 임계값 (field_w 기반).
static func enemy_threshold_x() -> float:
	return field_w() - _vp.x * 0.02


## 전투 필드 전체 폭 (vp.x * FIELD_MULT = 3배).
static func field_w() -> float:
	return _vp.x * FIELD_MULT


## 현재 뷰 카메라 x (스와이프 offset). 0=본진, field_w-vp.x=적진.
static func camera_x() -> float:
	return _camera_x


## 뷰 카메라 x 설정 (본진~적진 범위로 클램프).
static func set_camera_x(x: float) -> void:
	_camera_x = clampf(x, 0.0, field_w() - _vp.x)


## 디자인 해상도 대비 세로 스케일 (폰트/터치 보정용). 9:16(vp.y=1920)=1.0.
static func ui_scale() -> float:
	return _vp.y / DESIGN_H
