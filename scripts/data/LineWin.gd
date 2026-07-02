class_name LineWin
extends RefCounted
## 단일 페이라인에서의 당첨 결과 데이터. SpinResult.line_wins의 원소.

var payline_id: int = 0                # 당첨된 페이라인 ID (0..19)
var symbol_id: StringName = &""        # 당첨된 심볼 ID
var match_count: int = 0               # 왼쪽부터 연속 매치 수 (3/4/5)
var amount: int = 0                    # 이 라인의 당첨 금액
var positions: Array[Vector2i] = []    # 당첨에 포함된 셀 좌표 (reel, row)
