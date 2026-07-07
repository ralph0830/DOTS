class_name Payline
extends Resource
## 단일 페이라인 패턴. 5개 릴 각각에서 당첨으로 인정되는 행(row) 인덱스.
## 인스턴스는 resources/paylines/payline_NN.tres (0..19).

@export var id: int = 0                              # 페이라인 번호
## 각 릴(0..4)이 가리키는 행(0..2). PackedInt32Array 대신 개별 int로 분해
## (Godot 4.7 바이너리 export 시 PackedInt32Array 직렬화 손실 버그 회피 —
##  모바일에서 빈 배열 로드 → get_row()가 -1 → 모든 라인 매칭 실패).
@export var row_r0: int = 0
@export var row_r1: int = 0
@export var row_r2: int = 0
@export var row_r3: int = 0
@export var row_r4: int = 0
@export var debug_color: Color = Color(1, 0.85, 0.2) # PaylineOverlay 라인 색


## 특정 릴에서 이 페이라인이 가리키는 행. 범위 밖이면 -1.
func get_row(reel_index: int) -> int:
	match reel_index:
		0: return row_r0
		1: return row_r1
		2: return row_r2
		3: return row_r3
		4: return row_r4
	return -1


## 패턴 유효성 검증: 5개 릴 모두 행 값이 row_count 미만이어야 함.
func is_valid(row_count: int = 3) -> bool:
	for r in range(5):
		var row := get_row(r)
		if row < 0 or row >= row_count:
			return false
	return true
