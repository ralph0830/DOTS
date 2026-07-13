🌊 웨이브 매니저(Wave Manager) 상세 시스템 명세서1. 아키텍처 개요 (Architecture Overview)하드코딩(초 단위 개별 스폰 지정)을 지양하고, 데이터(Resource)와 스폰 로직(Node/Manager)을 완전히 분리합니다.데이터 영역 (Resource): 기획자가 구글 스프레드시트/엑셀로 편집한 뒤 CSV 변환을 통해 주입하는 웨이브 정보 및 스폰 규칙.로직 영역 (Node): 내부 타이머를 돌려 경과 시간(elapsed_time)을 측정하고, 현재 활성화된 스폰 큐(Queue)를 실시간 계산하여 적을 생성하는 런타임 제어기.2. 데이터 구조 명세 (Data Structures)2.1. 몬스터 스폰 그룹 정보 (SpawnInfo.gd)하나의 웨이브 내에서 특정 타임라인 동안 반복 스폰되는 몬스터의 묶음을 정의하는 템플릿입니다.GDScript# SpawnInfo.gd (Custom Resource)
class_name SpawnInfo
extends Resource

@export_group("스폰 에셋 정보")
@export var id: String = "spawn_batch_01"
@export var monster_stats: MonsterStats  # 몬스터의 능력치 데이터 리소스
@export var monster_prefab: PackedScene  # 스폰할 몬스터의 Godot 씬(Scene)

@export_group("타임라인 및 규칙")
@export var start_time: float            # 웨이브 시작 후 등장 시점 (초)
@export var end_time: float              # 등장 종료 시점 (초)
@export var spawn_delay: float           # 스폰 주기/간격 (초)
@export var count_per_tick: int = 1      # 1주기(Tick)당 동시 스폰될 마리수
2.2. 단일 웨이브 마스터 정보 (WaveData.gd)단일 웨이브 세션의 정보와 클리어 시 보스전 강제 트리거 여부를 관리합니다.GDScript# WaveData.gd (Custom Resource)
class_name WaveData
extends Resource

@export var wave_number: int
@export var description: String = "일반 웨이브"
@export var spawn_list: Array[SpawnInfo] # 이 웨이브에 작동할 SpawnInfo의 배열

@export_group("보스전 설정")
@export var is_boss_wave: bool = false
@export var boss_prefab: PackedScene     # 보스 웨이브일 경우 소환할 보스 씬
3. 핵심 로직: 런타임 웨이브 매니저 (WaveManager.gd)매 프레임(_process) 체크하는 리소스 낭비를 막고, 0.1초 틱(Tick) 타이머를 사용하여 타임라인을 정밀하게 연산하는 엔진 최적화 스크립트입니다.GDScript# WaveManager.gd
extends Node
class_name WaveManager

@export var wave_timeline_data: Array[WaveData] # 스테이지의 모든 웨이브 리소스 배열
@export var spawn_position_node: Marker2D       # 단일 라인 우측 끝 적 포탈 위치

var current_wave_idx: int = 0
var elapsed_time: float = 0.0
var active_spawns: Array[Dictionary] = []       # 현재 웨이브의 런타임 스폰 대기열 변수
var is_wave_running: bool = false

@onready var check_timer: Timer = $CheckTimer

func _ready():
	# 0.1초 주기로 타임라인을 체크하는 타이머 설정
	check_timer.wait_time = 0.1
	check_timer.timeout.connect(_on_check_timer_timeout)

## [외부 트리거] 다음 웨이브 시작
func start_next_wave():
	if current_wave_idx >= wave_timeline_data.size():
		_on_stage_clear()
		return
		
	var wave_data = wave_timeline_data[current_wave_idx]
	elapsed_time = 0.0
	active_spawns.clear()
	is_wave_running = true
	
	# 인게임 UI 및 연출 트리거 (예: 파타퐁 풍의 폰트로 "WAVE 1" 경고 연출)
	SignalBus.wave_started.emit(wave_data.wave_number)
	
	# 데이터 리소스의 스폰 정보들을 런타임 추적용 딕셔너리 구조로 복사
	for spawn in wave_data.spawn_list:
		active_spawns.append({
			"info": spawn,
			"next_spawn_time": spawn.start_time # 첫 스폰 시점 초기화
		})
		
	check_timer.start()

