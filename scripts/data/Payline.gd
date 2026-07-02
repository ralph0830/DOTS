class_name Payline
extends Resource
## 단일 페이라인 패턴. 5개 릴 각각에서 당첨으로 인정되는 행(row) 인덱스.
## 인스턴스는 resources/paylines/payline_NN.tres (0..19).

@export var id: int = 0                              # 페이라인 번호
@export var row_per_reel: PackedInt32Array = []      # 길이 5: 각 릴(0..4)의 행(0..2)
@export var debug_color: Color = Color(1, 0.85, 0.2) # PaylineOverlay 라인 색


## 특정 릴에서 이 페이라인이 가리키는 행. 범위 밖이면 -1.
func get_row(reel_index: int) -> int:
	if reel_index < 0 or reel_index >= row_per_reel.size():
		return -1
	return row_per_reel[reel_index]


## 패턴 유효성 검증: 5개 릴 모두 행 값이 있어야 함.
func is_valid(row_count: int = 3) -> bool:
	if row_per_reel.size() != 5:
		return false
	for row in row_per_reel:
		if row < 0 or row >= row_count:
			return false
	return true
