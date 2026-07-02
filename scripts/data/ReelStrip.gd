class_name ReelStrip
extends Resource
## 단일 릴의 심볼 시퀀스. 중복 출현 = 출현 빈도/가중치. RTP와 변동성 제어의 핵심.
## 인스턴스는 resources/reels/reel_N.tres.

@export var symbols: Array[SymbolData] = []


func get_length() -> int:
	return symbols.size()


func is_empty() -> bool:
	return symbols.is_empty()


## 인덱스를 순환(래핑)하여 심볼 반환. 범위 밖이거나 빈 스트립이면 null.
func at(index: int) -> SymbolData:
	if symbols.is_empty():
		return null
	return symbols[posmod(index, symbols.size())]


## 무작위 시작 인덱스 반환 (정지 시 상단에 보일 셀). 빈 스트립이면 0.
func random_start_index(rng: RandomNumberGenerator) -> int:
	if symbols.is_empty():
		return 0
	return rng.randi_range(0, symbols.size() - 1)