## [0.1초 주기 연산] 타임라인 체크 엔진
func _on_check_timer_timeout():
	if not is_wave_running: return
	
	elapsed_time += check_timer.wait_time
	
	# 억까 방지 장치: 슬롯 3회 연속 꽝 등 위기 상황 시 웨이브 시간 일시정지 기믹 확장 영역
	if GameManager.is_wave_frozen:
		return
	
	var all_spawns_completed = true
	
	# 활성화된 모든 스폰 그룹 순회
	for spawn in active_spawns:
		var info = spawn.info as SpawnInfo
		
		# 1. 현재 시간이 해당 스폰 그룹의 타임라인 범위 내에 있는가?
		if elapsed_time >= info.start_time and elapsed_time <= info.end_time:
			all_spawns_completed = false
			
			# 2. 스폰 주기가 도래했는가?
			if elapsed_time >= spawn.next_spawn_time:
				_execute_spawn(info)
				spawn.next_spawn_time += info.spawn_delay # 다음 스폰 틱 계산
				
		# 3. 아직 종료 시간이 안 지난 스폰이 있다면 웨이브는 끝나지 않음
		elif elapsed_time < info.end_time:
			all_spawns_completed = false
			
	# 모든 스폰 데이터의 end_time이 지나 스폰이 완전히 완료된 경우
	if all_spawns_completed:
		check_timer.stop()
		is_wave_running = false
		_wait_for_enemy_clear()

## [몬스터 생성] 유동적 난이도 조절(DDA) 융합 파트
func _execute_spawn(info: SpawnInfo):
	# 유저의 현재 Bet 레벨(x1~x5)에 따른 난이도 멀티플라이어 적용
	var bet_factor = GameManager.get_current_bet_multiplier() 
	
	# 맥스 베팅(Bet x5)일 경우 물량을 배수로 늘려 스폰 러시 연출
	var final_count = int(info.count_per_tick * bet_factor)
	
	for i in range(final_count):
		var monster_instance = info.monster_prefab.instantiate() as Monster
		
		# 생성된 몬스터에 리소스 스탯 주입
		monster_instance.stats_data = info.monster_stats
		
		# Bet 단계가 높다면 몬스터 스탯에 보정을 가해 밸런스 유지
		monster_instance.hp_modifier = bet_factor 
		
		# 고도 그룹 시스템에 몬스터 등록 (남은 마리수 체크용)
		monster_instance.add_to_group("enemies")
		
		# 전장 포탈 위치에 스폰 및 추가
		monster_instance.global_position = spawn_position_node.global_position
		add_child(monster_instance)

## [클리어 조건 감시] 필드의 적이 0마리가 될 때까지 대기
func _wait_for_enemy_clear():
	# 고도 엔진의 그룹 노드 개수 체크 활용
	while get_tree().get_nodes_in_group("enemies").size() > 0:
		await get_tree().create_timer(0.5).timeout # 0.5초 간격으로 잔여 적 감시
		
	_on_wave_enemies_cleared()

## [웨이브 종료 핸들러] 일반 웨이브 승리 혹은 보스전 트리거
func _on_wave_enemies_cleared():
	var current_wave_data = wave_timeline_data[current_wave_idx]
	
	if current_wave_data.is_boss_wave:
		_trigger_boss_battle(current_wave_data.boss_prefab)
	else:
		print("일반 웨이브 클리어 - 다음 단계 진입")
		current_wave_idx += 1
		# 뱀서식 중간 정비 턴을 주거나 즉시 다음 웨이브 시작
		start_next_wave()

func _trigger_boss_battle(boss_scene: PackedScene):
	print("🚨 보스 웨이브 돌입!")
	var boss_instance = boss_scene.instantiate()
	boss_instance.add_to_group("enemies") # 보스도 적 그룹에 포함
	boss_instance.global_position = spawn_position_node.global_position
	
	# 보스가 사망 시그널을 보낼 때까지 대기 후 스테이지 클리어 처리
	add_child(boss_instance)
	await boss_instance.tree_exited # 보스 노드가 언로드(사망)될 때까지 대기
	
	current_wave_idx += 1
	start_next_wave()

func _on_stage_clear():
	print("🎉 스테이지 최종 클리어!")
	SignalBus.stage_cleared.emit()
4. 엑셀/스프레드시트 연동용 CSV 파서 데이터 규격기획자가 관리할 엑셀 파일은 아래와 같은 규격으로 작성되어 프로젝트 내 res://data/wave_table.csv로 저장됩니다.wave_numberspawn_idstart_timeend_timespawn_delaycount_per_tickmonster_stats_pathmonster_prefab_pathis_bossboss_prefab_path1wave1_batch10.020.04.01res://data/stats/soldier.tresres://scenes/enemy_soldier.tscnfalse1wave1_batch210.025.03.02res://data/stats/archer.tresres://scenes/enemy_archer.tscnfalse2wave2_boss0.00.00.00trueres://scenes/boss_dragon.tscn해석: 1웨이브가 시작되면 0초부터 20초까지 4초마다 보병이 1마리씩 나오고, 10초가 되는 순간부터 25초까지는 3초마다 궁수가 2마리씩 겹쳐서 튀어나옵니다. 이 타임라인 동안 나온 적들을 플레이어가 슬롯머신으로 소환한 군대로 모두 처치하는 순간 2웨이브(보스전)로 자동 전환됩니다.개발자는 에디터 플러그인 툴을 이용해 이 CSV 파일 한 줄당 SpawnInfo 리소스를 동적으로 생성하고, 동일한 wave_number끼리 묶어 WaveData 배열에 채워 넣기만 하면 데이터 관리가 완전히 종료됩니다.