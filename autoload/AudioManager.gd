extends Node
## AudioManager — SFX/BGM 재생 autoload.
## Phase 1: 인터페이스만(no-op).
## Phase 3: AudioStream 풀 연결 예정이었으나,
## 2026-07-03: 프로시저럴 파형 합성(AudioStreamWAV + 16-bit PCM)으로 SFX 풀을 직접 구축.
##            외부 에셋 0, 라이선스 부담 없음, 코드만으로 전체 SFX 생성.

const SFX_BUS := "Master"
const MIX_RATE := 44100   # CD 품질. 효과음에 충분.

var _sfx_pool: Dictionary = {}   # name -> AudioStream
var _bgm_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var master_muted: bool = false


func _ready() -> void:
	AudioServer.get_bus_index(SFX_BUS)   # 마스터 버스 인덱스 캐싱(자동 생성 보장)
	# 헤드리스(RTP 시뮬 등)에서는 오디오 초기화/EventBus 구독을 전부 생략.
	# 이유: (1) 더미 오디오 드라이버라 재생 자체가 무의미. (2) WASAPI init 경고 방지.
	#       (3) 시뮬 성능 보호(파형 생성 비용 회피). (4) 평가 시그널이 재생 시도하지 않도록 차단.
	if DisplayServer.get_name() == "headless":
		return
	_build_procedural_sfx()
	_connect_events()


# --- 프로시저럴 파형 생성기 (private) ---

## 16-bit PCM 사인파 톤 생성. 페이드인/아웃 엔벨로프로 클릭 잡음 제거.
func _make_tone(freq_hz: float, duration_s: float, amplitude: float = 0.5) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration_s)
	var data := PackedByteArray()
	data.resize(n * 2)   # 16-bit = 2바이트/샘플
	var phase_step := freq_hz * TAU / float(MIX_RATE)
	var phase := 0.0
	var fade := maxi(1, n / 20)   # 처음/끝 5% 구간 페이드
	for i in range(n):
		var env := 1.0
		if i < fade:
			env = float(i) / float(fade)
		elif i > n - fade:
			env = float(n - i) / float(fade)
		var s := sin(phase) * amplitude * env
		data.encode_s16(i * 2, clampi(int(s * 32767), -32768, 32767))
		phase += phase_step
	return _wav_from_data(data)


## 주파수 스윕(상승/하강 사인). 시작→끝 주파수로 부드럽게 변화.
func _make_sweep(freq_start: float, freq_end: float, duration_s: float, amplitude: float = 0.5) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration_s)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var fade := maxi(1, n / 20)
	for i in range(n):
		var t := float(i) / float(n)   # 0→1 정규화 시간
		var env := 1.0
		if i < fade:
			env = float(i) / float(fade)
		elif i > n - fade:
			env = float(n - i) / float(fade)
		var freq := lerpf(freq_start, freq_end, t)
		var s := sin(phase) * amplitude * env
		data.encode_s16(i * 2, clampi(int(s * 32767), -32768, 32767))
		phase += freq * TAU / float(MIX_RATE)
	return _wav_from_data(data)


## 다중 주파수 화음(코드). 각 주파수 사인파를 합산 후 진폭 정규화.
func _make_chord(freqs: Array, duration_s: float, amplitude: float = 0.5) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration_s)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phases := PackedFloat32Array()
	phases.resize(freqs.size())
	phases.fill(0.0)
	var fade := maxi(1, n / 20)
	for i in range(n):
		var env := 1.0
		if i < fade:
			env = float(i) / float(fade)
		elif i > n - fade:
			env = float(n - i) / float(fade)
		# 각 주파수 성분 합산(진폭은 성분 수로 나눠 클리핑 방지).
		var sum := 0.0
		for k in range(freqs.size()):
			sum += sin(phases[k])
		sum = sum / float(freqs.size()) * amplitude * env
		data.encode_s16(i * 2, clampi(int(sum * 32767), -32768, 32767))
		for k in range(freqs.size()):
			phases[k] += freqs[k] * TAU / float(MIX_RATE)
	return _wav_from_data(data)


## PackedByteArray(16-bit PCM mono) → AudioStreamWAV 조립.
func _wav_from_data(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream


# --- SFX 풀 구축 + EventBus 연결 ---

## 프로시저럴 파형으로 SFX 풀을 채운다. _ready()에서 1회 호출.
func _build_procedural_sfx() -> void:
	# 스핀 시작: 짧은 상승 휘파람(600→1000Hz)
	register_stream("spin_start", _make_sweep(600.0, 1000.0, 0.15, 0.3))
	# 일반 당첨: 상승 사인 스윕(A4→A5)
	register_stream("win", _make_sweep(440.0, 880.0, 0.25, 0.4))
	# 빅윈: 메이저 화음(C5+E5+G5)
	register_stream("big_win", _make_chord([523.0, 659.0, 784.0], 0.6, 0.4))
	# 잭팟: 4음 팡파레(C5+E5+G5+C6)
	register_stream("jackpot", _make_chord([523.0, 659.0, 784.0, 1046.0], 1.0, 0.5))
	# 프리스핀 진입: 상승 스윕(660→990Hz)
	register_stream("free_spins", _make_sweep(660.0, 990.0, 0.4, 0.35))


## EventBus 시그널 → SFX 재생 브릿지 연결.
func _connect_events() -> void:
	EventBus.spin_started.connect(func(_bet: int) -> void: play_sfx("spin_start"))
	EventBus.evaluation_completed.connect(_on_eval_sfx)
	EventBus.big_win.connect(func(_amount: int) -> void: play_sfx("big_win"))
	EventBus.jackpot_won.connect(func(_tier: int, _amount: int) -> void: play_sfx("jackpot"))
	EventBus.free_spins_started.connect(func(_count: int, _mult: float) -> void: play_sfx("free_spins"))


## 평가 완료 시 당첨 여부에 따라 win SFX 재생.
func _on_eval_sfx(result: SpinResult) -> void:
	if result != null and result.has_win():
		play_sfx("win")


# --- 공개 API (기존 인터페이스 유지) ---

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


## 음소거 상태를 직접 설정 (버스 + 플래그 동기화).
# HUD 토글에서 사용 — toggle_mute() 를 직접 호출하면 플래그가 이중 반전되어
# 음소거가 풀리는 버그가 있으므로 이 setter 를 사용한다.
func set_muted(on: bool) -> void:
	master_muted = on
	var idx := AudioServer.get_bus_index(SFX_BUS)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, on)


## 마스터 볼륨 설정 (0.0~1.0). 0이면 사실상 음소거.
func set_master_volume(value: float) -> void:
	var idx := AudioServer.get_bus_index(SFX_BUS)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clamp(value, 0.0001, 1.0)))


## 현재 마스터 볼륨 (0.0~1.0).
func get_master_volume() -> float:
	var idx := AudioServer.get_bus_index(SFX_BUS)
	if idx >= 0:
		return db_to_linear(AudioServer.get_bus_volume_db(idx))
	return 1.0


## 오디오 스트림 등록.
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
