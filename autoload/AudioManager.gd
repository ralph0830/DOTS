extends Node
## AudioManager — SFX/BGM 재생 autoload.
## Phase 1에서는 인터페이스만(no-op). Phase 3에서 실제 AudioStream 풀 연결.

const SFX_BUS := "Master"

var _sfx_pool: Dictionary = {}   # name -> AudioStream (Phase 3 채움)
var _bgm_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var master_muted: bool = false


func _ready() -> void:
	# 마스터 버스가 없으면 자동 생성되어 있음. 인덱스 캐싱.
	AudioServer.get_bus_index(SFX_BUS)


## SFX 재생. 등록된 스트림이 없으면 안전하게 무시.
func play_sfx(name: String, pitch: float = 1.0) -> void:
	if master_muted or not _sfx_pool.has(name):
		return
	var player := _get_idle_sfx_player()
	player.stream = _sfx_pool[name]
	player.pitch_scale = pitch
	player.play()


func play_bgm(name: String) -> void:
	if master_muted or not _sfx_pool.has(name):
		return
	if _bgm_player == null:
		_bgm_player = AudioStreamPlayer.new()
		_bgm_player.bus = SFX_BUS
		add_child(_bgm_player)
	if _bgm_player.stream != _sfx_pool[name]:
		_bgm_player.stream = _sfx_pool[name]
		_bgm_player.play()


func stop_bgm() -> void:
	if _bgm_player != null:
		_bgm_player.stop()


func toggle_mute() -> void:
	master_muted = not master_muted
	var idx := AudioServer.get_bus_index(SFX_BUS)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, master_muted)


## 오디오 스트림 등록 (Phase 3에서 에셋 로드 시 호출).
func register_stream(name: String, stream: AudioStream) -> void:
	if stream != null:
		_sfx_pool[name] = stream


func _get_idle_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if not p.playing:
			return p
	var player := AudioStreamPlayer.new()
	player.bus = SFX_BUS
	add_child(player)
	_sfx_players.append(player)
	return player
