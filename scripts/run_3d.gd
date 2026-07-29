class_name RunController3D
extends Node3D

enum Phase {
	INTRO,
	FORWARD,
	CHOICE,
	BOSS,
	RESULTS,
	FAILED,
}

enum DamageShakeLevel {
	SMALL,
	MEDIUM,
	STRONG,
}


class ForwardSpawnRequest:
	enum Kind {
		CUSTOMER,
		ELITE,
		GATE,
	}

	var kind: Kind
	var customer_data: CustomerData
	var gate_index: int = 0
	var start_food_gate: bool = false
	var spawn_first_region: int = -1
	# 提前生成只改变可见距离，胃口仍使用原定事件时刻的基准值。
	var baseline_appetite: float = 0.0

	func _init(request_kind: Kind) -> void:
		kind = request_kind


class RewardSpawnRequest:
	var start_position: Vector3
	var upgrade: UpgradeData
	var baseline_appetite: float
	var occupied_regions: int

	func _init(
		request_position: Vector3,
		request_upgrade: UpgradeData,
		request_baseline: float,
		request_regions: int
	) -> void:
		start_position = request_position
		upgrade = request_upgrade
		baseline_appetite = request_baseline
		occupied_regions = request_regions


# 普通波次成员按各自速度保存独立预生成时刻，基准值仍来自同一原定波次。
class ScheduledCustomerSpawn:
	var customer_data: CustomerData
	var trigger_time: float = 0.0
	var baseline_appetite: float = 1.0

const TIMELINE_WORKBOOK_PATH: String = "res://balance_tables/时间轴.xlsx"
const CUSTOMER_WORKBOOK_PATH: String = "res://balance_tables/食客.xlsx"
const WEAPON_WORKBOOK_PATH: String = "res://balance_tables/武器.xlsx"
const NORMAL_UPGRADE_WORKBOOK_PATH: String = "res://balance_tables/普通强化.xlsx"
const SPECIAL_UPGRADE_WORKBOOK_PATH: String = "res://balance_tables/特殊强化.xlsx"
const DEFAULT_CUSTOMER_SCENE: PackedScene = preload(
	"res://scenes/characters/customers/customer_base_3d.tscn"
)
const BOSS_SCENE: PackedScene = preload(
	"res://scenes/characters/bosses/prototype_boss_3d.tscn"
)
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile_3d.tscn")
const GATE_SCENE: PackedScene = preload("res://scenes/upgrade_gate_3d.tscn")
const REWARD_GATE_SCENE: PackedScene = preload("res://scenes/upgrade_drop_3d.tscn")
const LEGACY_CUSTOMER_SPAWN_Z: float = -6.4
const LEGACY_GATE_SPAWN_Z: float = 0.0
const FORWARD_GATE_SPEED: float = 2.5
const BASE_WORLD_SCROLL_SPEED: float = 2.05
const TARGET_CONE_EPSILON: float = 0.0001
const DAMAGE_SHAKE_SMALL_STRENGTH: float = 0.055
const DAMAGE_SHAKE_SMALL_DURATION: float = 0.14
const DAMAGE_SHAKE_MEDIUM_STRENGTH: float = 0.09
const DAMAGE_SHAKE_MEDIUM_DURATION: float = 0.18
const DAMAGE_SHAKE_STRONG_STRENGTH: float = 0.14
const DAMAGE_SHAKE_STRONG_DURATION: float = 0.26
# 远端生成队列还需吸收与食客/掉落门错峰产生的短暂等待。
const FORWARD_GATE_QUEUE_LEAD_SECONDS: float = 2.0
const REWARD_GATE_SEARCH_STEP: float = 0.1
const REWARD_GATE_SEARCH_LIMIT: float = 4.0
# 首轮允许奖励门与横向相交对象重合约半个门深，优先保留食客掉落位置。
const REWARD_GATE_MIN_CENTER_DISTANCE: float = 0.72
const POST_BOSS_MINIMUM_DURATION: float = 40.0
const SMOKE_TEST_TIMEOUT: float = 600.0
const SMOKE_TEST_BOSS_CLEAR_DURATION: float = 30.0
const SMOKE_MINIMUM_GEOMETRY_GAP: float = 1.1
const PLAYTEST_RECORD_PATH: String = "user://playtest_runs.jsonl"

@export_group("Prototype data")
@export var potato_data: FoodData
@export var baguette_data: FoodData
@export var mushroom_data: FoodData
# 空数组表示当前原型默认解锁全部食材；后续局外解锁可在场景中显式配置子集。
@export var unlocked_foods: Array[FoodData] = []
@export var basic_guest_data: CustomerData
@export var fast_guest_data: CustomerData
@export var ranged_guest_data: CustomerData
@export var elite_guest_data: CustomerData
@export var boss_data: BossPatternData

@onready var background: WorldBackground3D = %Background
@onready var entities: Node3D = %Entities
@onready var projectiles: Node3D = %Projectiles
@onready var drops: Node3D = %Drops
@onready var gates: Node3D = %Gates
@onready var cart: Cart3D = %Cart3D
@onready var weapon_controller: WeaponController3D = %WeaponController3D
@onready var director: EncounterDirector = %EncounterDirector
@onready var hud: GameHud = %Hud
@onready var debug_menu: DebugMenu = %DebugMenu

var world_scroll_speed: float = BASE_WORLD_SCROLL_SPEED
var state: RunState
var playfield: Playfield
var phase: Phase = Phase.INTRO
var customers: Array[Customer3D] = []
var boss: PrototypeBoss3D
var _spawn_counter: int = 0
var _elite_started_at: float = 0.0
var _boss_started_at: float = 0.0
var _post_boss_started_at: float = 0.0
var _debug_accumulator: float = 0.0
# 普通门双选与食客奖励单抽共同使用这份本局候选模板。
var _normal_upgrade_pool: Array[UpgradeData] = []
var _normal_wave_index: int = 0
var _next_gate_index: int = 0
var _smoke_test: bool = false
# 请求队列保留时间轴顺序，并在预测到纵向追尾时延迟生成。
var _forward_spawn_requests: Array[ForwardSpawnRequest] = []
var _reward_spawn_requests: Array[RewardSpawnRequest] = []
var _normal_waves_suspended: bool = false
# Boss事件到达时若仍有强化门，先保留前进阶段让该门完成结算。
var _boss_pending: bool = false
var _boss_reward_pending: bool = false
var _bosses_started: int = 0
var _bosses_completed: int = 0
var _current_speed_tier: int = -1
var _crosswind_sign: float = 1.0
var _post_boss_active: bool = false
var _playtest_record_saved: bool = false
var _post_boss_satisfaction_start: Dictionary[StringName, float] = {}
var _post_boss_durability_lost_start: float = 0.0
var _post_boss_gate_choices_start: int = 0
var _upgrade_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _run_seed: int = 0
var _active_special_choices: Array[StringName] = []
var _special_choice_source: StringName = &""
var _smoke_minimum_gate_customer_gap: float = INF
var _smoke_minimum_required_gap: float = SMOKE_MINIMUM_GEOMETRY_GAP
var _smoke_minimum_gap_kind: String = ""
var _smoke_minimum_gap_detail: String = ""
# Excel 加载结果只在本局内存中生效，避免改写场景引用的共享 Resource。
var _food_data_by_id: Dictionary[StringName, FoodData] = {}
var _customer_data_by_id: Dictionary[StringName, CustomerData] = {}
var _special_upgrades_by_id: Dictionary[StringName, SpecialUpgradeData] = {}
var _special_food_max_level: int = RunState.FOOD_MAX_LEVEL
var _special_food_level_multiplier: float = RunState.FOOD_LEVEL_SATISFACTION_MULTIPLIER
var _baguette_giant_interval_seconds: float = RunState.BAGUETTE_GIANT_INTERVAL_SECONDS
var _baguette_giant_attack_speed_scale: float = RunState.BAGUETTE_GIANT_ATTACK_SPEED_SCALE
var _baguette_giant_minimum_interval_seconds: float = RunState.BAGUETTE_GIANT_MINIMUM_INTERVAL_SECONDS
var _baguette_giant_width_regions: float = RunState.BAGUETTE_GIANT_WIDTH_REGIONS
var _baguette_giant_pierce_count: int = RunState.BAGUETTE_GIANT_PIERCE_COUNT
var _baguette_giant_duration_multiplier: float = RunState.BAGUETTE_GIANT_DURATION_MULTIPLIER
var _baguette_giant_satisfaction_multiplier: float = RunState.BAGUETTE_GIANT_SATISFACTION_MULTIPLIER
var _reward_effect_scale: float = 0.4
var _wine_curve_c: float = RunState.WINE_CURVE_C
var _range_curve_c: float = RunState.RANGE_CURVE_C
var _duration_curve_c: float = RunState.DURATION_CURVE_C
var _cart_speed_curve_c: float = RunState.CART_SPEED_CURVE_C
var _range_multiplier_cap: float = RunState.RANGE_MULTIPLIER_CAP
var _debug_invincible: bool = false
# 食材卡取得后转为等级卡；进化按持有状态进入池，全局效果可以重复取得。
var _special_choice_pool: Array[StringName] = [
	&"potato",
	&"baguette",
	&"mushroom",
	&"serving",
	&"potato_aim",
	&"baguette_giant",
	&"mushroom_breath",
	&"soy_sauce",
]


func _ready() -> void:
	_load_timeline_balance()
	_load_customer_balance()
	_load_weapon_balance()
	_load_normal_upgrade_balance()
	_load_special_upgrade_balance()
	_smoke_test = OS.get_cmdline_user_args().has("--smoke-test")
	var requested_seed: int = _requested_run_seed()
	if _smoke_test:
		_run_seed = requested_seed if requested_seed >= 0 else 1701
		_upgrade_rng.seed = _run_seed
	else:
		if requested_seed >= 0:
			_run_seed = requested_seed
			_upgrade_rng.seed = _run_seed
		else:
			_upgrade_rng.randomize()
			_run_seed = _upgrade_rng.seed
	_crosswind_sign = -1.0 if (_run_seed & 1) == 0 else 1.0
	state = RunState.new()
	state.run_seed = _run_seed
	state.food_max_level = _special_food_max_level
	state.food_level_satisfaction_multiplier = _special_food_level_multiplier
	state.baguette_giant_interval_seconds = _baguette_giant_interval_seconds
	state.baguette_giant_attack_speed_scale = _baguette_giant_attack_speed_scale
	state.baguette_giant_minimum_interval_seconds = _baguette_giant_minimum_interval_seconds
	state.baguette_giant_width_regions = _baguette_giant_width_regions
	state.baguette_giant_pierce_count = _baguette_giant_pierce_count
	state.baguette_giant_duration_multiplier = _baguette_giant_duration_multiplier
	state.baguette_giant_satisfaction_multiplier = _baguette_giant_satisfaction_multiplier
	state.wine_curve_c = _wine_curve_c
	state.range_curve_c = _range_curve_c
	state.duration_curve_c = _duration_curve_c
	state.cart_speed_curve_c = _cart_speed_curve_c
	state.range_multiplier_cap = _range_multiplier_cap
	print("PLAYTEST_RUN_SEED value=%d" % _run_seed)
	if _smoke_test:
		# 烟雾测试只验证流程闭环，不让扩展后的普通波次提前终止自动跑局。
		state.maximum_durability = 1000000.0
		state.current_durability = 1000000.0
		Engine.time_scale = 20.0
	playfield = Playfield.new()
	add_child(playfield)
	cart.configure(state, playfield)
	background.set_cart(cart)
	weapon_controller.configure(self, cart, state)
	_build_prototype_upgrades()
	director.event_triggered.connect(_on_timeline_event)
	cart.damaged.connect(_on_cart_damaged)
	cart.destroyed.connect(_on_cart_destroyed)
	state.durability_changed.connect(hud.set_durability)
	hud.special_choice_selected.connect(_on_special_choice_selected)
	hud.restart_requested.connect(_on_restart_requested)
	debug_menu.action_requested.connect(_on_debug_action_requested)
	debug_menu.menu_opened.connect(_on_debug_menu_opened)
	debug_menu.menu_closed.connect(_on_debug_menu_closed)
	hud.set_durability(
		state.current_durability,
		state.maximum_durability,
		state.temporary_shield
	)
	hud.set_phase("准备出餐 · 横向拖动餐车")
	hud.show_toast("按住并横向拖动，松手后餐车留在原位")
	phase = Phase.FORWARD


# 每次进入单局读取已保存的 Excel；非法表只回退场景装配的 .tres。
func _load_timeline_balance() -> void:
	var load_result: TimelineExcelLoader.LoadResult = TimelineExcelLoader.load_from_excel(
		TIMELINE_WORKBOOK_PATH,
		director.timeline
	)
	if load_result.timeline != null:
		director.timeline = load_result.timeline
	if load_result.loaded_from_excel:
		print(
				"BALANCE_TIMELINE_LOADED path=%s events=%d gates=%d waves=%d" % [
				TIMELINE_WORKBOOK_PATH,
				director.timeline.event_progresses.size(),
				director.timeline.normal_gate_count,
				director.timeline.normal_wave_count,
			]
		)
	else:
		push_warning(
			"BALANCE_TIMELINE_FALLBACK path=%s reason=%s" % [
				TIMELINE_WORKBOOK_PATH,
				load_result.error_message,
			]
	)


# 食客表成功时整体替换四类本局数据；失败时不混用部分行，保留场景装配回退。
func _load_customer_balance() -> void:
	var load_result: GameplayExcelLoader.CustomerLoadResult = GameplayExcelLoader.load_customers(
		CUSTOMER_WORKBOOK_PATH
	)
	if load_result.loaded_from_excel:
		_customer_data_by_id.clear()
		for customer_data: CustomerData in load_result.customers:
			_customer_data_by_id[customer_data.id] = customer_data
		basic_guest_data = _customer_data_by_id[&"basic_guest"]
		fast_guest_data = _customer_data_by_id[&"fast_guest"]
		ranged_guest_data = _customer_data_by_id[&"ranged_guest"]
		elite_guest_data = _customer_data_by_id[&"elite_guest"]
		print(
			"BALANCE_CUSTOMERS_LOADED path=%s count=%d" % [
				CUSTOMER_WORKBOOK_PATH,
				load_result.customers.size(),
			]
		)
		return
	_register_fallback_customers()
	push_warning(
		"BALANCE_CUSTOMERS_FALLBACK path=%s reason=%s" % [
			CUSTOMER_WORKBOOK_PATH,
			load_result.error_message,
		]
	)


# 武器表成功时替换本局数据引用；失败时继续使用场景装配的 FoodData。
func _load_weapon_balance() -> void:
	var load_result: GameplayExcelLoader.WeaponLoadResult = GameplayExcelLoader.load_weapons(
		WEAPON_WORKBOOK_PATH
	)
	if load_result.loaded_from_excel:
		_baguette_giant_interval_seconds = load_result.baguette_giant_interval_seconds
		_baguette_giant_attack_speed_scale = load_result.baguette_giant_attack_speed_scale
		_baguette_giant_minimum_interval_seconds = load_result.baguette_giant_minimum_interval_seconds
		_baguette_giant_width_regions = load_result.baguette_giant_width_regions
		_baguette_giant_pierce_count = load_result.baguette_giant_pierce_count
		_baguette_giant_duration_multiplier = load_result.baguette_giant_duration_multiplier
		_baguette_giant_satisfaction_multiplier = load_result.baguette_giant_satisfaction_multiplier
		for food: FoodData in load_result.foods:
			_food_data_by_id[food.id] = food
		if _food_data_by_id.has(&"potato"):
			potato_data = _food_data_by_id[&"potato"]
		if _food_data_by_id.has(&"baguette"):
			baguette_data = _food_data_by_id[&"baguette"]
		if _food_data_by_id.has(&"mushroom"):
			mushroom_data = _food_data_by_id[&"mushroom"]
		if not unlocked_foods.is_empty():
			var replaced_unlocks: Array[FoodData] = []
			for configured_food: FoodData in unlocked_foods:
				if configured_food == null:
					continue
				replaced_unlocks.append(
					_food_data_by_id.get(configured_food.id, configured_food)
				)
			unlocked_foods = replaced_unlocks
		print(
			"BALANCE_WEAPONS_LOADED path=%s count=%d" % [
				WEAPON_WORKBOOK_PATH,
				load_result.foods.size(),
			]
		)
		return
	_register_fallback_foods()
	push_warning(
		"BALANCE_WEAPONS_FALLBACK path=%s reason=%s" % [
			WEAPON_WORKBOOK_PATH,
			load_result.error_message,
		]
	)


# 普通强化表以同一候选池驱动普通门和食客奖励门，非法时回退安全区间。
func _load_normal_upgrade_balance() -> void:
	var load_result: GameplayExcelLoader.NormalUpgradeLoadResult = (
		GameplayExcelLoader.load_normal_upgrades(NORMAL_UPGRADE_WORKBOOK_PATH)
	)
	if load_result.loaded_from_excel:
		_normal_upgrade_pool = load_result.upgrades
		_reward_effect_scale = load_result.reward_effect_scale
		_wine_curve_c = load_result.wine_curve_c
		_range_curve_c = load_result.range_curve_c
		_duration_curve_c = load_result.duration_curve_c
		_cart_speed_curve_c = load_result.cart_speed_curve_c
		_range_multiplier_cap = load_result.range_multiplier_cap
		print(
			"BALANCE_NORMAL_UPGRADES_LOADED path=%s shared_pool=%d" % [
				NORMAL_UPGRADE_WORKBOOK_PATH,
				_normal_upgrade_pool.size(),
			]
		)
		return
	push_warning(
		"BALANCE_NORMAL_UPGRADES_FALLBACK path=%s reason=%s" % [
			NORMAL_UPGRADE_WORKBOOK_PATH,
			load_result.error_message,
		]
	)


# 特殊表控制候选池、说明和可调效果量，未知效果不会进入运行时。
func _load_special_upgrade_balance() -> void:
	var load_result: GameplayExcelLoader.SpecialUpgradeLoadResult = (
		GameplayExcelLoader.load_special_upgrades(SPECIAL_UPGRADE_WORKBOOK_PATH)
	)
	var target_error: String = _special_upgrade_target_error(load_result.upgrades)
	if load_result.loaded_from_excel and target_error.is_empty():
		_set_special_upgrades(load_result.upgrades)
		_special_food_max_level = load_result.food_max_level
		_special_food_level_multiplier = load_result.food_level_satisfaction_multiplier
		print(
			"BALANCE_SPECIAL_UPGRADES_LOADED path=%s count=%d" % [
				SPECIAL_UPGRADE_WORKBOOK_PATH,
				_special_choice_pool.size(),
			]
		)
		return
	_build_fallback_special_upgrades()
	push_warning(
		"BALANCE_SPECIAL_UPGRADES_FALLBACK path=%s reason=%s" % [
			SPECIAL_UPGRADE_WORKBOOK_PATH,
			target_error if not target_error.is_empty() else load_result.error_message,
		]
	)


func _register_fallback_foods() -> void:
	_food_data_by_id.clear()
	for food: FoodData in [potato_data, baguette_data, mushroom_data]:
		if food != null:
			_food_data_by_id[food.id] = food


func _register_fallback_customers() -> void:
	_customer_data_by_id.clear()
	for customer_data: CustomerData in [
		basic_guest_data,
		fast_guest_data,
		ranged_guest_data,
		elite_guest_data,
	]:
		if customer_data != null:
			_customer_data_by_id[customer_data.id] = customer_data


func _special_upgrade_target_error(upgrades: Array[SpecialUpgradeData]) -> String:
	for upgrade: SpecialUpgradeData in upgrades:
		if upgrade.effect_kind not in [
			SpecialUpgradeData.EffectKind.FOOD_CARD,
			SpecialUpgradeData.EffectKind.TARGET_AIM,
			SpecialUpgradeData.EffectKind.EVOLUTION,
		]:
			continue
		if _food_data_for_id(upgrade.target_id) == null:
			return "特殊强化 %s 的目标ID不存在于武器表: %s" % [
				String(upgrade.id),
				String(upgrade.target_id),
			]
	return ""


func _process(delta: float) -> void:
	if phase == Phase.FORWARD:
		state.elapsed_seconds += delta
		# Boss请求到达后只让已排队对象完成接近，不再越过后续路程事件。
		if not _boss_pending:
			_advance_forward_progress(delta)
			director.advance(forward_progress())
			_advance_distance_spawns()
		_process_spawn_requests()
		_process_reward_spawn_requests(delta)
		if _boss_pending and not _has_pending_boss_blocker():
			_begin_boss()
		if _smoke_test:
			_track_smoke_gate_customer_gap()
		hud.set_time(state.elapsed_seconds)
	elif phase == Phase.BOSS:
		state.elapsed_seconds += delta
		hud.set_time(state.elapsed_seconds)
	if _smoke_test:
		if phase == Phase.BOSS and boss != null and is_instance_valid(boss):
			# 自动跑局在Boss阶段跟随目标横坐标，避免把固定发射角误判为流程卡死。
			cart.target_x = boss.position.x
			boss.receive_satisfaction(
				boss.maximum_appetite * delta / SMOKE_TEST_BOSS_CLEAR_DURATION
			)
		elif phase == Phase.FORWARD:
			cart.target_x = 3.6 + sin(state.elapsed_seconds * 1.7) * 2.45
		_check_smoke_timeout()
	_debug_accumulator += delta
	if _debug_accumulator >= 0.25:
		_debug_accumulator = 0.0
		hud.set_debug_text(
			"FPS %d  食客 %d  投射物 %d\n门 %d  奖励 %d  击败 %d" % [
				Engine.get_frames_per_second(),
				customers.size(),
				projectiles.get_child_count(),
				state.gate_choices,
				state.dropped_upgrades,
				state.customers_satisfied,
			]
		)
		_refresh_debug_menu()


func is_world_scrolling() -> bool:
	return phase == Phase.FORWARD


func forward_progress() -> float:
	if director == null or director.timeline == null or state == null:
		return 0.0
	return clampf(
		state.forward_distance / maxf(0.001, director.timeline.course_distance),
		0.0,
		1.0
	)


func forward_speed_multiplier() -> float:
	if director == null or director.timeline == null:
		return 1.0
	return director.timeline.speed_multiplier_at_progress(forward_progress())


# 前进距离、背景速度和疲劳共用同一压力档；切档只触发一次可读反馈。
func _advance_forward_progress(delta: float) -> void:
	if director == null or director.timeline == null:
		return
	var progress_before: float = forward_progress()
	var tier: int = director.timeline.speed_tier_at_progress(progress_before)
	var multiplier: float = director.timeline.forward_speed_multipliers[tier]
	world_scroll_speed = BASE_WORLD_SCROLL_SPEED * multiplier
	background.scroll_speed = world_scroll_speed
	var pressure_ratio: float = director.timeline.pressure_ratio_at_progress(progress_before)
	state.cart_base_speed_factor = lerpf(
		1.0,
		director.timeline.minimum_cart_base_speed_factor,
		pressure_ratio
	)
	state.forward_distance += world_scroll_speed * delta
	var next_tier: int = director.timeline.speed_tier_at_progress(forward_progress())
	if next_tier != _current_speed_tier:
		_current_speed_tier = next_tier
		if next_tier > 0:
			_crosswind_sign *= -1.0
			hud.show_toast(
				"路况升级 · 前进 %.1f× · %s侧风" % [
					director.timeline.forward_speed_multipliers[next_tier],
					"向右" if _crosswind_sign > 0.0 else "向左",
				],
				Color("#f0c45f")
			)


# 距离阈值只生成普通门和普通波次；精英与Boss仍由时间轴事件负责。
func _advance_distance_spawns() -> void:
	if director == null or director.timeline == null or _normal_waves_suspended:
		return
	var progress: float = forward_progress()
	while _next_gate_index < director.timeline.normal_gate_count:
		var gate_progress: float = float(_next_gate_index + 1) / float(
			director.timeline.normal_gate_count + 1
		)
		if progress + 0.000001 < gate_progress:
			break
		_queue_gate(_next_gate_index, false, _current_baseline_appetite())
		_next_gate_index += 1
	while _normal_wave_index < director.timeline.normal_wave_count:
		var wave_progress: float = float(_normal_wave_index + 1) / float(
			director.timeline.normal_wave_count + 1
		)
		if progress + 0.000001 < wave_progress:
			break
		_queue_normal_wave(_normal_wave_index)
		_normal_wave_index += 1


# 保留当前五波类型轮换和每四波一次双客，生成位置按路程、胃口按请求时刻锁定。
func _queue_normal_wave(wave_index: int) -> void:
	var pattern: int = wave_index % 5
	var primary: CustomerData = basic_guest_data
	if pattern == 2:
		primary = fast_guest_data
	elif pattern == 4:
		primary = ranged_guest_data
	var baseline: float = _current_baseline_appetite()
	_queue_customer(primary, baseline)
	if wave_index % 4 == 3:
		_queue_customer(basic_guest_data if pattern == 4 else fast_guest_data, baseline)


func current_headwind_speed() -> float:
	if director == null or director.timeline == null:
		return 0.0
	return (
		director.timeline.headwind_factor
		* BASE_WORLD_SCROLL_SPEED
		* maxf(0.0, forward_speed_multiplier() - 1.0)
	)


func current_crosswind_speed() -> float:
	if director == null or director.timeline == null:
		return 0.0
	return (
		Playfield.design_to_world(director.timeline.max_crosswind_speed)
		* director.timeline.pressure_ratio_at_progress(forward_progress())
		* _crosswind_sign
	)


func can_weapons_fire() -> bool:
	return phase == Phase.FORWARD or phase == Phase.BOSS


func _check_smoke_timeout() -> void:
	if state.elapsed_seconds <= SMOKE_TEST_TIMEOUT:
		return
	_save_playtest_record(&"smoke_timeout")
	push_error(
		"SMOKE_TEST_FAILED timeout phase=%d gates=%d requests=%d customers=%d drops=%d specials=%d boss_active=%s boss_remaining=%.1f boss_position=%s boss_state=%d projectiles=%d" % [
			phase,
			state.gate_choices,
			_forward_spawn_requests.size(),
			customers.size(),
			drops.get_child_count(),
			state.special_choice_records.size(),
			str(boss != null and is_instance_valid(boss) and boss.active),
			boss.remaining_appetite if boss != null and is_instance_valid(boss) else -1.0,
			str(boss.position if boss != null and is_instance_valid(boss) else Vector3.ZERO),
			boss._state if boss != null and is_instance_valid(boss) else -1,
			projectiles.get_child_count(),
		]
	)
	Engine.time_scale = 1.0
	get_tree().quit(1)


# 正常运行读取场景节点；脱离主场景的规则验证继续使用设计回退值。
func cart_destination_z() -> float:
	if cart == null:
		return Playfield.CART_Z
	return cart.position.z


# 所有3D对象直接使用米制X/Z坐标；仅策划数据与触控输入在边界处从设计像素换算。
func logic_position(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	if not is_inside_tree() or not node.is_inside_tree():
		return node.position
	return to_local(node.global_position)


func customer_collides_with_cart(customer: Customer3D) -> bool:
	if customer == null or cart == null:
		return false
	return customer.collision_rect_xz().intersects(cart.collision_rect_xz())


# 高压档或低帧率下一帧可能跨过餐车，使用前后包围矩形补足连续接触判定。
func customer_swept_collides_with_cart(customer: Customer3D, previous_z: float) -> bool:
	if customer == null or cart == null:
		return false
	var current_rect: Rect2 = customer.collision_rect_xz()
	var previous_rect: Rect2 = current_rect
	previous_rect.position.y += previous_z - customer.position.z
	return previous_rect.merge(current_rect).intersects(cart.collision_rect_xz())


func get_priority_target() -> Node3D:
	return _get_priority_target(&"")


func get_priority_target_for_food(food: FoodData) -> Node3D:
	return _get_priority_target(food.id if food != null else &"")


func _get_priority_target(food_id: StringName) -> Node3D:
	var best_target: Node3D = null
	var best_forward: float = INF
	var best_horizontal: float = INF
	var best_spawn_index: int = 2147483647
	for customer: Customer3D in customers:
		if not is_instance_valid(customer) or not customer.active or customer.position.z >= cart.position.z:
			continue
		if not _target_is_allowed_for_food(food_id, logic_position(customer)):
			continue
		var forward: float = cart.position.z - customer.position.z
		var horizontal: float = absf(customer.position.x - cart.position.x)
		if _target_is_better(forward, horizontal, customer.spawn_index, best_forward, best_horizontal, best_spawn_index):
			best_target = customer
			best_forward = forward
			best_horizontal = horizontal
			best_spawn_index = customer.spawn_index
	for child: Node in gates.get_children():
		if not child is UpgradeGate3D or child.is_queued_for_deletion():
			continue
		var gate: UpgradeGate3D = child as UpgradeGate3D
		if gate.position.z >= cart.position.z:
			continue
		var gate_target: Node3D = gate.target_for_cart_x(cart.position.x)
		if gate_target == null:
			continue
		if not _target_is_allowed_for_food(food_id, logic_position(gate_target)):
			continue
		var gate_forward: float = cart.position.z - gate.position.z
		var gate_horizontal: float = absf(logic_position(gate_target).x - logic_position(cart).x)
		if _target_is_better(gate_forward, gate_horizontal, gate.spawn_index, best_forward, best_horizontal, best_spawn_index):
			best_target = gate_target
			best_forward = gate_forward
			best_horizontal = gate_horizontal
			best_spawn_index = gate.spawn_index
	for child: Node in drops.get_children():
		if not child is UpgradeDrop3D or child.is_queued_for_deletion():
			continue
		var reward_gate: UpgradeDrop3D = child as UpgradeDrop3D
		if reward_gate.position.z >= cart.position.z:
			continue
		var reward_target: Node3D = reward_gate.target_for_cart_x(cart.position.x)
		if reward_target == null:
			continue
		if not _target_is_allowed_for_food(food_id, logic_position(reward_target)):
			continue
		var reward_forward: float = cart.position.z - reward_gate.position.z
		var reward_horizontal: float = absf(logic_position(reward_target).x - logic_position(cart).x)
		if _target_is_better(reward_forward, reward_horizontal, reward_gate.spawn_index, best_forward, best_horizontal, best_spawn_index):
			best_target = reward_target
			best_forward = reward_forward
			best_horizontal = reward_horizontal
			best_spawn_index = reward_gate.spawn_index
	if boss != null and is_instance_valid(boss) and boss.active:
		if not _target_is_allowed_for_food(food_id, logic_position(boss)):
			return best_target
		var boss_forward: float = cart.position.z - boss.position.z
		var boss_horizontal: float = absf(boss.position.x - cart.position.x)
		if _target_is_better(boss_forward, boss_horizontal, 2000000000, best_forward, best_horizontal, best_spawn_index):
			best_target = boss
	return best_target


# 法棍只在道路正前方90°扇区寻敌；-Z为北，左右45°边界均计入。
func _target_is_allowed_for_food(food_id: StringName, target_position: Vector3) -> bool:
	if food_id != &"baguette":
		return true
	var offset: Vector3 = target_position - logic_position(cart)
	return (
		offset.z < -TARGET_CONE_EPSILON
		and absf(offset.x) <= -offset.z + TARGET_CONE_EPSILON
	)


func spawn_projectile(
	start_position: Vector3,
	direction: Vector3,
	food: FoodData,
	amount: float,
	speed: float,
	radius: float,
	target: Node3D,
	orbit_phase: float = 0.0,
	giant_baguette: bool = false
) -> void:
	var projectile: FoodProjectile3D = PROJECTILE_SCENE.instantiate() as FoodProjectile3D
	projectiles.add_child(projectile)
	var should_home: bool = (
		not giant_baguette
		and (
			food.initial_tracking_mode == FoodData.TrackingMode.HOMING
			or state.is_food_homing(food.id)
		)
	)
	var lifetime: float = (
		state.effective_duration(food) * state.baguette_giant_duration_multiplier
		if giant_baguette
		else state.effective_duration(food)
	)
	var hit_count: int = (
		state.baguette_giant_pierce_count
		if giant_baguette
		else state.effective_pierce_count(food)
	)
	var breathing_enabled: bool = (
		food.id == &"mushroom"
		and state.has_food_evolution(&"mushroom_breath")
	)
	var giant_range_scale: float = (
		state.effective_projectile_radius(food) / maxf(0.001, food.projectile_radius)
	)
	projectile.configure(
		self,
		start_position,
		direction,
		food,
		amount,
		speed,
		_projectile_environment_velocity(food, giant_baguette),
		radius,
		lifetime,
		hit_count,
		target,
		should_home,
		orbit_phase,
		giant_baguette,
		Playfield.REGION_WIDTH * state.baguette_giant_width_regions * giant_range_scale if giant_baguette else 0.0,
		breathing_enabled
	)
	if giant_baguette and is_instance_valid(background):
		background.shake_camera()


# 蘑菇随餐车环绕不受位移风；巨型法棍只承受普通投射物四分之一风偏。
func _projectile_environment_velocity(food: FoodData, giant_baguette: bool) -> Vector3:
	if food == null or food.attack_kind == FoodData.AttackKind.ORBITING_MUSHROOM:
		return Vector3.ZERO
	var susceptibility: float = 0.25 if giant_baguette else 1.0
	return Vector3(
		current_crosswind_speed(),
		0.0,
		current_headwind_speed()
	) * susceptibility


func resolve_projectile_hits(projectile: FoodProjectile3D) -> void:
	if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
		return
	for customer: Customer3D in customers:
		if not is_instance_valid(customer) or not customer.active or not projectile.can_hit(customer):
			continue
		if projectile.overlaps_target(logic_position(customer), customer.hit_radius()):
			var applied: float = minf(projectile.satisfaction, customer.remaining_appetite)
			customer.receive_satisfaction(projectile.satisfaction)
			state.record_food_satisfaction(projectile.food_id, applied)
			if projectile.register_hit(customer):
				return
	for child: Node in gates.get_children():
		if not child is UpgradeGate3D or child.is_queued_for_deletion():
			continue
		var gate: UpgradeGate3D = child as UpgradeGate3D
		if gate.try_receive_projectile(projectile):
			return
	for child: Node in drops.get_children():
		if not child is UpgradeDrop3D or child.is_queued_for_deletion():
			continue
		var reward_gate: UpgradeDrop3D = child as UpgradeDrop3D
		if reward_gate.try_receive_projectile(projectile):
			return
	if boss != null and is_instance_valid(boss) and boss.active and projectile.can_hit(boss):
		if projectile.overlaps_target(logic_position(boss), boss.hit_radius()):
			var applied: float = minf(projectile.satisfaction, boss.remaining_appetite)
			boss.receive_satisfaction(projectile.satisfaction)
			state.record_food_satisfaction(projectile.food_id, applied)
			projectile.register_hit(boss)


func on_gate_selected(
	upgrade: UpgradeData,
	start_food_gate: bool,
	remaining_base_health: float = 0.0
) -> void:
	if start_food_gate:
		if upgrade == null:
			push_error("START_FOOD_SELECTION_MISSING")
			return
		var selected_food: FoodData = _food_data_for_id(upgrade.id)
		if selected_food == null:
			push_error("START_FOOD_NOT_UNLOCKED food=%s" % String(upgrade.id))
			return
		weapon_controller.add_food(selected_food)
		hud.show_toast("%s装车！自动寻找最近的食客" % selected_food.display_name)
		return
	state.apply_upgrade(upgrade)
	cart.play_upgrade_feedback(upgrade.rarity_color)
	hud.show_toast(
		"%s：%s\n%s" % [
			upgrade.display_name,
			upgrade.effect_text(state.maximum_durability),
			_cumulative_upgrade_text(upgrade.kind),
		],
		upgrade.rarity_color
	)
	if remaining_base_health > 0.0:
		damage_cart(remaining_base_health, "撞门")


func on_customer_reward_gate_collected(upgrade: UpgradeData) -> void:
	state.apply_upgrade(upgrade, false)
	cart.play_upgrade_feedback(upgrade.rarity_color)
	hud.show_toast(
		"奖励门 %s：%s\n%s" % [
			upgrade.display_name,
			upgrade.effect_text(state.maximum_durability),
			_cumulative_upgrade_text(upgrade.kind),
		],
		upgrade.rarity_color
	)


# 物理强化按已拥有食材显示实际倍率，避免把门牌原始百分比误读为线性终值。
func _cumulative_upgrade_text(kind: UpgradeData.Kind) -> String:
	if kind not in [
		UpgradeData.Kind.WINE,
		UpgradeData.Kind.SCALLION,
		UpgradeData.Kind.STARCH,
	]:
		if kind == UpgradeData.Kind.LIGHT_CART:
			var bonus: float = state.effective_cart_speed_bonus(Cart3D.BASE_MOVE_SPEED_DESIGN)
			return "实际横移加值 +%.0f · 基础保留 %.0f%%" % [
				bonus,
				state.cart_base_speed_factor * 100.0,
			]
		return state.cumulative_effect_text(kind)
	var texts: PackedStringArray = []
	for food_id: StringName in state.foods:
		var food: FoodData = _food_data_for_id(food_id)
		if food == null:
			continue
		var multiplier: float = 1.0
		match kind:
			UpgradeData.Kind.WINE:
				if food.attack_kind == FoodData.AttackKind.ORBITING_MUSHROOM:
					multiplier = state.effective_orbit_angular_speed(food) / food.orbit_angular_speed
				else:
					multiplier = state.effective_projectile_speed(food) / food.projectile_speed
			UpgradeData.Kind.SCALLION:
				multiplier = state.effective_projectile_radius(food) / food.projectile_radius
			UpgradeData.Kind.STARCH:
				multiplier = state.effective_duration(food) / food.base_lifetime
		texts.append("%s×%.2f" % [food.display_name, multiplier])
	return "实际：%s" % (" · ".join(texts) if not texts.is_empty() else "待装车后生效")


func damage_cart(amount: float, source: String) -> void:
	if _debug_invincible:
		hud.show_toast("DEBUG 无敌：已忽略 %s 的伤害" % source, Color("#a9e69d"))
		return
	var durability_before: float = state.current_durability
	var shield_before: float = state.temporary_shield
	if cart.take_damage(amount):
		var durability_damage: float = durability_before - state.current_durability
		var shield_damage: float = shield_before - state.temporary_shield
		if shield_damage > 0.0 and durability_damage > 0.0:
			hud.show_toast(
				"%s：护盾 -%.0f · 耐久 -%.0f" % [source, shield_damage, durability_damage],
				Color("#ffb45e")
			)
		elif shield_damage > 0.0:
			hud.show_toast("%s：护盾 -%.0f" % [source, shield_damage], Color("#78d8ff"))
		else:
			hud.show_toast("%s：耐久 -%.0f" % [source, durability_damage], Color("#ff7858"))


func _on_timeline_event(event_id: StringName) -> void:
	if event_id == &"start_gate":
		_queue_gate(0, true)
	elif event_id == &"basic":
		_queue_customer(basic_guest_data, _scheduled_baseline_appetite(event_id))
	elif event_id == &"fast":
		_queue_customer(fast_guest_data, _scheduled_baseline_appetite(event_id))
	elif event_id == &"ranged":
		_queue_customer(ranged_guest_data, _scheduled_baseline_appetite(event_id))
	elif event_id == &"elite":
		_queue_elite()
	elif event_id == &"boss":
		_start_boss()
	elif String(event_id).begins_with("gate_"):
		var gate_index: int = String(event_id).trim_prefix("gate_").to_int()
		_queue_gate(gate_index, false, _scheduled_baseline_appetite(event_id))


# 将普通食客加入统一队列，避免同帧双生或与门产生视觉重叠。
func _queue_customer(customer_data: CustomerData, baseline_appetite: float = 0.0) -> void:
	var request: ForwardSpawnRequest = ForwardSpawnRequest.new(ForwardSpawnRequest.Kind.CUSTOMER)
	request.customer_data = customer_data
	request.baseline_appetite = baseline_appetite
	_forward_spawn_requests.append(request)


func _queue_elite() -> void:
	_forward_spawn_requests.append(ForwardSpawnRequest.new(ForwardSpawnRequest.Kind.ELITE))


func _queue_gate(index: int, is_start_gate: bool, baseline_appetite: float = 0.0) -> void:
	var request: ForwardSpawnRequest = ForwardSpawnRequest.new(ForwardSpawnRequest.Kind.GATE)
	request.gate_index = index
	request.start_food_gate = is_start_gate
	request.baseline_appetite = baseline_appetite
	_forward_spawn_requests.append(request)


# 普通食客与门可从当前安全项中先行生成；精英保持事件屏障，后续请求不得越过。
func _process_spawn_requests() -> void:
	var spawned_this_frame: int = 0
	while not _forward_spawn_requests.is_empty() and spawned_this_frame < 4:
		var request_index: int = _next_safe_spawn_request_index()
		if request_index < 0:
			return
		var request: ForwardSpawnRequest = _forward_spawn_requests[request_index]
		_forward_spawn_requests.remove_at(request_index)
		match request.kind:
			ForwardSpawnRequest.Kind.CUSTOMER:
				_spawn_customer_now(
					request.customer_data,
					request.baseline_appetite,
					request.spawn_first_region
				)
			ForwardSpawnRequest.Kind.ELITE:
				_spawn_elite_now()
			ForwardSpawnRequest.Kind.GATE:
				_spawn_gate_now(request.gate_index, request.start_food_gate, request.baseline_appetite)
		spawned_this_frame += 1


# 精英是不可绕过的节奏节点；其前方普通请求只要安全便可消化队列积压。
func _next_safe_spawn_request_index() -> int:
	for index: int in range(_forward_spawn_requests.size()):
		var request: ForwardSpawnRequest = _forward_spawn_requests[index]
		if _spawn_request_is_safe(request):
			return index
		if request.kind == ForwardSpawnRequest.Kind.ELITE:
			break
	return -1


# 对候选对象与全部活动前进对象做匀速路径预测，追尾风险解除后才生成。
func _spawn_request_is_safe(request: ForwardSpawnRequest) -> bool:
	var candidate_z: float = 0.0 if request.start_food_gate else Playfield.FORWARD_SPAWN_Z
	var speed_multiplier: float = forward_speed_multiplier()
	var candidate_speed: float = FORWARD_GATE_SPEED * speed_multiplier
	var candidate_is_customer: bool = false
	if request.kind == ForwardSpawnRequest.Kind.CUSTOMER:
		if request.customer_data == null:
			return false
		candidate_z = Playfield.FORWARD_SPAWN_Z
		var first_region: int = _find_safe_customer_first_region(
			request.customer_data,
			candidate_z,
			(
				BASE_WORLD_SCROLL_SPEED
				+ Playfield.design_to_world(request.customer_data.move_speed)
			) * speed_multiplier
		)
		if first_region < 0:
			return false
		request.spawn_first_region = first_region
		candidate_is_customer = true
		candidate_speed = (
			BASE_WORLD_SCROLL_SPEED + Playfield.design_to_world(request.customer_data.move_speed)
		) * speed_multiplier
	elif request.kind == ForwardSpawnRequest.Kind.ELITE:
		candidate_z = Playfield.FORWARD_SPAWN_Z
		candidate_speed = (
			BASE_WORLD_SCROLL_SPEED + Playfield.design_to_world(elite_guest_data.move_speed)
		) * speed_multiplier
	for customer: Customer3D in customers:
		if not is_instance_valid(customer) or not customer.active:
			continue
		if candidate_is_customer:
			continue
		if not playfield.forward_paths_are_separated(
			candidate_z,
			candidate_speed,
			customer.position.z,
			customer.travel_speed(),
			Playfield.FORWARD_SPAWN_RESERVATION_DISTANCE,
			cart_destination_z()
		):
			return false
	for child: Node in gates.get_children():
		if not child is UpgradeGate3D or child.is_queued_for_deletion():
			continue
		var gate: UpgradeGate3D = child as UpgradeGate3D
		if not playfield.forward_paths_are_separated(
			candidate_z,
			candidate_speed,
			gate.position.z,
			gate.travel_speed(),
			Playfield.FORWARD_SPAWN_RESERVATION_DISTANCE,
			cart_destination_z()
		):
			return false
	for child: Node in drops.get_children():
		if not child is UpgradeDrop3D or child.is_queued_for_deletion():
			continue
		var reward_gate: UpgradeDrop3D = child as UpgradeDrop3D
		if not playfield.forward_paths_are_separated(
			candidate_z,
			candidate_speed,
			reward_gate.position.z,
			reward_gate.travel_speed(),
			Playfield.FORWARD_SPAWN_RESERVATION_DISTANCE,
			cart_destination_z()
		):
			return false
	return true


# 普通食客可在合法占位中横向错开；只选择整条接近路径都不会追尾的位置。
func _find_safe_customer_first_region(
	customer_data: CustomerData,
	candidate_z: float,
	candidate_speed: float
) -> int:
	var occupied_regions: int = customer_data.occupied_regions
	var max_start: int = Playfield.REGION_COUNT - occupied_regions
	var default_first: int = (
		(_spawn_counter + 1) * 2 + customer_data.spawn_pattern_offset()
	) % (max_start + 1)
	var candidate_width: float = maxf(
		0.82,
		float(occupied_regions) * Playfield.REGION_WIDTH - 0.18
	)
	for offset: int in range(max_start + 1):
		var first_region: int = (default_first + offset) % (max_start + 1)
		var candidate_x: float = playfield.spawn_x(first_region, occupied_regions)
		var candidate_rect_x: Rect2 = Rect2(
			candidate_x - candidate_width * 0.5,
			0.0,
			candidate_width,
			1.0
		)
		var safe: bool = true
		for customer: Customer3D in customers:
			if not is_instance_valid(customer) or not customer.active:
				continue
			var existing_rect: Rect2 = customer.collision_rect_xz()
			var existing_rect_x: Rect2 = Rect2(
				existing_rect.position.x,
				0.0,
				existing_rect.size.x,
				1.0
			)
			if not candidate_rect_x.intersects(existing_rect_x):
				continue
			if not playfield.forward_paths_are_separated(
				candidate_z,
				candidate_speed,
				customer.position.z,
				customer.travel_speed(),
				Playfield.FORWARD_SPAWN_RESERVATION_DISTANCE,
				cart_destination_z()
			):
				safe = false
				break
		if safe:
			return first_region
	return -1


func _spawn_customer_now(
	customer_data: CustomerData,
	scheduled_baseline_appetite: float = 0.0,
	spawn_first_region: int = -1
) -> void:
	state.normal_customers_spawned += 1
	_spawn_counter += 1
	var customer: Customer3D = _instantiate_customer(customer_data)
	var max_start: int = Playfield.REGION_COUNT - customer_data.occupied_regions
	var first_region: int = spawn_first_region
	if first_region < 0:
		first_region = (
			_spawn_counter * 2 + customer_data.spawn_pattern_offset()
		) % (max_start + 1)
	customer.position = Vector3(
		playfield.spawn_x(first_region, customer_data.occupied_regions),
		0.0,
		Playfield.FORWARD_SPAWN_Z
	)
	entities.add_child(customer)
	var baseline_appetite: float = scheduled_baseline_appetite
	if baseline_appetite <= 0.0:
		baseline_appetite = _current_baseline_appetite()
	var reward_upgrade: UpgradeData = _roll_customer_reward()
	var appetite: float = customer_data.appetite_at(
		baseline_appetite,
		reward_upgrade.value_ratio,
		reward_upgrade.source_scale
	)
	customer.configure(customer_data, self, _spawn_counter, appetite, reward_upgrade, baseline_appetite)
	customer.satisfied.connect(_on_customer_satisfied)
	customer.collided_with_cart.connect(_on_customer_collided_with_cart)
	customer.escaped.connect(_on_customer_escaped)
	customer.ranged_attack.connect(_on_customer_ranged_attack)
	customers.append(customer)


func _spawn_elite_now() -> void:
	_elite_started_at = state.elapsed_seconds
	_spawn_counter += 1
	var elite: Customer3D = _instantiate_customer(elite_guest_data)
	elite.position = Vector3(3.6, 0.0, Playfield.FORWARD_SPAWN_Z)
	entities.add_child(elite)
	var appetite: float = elite_guest_data.appetite_at(_current_baseline_appetite())
	elite.configure(elite_guest_data, self, _spawn_counter, appetite)
	elite.satisfied.connect(_on_customer_satisfied)
	elite.collided_with_cart.connect(_on_customer_collided_with_cart)
	elite.escaped.connect(_on_customer_escaped)
	elite.ranged_attack.connect(_on_customer_ranged_attack)
	customers.append(elite)
	hud.set_phase("精英检查 · 六区无法绕行")
	hud.show_toast("六席贵客挡住整条路，尽快满足它！", Color("#f0c45f"))


# 食客数据只选择完整预制场景；错误或缺失配置回退到通用纸片场景。
func _instantiate_customer(customer_data: CustomerData) -> Customer3D:
	var packed_scene: PackedScene = customer_data.customer_scene
	if packed_scene == null:
		packed_scene = DEFAULT_CUSTOMER_SCENE
	var customer: Customer3D = packed_scene.instantiate() as Customer3D
	if customer != null:
		return customer
	push_error("食客场景根节点必须继承 Customer3D: %s" % String(customer_data.id))
	return DEFAULT_CUSTOMER_SCENE.instantiate() as Customer3D


func _spawn_gate_now(_index: int, is_start_gate: bool, scheduled_baseline_appetite: float = 0.0) -> void:
	_spawn_counter += 1
	var gate: UpgradeGate3D = GATE_SCENE.instantiate() as UpgradeGate3D
	gates.add_child(gate)
	if is_start_gate:
		var start_options: Array[UpgradeData] = _roll_start_food_options()
		if start_options.size() != 2:
			push_error("START_FOOD_POOL_EMPTY")
			gate.queue_free()
			return
		gate.configure(
			self,
			start_options[0],
			start_options[1],
			true,
			_current_baseline_appetite(),
			_spawn_counter
		)
		return
	var baseline_appetite: float = scheduled_baseline_appetite
	if baseline_appetite <= 0.0:
		baseline_appetite = _current_baseline_appetite()
	var options: Array[UpgradeData] = _roll_normal_upgrade_options(2)
	if options.size() != 2:
		push_error("NORMAL_UPGRADE_POOL_TOO_SMALL")
		gate.queue_free()
		return
	state.record_normal_upgrade_offer(options)
	gate.configure(self, options[0], options[1], false, baseline_appetite, _spawn_counter)


func _start_boss() -> void:
	if phase == Phase.BOSS or phase == Phase.RESULTS or phase == Phase.FAILED:
		return
	_normal_waves_suspended = true
	if _has_pending_boss_blocker():
		_boss_pending = true
		return
	_begin_boss()


# Boss等待既定普通门和精英完成；普通食客可在正式开战清场时统一离场。
func _has_pending_boss_blocker() -> bool:
	if not _reward_spawn_requests.is_empty():
		return true
	for child: Node in gates.get_children():
		if child is UpgradeGate3D and not child.is_queued_for_deletion():
			return true
	for customer: Customer3D in customers:
		if (
			is_instance_valid(customer)
			and customer.active
			and customer.data != null
			and customer.data.category == CustomerData.Category.ELITE
		):
			return true
	for request: ForwardSpawnRequest in _forward_spawn_requests:
		if request.kind in [ForwardSpawnRequest.Kind.GATE, ForwardSpawnRequest.Kind.ELITE]:
			return true
	for child: Node in drops.get_children():
		if child is UpgradeDrop3D and not child.is_queued_for_deletion():
			return true
	return false


# 最后一门完成后才停止道路并清场，避免编辑器位置变化吞掉既定强化门。
func _begin_boss() -> void:
	_boss_pending = false
	_bosses_started += 1
	phase = Phase.BOSS
	background.scrolling = false
	_clear_forward_objects()
	_boss_started_at = state.elapsed_seconds
	boss = BOSS_SCENE.instantiate() as PrototypeBoss3D
	entities.add_child(boss)
	boss.configure(boss_data, self, _current_baseline_appetite())
	cart.begin_boss_movement(boss)
	boss.satisfied.connect(_on_boss_satisfied)
	hud.set_phase("Boss服务 · 自由移动并自动反击")
	hud.show_toast("前进停止！危险预警后会出现反击窗口", Color("#ff7957"))


func _on_customer_satisfied(customer: Customer3D) -> void:
	_finish_customer(customer, false)


func _on_customer_collided_with_cart(customer: Customer3D) -> void:
	var remaining: float = customer.remaining_appetite
	damage_cart(remaining, "漏客投诉")
	_finish_customer(customer, true)


# 绕开餐车的食客只离开模拟，不产生伤害、击败或掉落。
func _on_customer_escaped(customer: Customer3D) -> void:
	customers.erase(customer)
	customer.queue_free()


func _finish_customer(customer: Customer3D, collided: bool) -> void:
	var was_elite: bool = customer.data.category == CustomerData.Category.ELITE
	var defeat_position: Vector3 = logic_position(customer)
	var reward_upgrade: UpgradeData = customer.reward_upgrade
	var reward_baseline_appetite: float = customer.reward_baseline_appetite
	var occupied_regions: int = customer.data.occupied_regions
	state.customers_satisfied += 1
	if collided:
		state.collided_defeats += 1
	customers.erase(customer)
	customer.queue_free()
	if phase == Phase.FAILED:
		return
	if was_elite:
		state.elite_duration = state.elapsed_seconds - _elite_started_at
		state.elite_durations.append(state.elite_duration)
		phase = Phase.CHOICE
		hud.set_phase("特别赏赐 · 三选一")
		hud.show_toast("撞击也算击败！" if collided else "精英已击败！", Color("#f0c45f"))
		_show_special_choices(&"elite", "六席贵客满意了！挑一份特别赏赐")
	else:
		state.normal_defeats += 1
		_spawn_customer_reward_gate(defeat_position, reward_upgrade, reward_baseline_appetite, occupied_regions)
		hud.show_toast("撞击击败，留下奖励门" if collided else "食客已满足，留下奖励门", Color("#f0d36e"))


func _spawn_customer_reward_gate(
	start_position: Vector3,
	upgrade: UpgradeData,
	baseline_appetite: float,
	occupied_regions: int
) -> void:
	if upgrade == null:
		return
	var safe_z: float = _find_reward_gate_spawn_z(
		start_position.z,
		start_position.x,
		occupied_regions
	)
	if is_inf(safe_z):
		_reward_spawn_requests.append(RewardSpawnRequest.new(
			start_position,
			upgrade,
			baseline_appetite,
			occupied_regions
		))
		return
	_spawn_customer_reward_gate_now(
		start_position,
		upgrade,
		baseline_appetite,
		occupied_regions,
		safe_z
	)


func _spawn_customer_reward_gate_now(
	start_position: Vector3,
	upgrade: UpgradeData,
	baseline_appetite: float,
	occupied_regions: int,
	safe_z: float
) -> void:
	state.upgrade_drops_spawned += 1
	_spawn_counter += 1
	var drop: UpgradeDrop3D = REWARD_GATE_SCENE.instantiate() as UpgradeDrop3D
	start_position.z = safe_z
	drops.add_child(drop)
	drop.configure(self, upgrade, start_position, baseline_appetite, occupied_regions, _spawn_counter)


func _process_reward_spawn_requests(delta: float) -> void:
	var spawned_this_frame: int = 0
	var index: int = 0
	while index < _reward_spawn_requests.size() and spawned_this_frame < 4:
		var request: RewardSpawnRequest = _reward_spawn_requests[index]
		# 等待避让期间锚点随道路前进，避免最终生成点落后于食客消失位置。
		request.start_position.z += FORWARD_GATE_SPEED * forward_speed_multiplier() * delta
		var safe_z: float = _find_reward_gate_spawn_z(
			request.start_position.z,
			request.start_position.x,
			request.occupied_regions
		)
		if is_inf(safe_z):
			index += 1
			continue
		_reward_spawn_requests.remove_at(index)
		_spawn_customer_reward_gate_now(
			request.start_position,
			request.upgrade,
			request.baseline_appetite,
			request.occupied_regions,
			safe_z
		)
		spawned_this_frame += 1


# 奖励门只在横向实际相交时做近场双向搜索，并始终选择离食客最近的可用位置。
func _find_reward_gate_spawn_z(
	preferred_z: float,
	preferred_x: float,
	occupied_regions: int
) -> float:
	if _reward_gate_spawn_is_safe(preferred_z, preferred_x, occupied_regions):
		return preferred_z
	var distance: float = REWARD_GATE_SEARCH_STEP
	while distance <= REWARD_GATE_SEARCH_LIMIT + 0.001:
		var toward_cart_z: float = preferred_z + distance
		if (
			toward_cart_z < cart_destination_z() - 0.5
			and _reward_gate_spawn_is_safe(toward_cart_z, preferred_x, occupied_regions)
		):
			return toward_cart_z
		var toward_far_z: float = preferred_z - distance
		if _reward_gate_spawn_is_safe(toward_far_z, preferred_x, occupied_regions):
			return toward_far_z
		distance += REWARD_GATE_SEARCH_STEP
	return INF


func _reward_gate_spawn_is_safe(
	candidate_z: float,
	candidate_x: float,
	occupied_regions: int
) -> bool:
	var candidate_speed: float = FORWARD_GATE_SPEED * forward_speed_multiplier()
	var candidate_width: float = maxf(
		0.82,
		float(clampi(occupied_regions, 1, Playfield.REGION_COUNT)) * Playfield.REGION_WIDTH - 0.18
	)
	var candidate_rect_x: Rect2 = Rect2(
		candidate_x - candidate_width * 0.5,
		0.0,
		candidate_width,
		1.0
	)
	for customer: Customer3D in customers:
		if not is_instance_valid(customer) or not customer.active:
			continue
		var customer_rect: Rect2 = customer.collision_rect_xz()
		var customer_rect_x: Rect2 = Rect2(
			customer_rect.position.x,
			0.0,
			customer_rect.size.x,
			1.0
		)
		if not candidate_rect_x.intersects(customer_rect_x):
			continue
		if not playfield.forward_paths_are_separated(
			candidate_z,
			candidate_speed,
			customer.position.z,
			customer.travel_speed(),
			REWARD_GATE_MIN_CENTER_DISTANCE,
			cart_destination_z()
		):
			return false
	for child: Node in gates.get_children():
		if not child is UpgradeGate3D or child.is_queued_for_deletion():
			continue
		var gate: UpgradeGate3D = child as UpgradeGate3D
		if not playfield.forward_paths_are_separated(
			candidate_z,
			candidate_speed,
			gate.position.z,
			gate.travel_speed(),
			REWARD_GATE_MIN_CENTER_DISTANCE,
			cart_destination_z()
		):
			return false
	for child: Node in drops.get_children():
		if not child is UpgradeDrop3D or child.is_queued_for_deletion():
			continue
		var reward_gate: UpgradeDrop3D = child as UpgradeDrop3D
		var reward_width: float = reward_gate._panel_width()
		var reward_rect_x: Rect2 = Rect2(
			reward_gate.position.x - reward_width * 0.5,
			0.0,
			reward_width,
			1.0
		)
		if not candidate_rect_x.intersects(reward_rect_x):
			continue
		if not playfield.forward_paths_are_separated(
			candidate_z,
			candidate_speed,
			reward_gate.position.z,
			reward_gate.travel_speed(),
			REWARD_GATE_MIN_CENTER_DISTANCE,
			cart_destination_z()
		):
			return false
	return true


func _on_customer_ranged_attack(_customer: Customer3D, amount: float) -> void:
	damage_cart(amount, "拍桌投诉")


func _on_special_choice_selected(choice_id: StringName) -> void:
	if not _active_special_choices.has(choice_id):
		push_error("SPECIAL_CHOICE_REJECTED choice=%s" % String(choice_id))
		return
	var upgrade: SpecialUpgradeData = _special_upgrades_by_id.get(choice_id)
	if upgrade == null:
		push_error("SPECIAL_CHOICE_DATA_MISSING choice=%s" % String(choice_id))
		return
	get_tree().paused = false
	state.record_special_choice(choice_id)
	match upgrade.effect_kind:
		SpecialUpgradeData.EffectKind.FOOD_CARD:
			_apply_food_card(_food_data_for_id(upgrade.target_id))
		SpecialUpgradeData.EffectKind.SERVING:
			var serving_amount: int = maxi(1, roundi(upgrade.effect_value))
			state.servings += serving_amount
			state.add_special(choice_id)
			hud.show_toast("%s：每种食材多发 %d 份" % [upgrade.display_name, serving_amount])
		SpecialUpgradeData.EffectKind.TARGET_AIM:
			state.enable_target_aim(upgrade.target_id)
			state.add_special(choice_id)
			hud.show_toast("%s：%s" % [upgrade.display_name, upgrade.description])
		SpecialUpgradeData.EffectKind.EVOLUTION:
			state.enable_food_evolution(choice_id)
			state.add_special(choice_id)
			hud.show_toast("%s：%s" % [upgrade.display_name, upgrade.description])
		SpecialUpgradeData.EffectKind.PIERCE:
			var pierce_amount: int = maxi(1, roundi(upgrade.effect_value))
			state.add_pierce_bonus(pierce_amount)
			state.add_special(choice_id)
			hud.show_toast("%s：所有食材穿透次数 +%d" % [upgrade.display_name, pierce_amount])
	_active_special_choices.clear()
	hud.hide_special_choices()
	if _boss_reward_pending:
		_boss_reward_pending = false
		if boss != null and is_instance_valid(boss):
			boss.queue_free()
		if _bosses_completed >= 2:
			_finish_run()
			return
	phase = Phase.FORWARD
	_normal_waves_suspended = false
	background.scrolling = true
	hud.set_phase("继续前进 · 构筑已变化")


func _on_boss_satisfied() -> void:
	state.boss_duration = state.elapsed_seconds - _boss_started_at
	state.boss_durations.append(state.boss_duration)
	_bosses_completed += 1
	state.customers_satisfied += 1
	cart.end_boss_movement()
	phase = Phase.CHOICE
	_boss_reward_pending = true
	hud.set_phase("Boss赏赐 · 特别三选一")
	hud.show_toast("Boss满意离场！选择本局特别强化", Color("#f0c45f"))
	_show_special_choices(&"boss", "Boss满意了！选择特别强化")


func _show_special_choices(source: StringName, title: String) -> void:
	_special_choice_source = source
	_active_special_choices = _roll_special_choices()
	if _active_special_choices.size() != 3:
		push_error(
			"SPECIAL_CHOICE_POOL_INVALID source=%s count=%d" % [
				String(source),
				_active_special_choices.size(),
			]
		)
		return
	state.record_special_offer(source, _active_special_choices)
	hud.show_special_choices(_active_special_choices, _special_choice_texts(_active_special_choices), title)
	if _smoke_test:
		_on_special_choice_selected(_active_special_choices[0])
	else:
		get_tree().paused = true


func _apply_food_card(food: FoodData) -> void:
	if food == null:
		return
	if state.has_food(food.id):
		var next_level: int = state.level_food(food.id)
		state.add_special(StringName("%s_level_%d" % [String(food.id), next_level]))
		hud.show_toast(
			"%s升至 Lv.%d：自身基础满足值 ×%.2f" % [
				food.display_name,
				next_level,
				state.food_level_satisfaction_multiplier,
			]
		)
		return
	weapon_controller.add_food(food)
	state.add_special(StringName("%s_acquired" % String(food.id)))
	hud.show_toast("获得%s：加入自动投喂构筑" % food.display_name)


func _finish_run() -> void:
	if phase == Phase.RESULTS:
		return
	phase = Phase.RESULTS
	_save_playtest_record(&"completed")
	hud.set_phase("构筑验证完成")
	hud.show_results("最终Boss满意离场，八分钟服务完成！", _build_results_text())
	if _smoke_test:
		if state.gate_choices != _expected_gate_count():
			push_error(
				"SMOKE_TEST_FAILED gates=%d expected=%d" % [
					state.gate_choices,
					_expected_gate_count(),
				]
			)
			Engine.time_scale = 1.0
			get_tree().quit(1)
			return
		if state.normal_customers_spawned != director.timeline.expected_normal_customer_count():
			push_error(
				"SMOKE_TEST_FAILED customers=%d expected=%d" % [
					state.normal_customers_spawned,
					director.timeline.expected_normal_customer_count(),
				]
			)
			Engine.time_scale = 1.0
			get_tree().quit(1)
			return
		if _smoke_minimum_gate_customer_gap + 0.001 < _smoke_minimum_required_gap:
			push_error(
				"SMOKE_TEST_FAILED forward_gap=%.2f required=%.2f kind=%s detail=%s"
				% [
					_smoke_minimum_gate_customer_gap,
					_smoke_minimum_required_gap,
					_smoke_minimum_gap_kind,
					_smoke_minimum_gap_detail,
				]
			)
			Engine.time_scale = 1.0
			get_tree().quit(1)
			return
		if state.upgrade_drops_spawned != state.normal_defeats:
			push_error(
				"SMOKE_TEST_FAILED drops=%d normal_defeats=%d" % [
					state.upgrade_drops_spawned,
					state.normal_defeats,
				]
			)
			Engine.time_scale = 1.0
			get_tree().quit(1)
			return
		if state.special_choice_records.size() != 8:
			push_error(
				"SMOKE_TEST_FAILED special_choices=%d expected=8"
				% state.special_choice_records.size()
			)
			Engine.time_scale = 1.0
			get_tree().quit(1)
			return
		print(
			"SMOKE_TEST_OK elapsed=%.2f gates=%d elites=%d specials=%d spawned=%d defeated=%d collisions=%d reward_gates=%d collected=%d min_gap=%.2f" % [
				state.elapsed_seconds,
				state.gate_choices,
				state.elite_durations.size(),
				state.special_choice_records.size(),
				state.normal_customers_spawned,
				state.customers_satisfied,
				state.collided_defeats,
				state.upgrade_drops_spawned,
				state.dropped_upgrades,
				_smoke_minimum_gate_customer_gap,
			]
		)
		Engine.time_scale = 1.0
		get_tree().quit(0)
	else:
		get_tree().paused = true


func _expected_gate_count() -> int:
	return director.timeline.normal_gate_count if director.timeline != null else 0


# 按实际承伤与受击后耐久的较高等级触发反馈，护盾吸收量也属于本次受击强度。
static func damage_shake_level(
	applied_damage: float,
	maximum_durability: float,
	current_durability_after_hit: float
) -> DamageShakeLevel:
	if maximum_durability <= 0.0:
		return DamageShakeLevel.SMALL
	var damage_ratio: float = maxf(0.0, applied_damage) / maximum_durability
	var remaining_ratio: float = clampf(
		current_durability_after_hit / maximum_durability,
		0.0,
		1.0
	)
	if damage_ratio > 0.5 or remaining_ratio < 0.2:
		return DamageShakeLevel.STRONG
	if damage_ratio >= 0.3 or remaining_ratio < 0.5:
		return DamageShakeLevel.MEDIUM
	return DamageShakeLevel.SMALL


func _on_cart_damaged(applied_damage: float) -> void:
	if state == null or background == null:
		return
	match damage_shake_level(
		applied_damage,
		state.maximum_durability,
		state.current_durability
	):
		DamageShakeLevel.STRONG:
			background.shake_camera(
				DAMAGE_SHAKE_STRONG_STRENGTH,
				DAMAGE_SHAKE_STRONG_DURATION
			)
		DamageShakeLevel.MEDIUM:
			background.shake_camera(
				DAMAGE_SHAKE_MEDIUM_STRENGTH,
				DAMAGE_SHAKE_MEDIUM_DURATION
			)
		_:
			background.shake_camera(
				DAMAGE_SHAKE_SMALL_STRENGTH,
				DAMAGE_SHAKE_SMALL_DURATION
			)


func _on_cart_destroyed() -> void:
	if phase == Phase.RESULTS or phase == Phase.FAILED:
		return
	phase = Phase.FAILED
	_save_playtest_record(&"failed")
	hud.set_phase("餐车失控 · 本局结束")
	hud.show_results("服务失败", _build_results_text())
	get_tree().paused = true


func _on_restart_requested() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# Debug菜单只发送动作ID，所有局内写操作继续集中在单局控制器及RunState中。
func _on_debug_action_requested(action_id: StringName) -> void:
	var feedback: String = ""
	var success: bool = true
	match action_id:
		&"speed_0_5":
			Engine.time_scale = 0.5
			feedback = "局内速度已设为 0.5×"
		&"speed_1":
			Engine.time_scale = 1.0
			feedback = "局内速度已恢复为 1×"
		&"speed_2":
			Engine.time_scale = 2.0
			feedback = "局内速度已设为 2×"
		&"speed_5":
			Engine.time_scale = 5.0
			feedback = "局内速度已设为 5×"
		&"advance_30":
			if phase == Phase.FORWARD or phase == Phase.BOSS:
				state.elapsed_seconds += 30.0
				if phase == Phase.FORWARD:
					state.forward_distance += world_scroll_speed * 30.0
				hud.set_time(state.elapsed_seconds)
				feedback = "局内进度已前进 30 秒等效距离"
			else:
				success = false
				feedback = "当前阶段不能推进时间"
		&"restart":
			Engine.time_scale = 1.0
			_on_restart_requested()
			return
		&"restore_cart":
			state.repair(state.maximum_durability - state.current_durability)
			feedback = "餐车耐久已修满"
		&"add_shield":
			state.add_temporary_shield(100.0)
			feedback = "临时护盾已增加 100"
		&"toggle_invincible":
			_debug_invincible = not _debug_invincible
			feedback = "餐车无敌已%s" % ("开启" if _debug_invincible else "关闭")
		&"unlock_all_foods":
			var unlocked_count: int = _debug_unlock_all_foods()
			feedback = "已解锁全部食材（新增 %d 种）" % unlocked_count
		&"max_all_foods":
			var level_count: int = _debug_max_all_foods()
			feedback = "全部食材已满级（提升 %d 级）" % level_count
		&"unlock_all_specials":
			var special_count: int = _debug_unlock_all_specials()
			feedback = "全部特殊能力已解锁（新增 %d 项）" % special_count
		&"random_normal_upgrade":
			if _normal_upgrade_pool.is_empty():
				success = false
				feedback = "普通强化池为空"
			else:
				var upgrade: UpgradeData = _roll_normal_upgrade_options(1)[0]
				upgrade.set_value_ratio(1.0)
				state.apply_upgrade(upgrade)
				cart.play_upgrade_feedback(upgrade.rarity_color)
				feedback = "已取得满品质强化：%s" % upgrade.display_name
		&"all_normal_upgrades":
			var upgrade_count: int = _debug_apply_all_normal_upgrades()
			feedback = "全部普通强化已各增加 1 层（%d 项）" % upgrade_count
		&"spawn_basic":
			success = _debug_queue_customer(basic_guest_data)
			feedback = "已排队生成普通食客" if success else "只有前进阶段可生成食客"
		&"spawn_fast":
			success = _debug_queue_customer(fast_guest_data)
			feedback = "已排队生成快速食客" if success else "只有前进阶段可生成食客"
		&"spawn_ranged":
			success = _debug_queue_customer(ranged_guest_data)
			feedback = "已排队生成远程食客" if success else "只有前进阶段可生成食客"
		&"spawn_elite":
			if phase == Phase.FORWARD:
				_queue_elite()
				feedback = "已排队生成精英食客"
			else:
				success = false
				feedback = "只有前进阶段可生成精英食客"
		&"spawn_gate":
			if phase == Phase.FORWARD:
				_queue_gate(-1, false, _current_baseline_appetite())
				feedback = "已排队生成普通强化门"
			else:
				success = false
				feedback = "只有前进阶段可生成强化门"
		&"start_boss":
			if phase == Phase.FORWARD:
				_normal_waves_suspended = true
				_begin_boss()
				feedback = "Boss 已开始，关闭菜单后进入战斗"
			else:
				success = false
				feedback = "只有前进阶段可直接开始 Boss"
		&"satisfy_targets":
			var target_count: int = _debug_satisfy_targets()
			success = target_count > 0
			feedback = ("已瞬间满足 %d 个当前目标" % target_count) if success else "当前没有可满足的目标"
		&"clear_forward":
			if phase == Phase.FORWARD:
				_clear_forward_objects()
				_normal_waves_suspended = false
				feedback = "食客、门、奖励与投射物已清空"
			else:
				success = false
				feedback = "只有前进阶段可清空路面对象"
		&"toggle_hud":
			hud.visible = not hud.visible
			feedback = "正式 HUD 已%s" % ("显示" if hud.visible else "隐藏")
		_:
			success = false
			feedback = "未知 Debug 操作：%s" % String(action_id)
	debug_menu.show_feedback(feedback, success)
	_refresh_debug_menu()


func _on_debug_menu_closed() -> void:
	if phase == Phase.CHOICE or phase == Phase.RESULTS or phase == Phase.FAILED:
		get_tree().paused = true


func _on_debug_menu_opened() -> void:
	cart.cancel_pointer_input()
	_refresh_debug_menu()


func _refresh_debug_menu() -> void:
	if debug_menu == null or state == null:
		return
	var food_texts: PackedStringArray = []
	for food_id: StringName in state.foods:
		var food: FoodData = _food_data_for_id(food_id)
		var display_name: String = food.display_name if food != null else String(food_id)
		food_texts.append("%s Lv.%d" % [display_name, state.food_level(food_id)])
	var boss_text: String = "无"
	if boss != null and is_instance_valid(boss) and boss.active:
		boss_text = "%.0f / %.0f" % [boss.remaining_appetite, boss.maximum_appetite]
	debug_menu.set_status_text((
		"阶段：%s  时间：%02d:%02d  速度：%.1f×\n"
		+ "耐久：%.0f / %.0f  护盾：%.0f  无敌：%s\n"
		+ "食材：%s\n"
		+ "食客：%d  门：%d  奖励门：%d  投射物：%d  Boss：%s"
	) % [
			_debug_phase_name(),
			floori(state.elapsed_seconds / 60.0),
			floori(state.elapsed_seconds) % 60,
			Engine.time_scale,
			state.current_durability,
			state.maximum_durability,
			state.temporary_shield,
			"开" if _debug_invincible else "关",
			"、".join(food_texts) if not food_texts.is_empty() else "尚未装车",
			customers.size(),
			gates.get_child_count(),
			drops.get_child_count(),
			projectiles.get_child_count(),
			boss_text,
		]
	)
	debug_menu.set_toggle_states(_debug_invincible, hud.visible)


func _debug_phase_name() -> String:
	match phase:
		Phase.INTRO:
			return "准备"
		Phase.FORWARD:
			return "前进"
		Phase.CHOICE:
			return "特别赏赐"
		Phase.BOSS:
			return "Boss"
		Phase.RESULTS:
			return "结算"
		Phase.FAILED:
			return "失败"
	return "未知"


func _debug_unlock_all_foods() -> int:
	var unlocked_count: int = 0
	for food: FoodData in _food_data_by_id.values():
		if state.has_food(food.id):
			continue
		weapon_controller.add_food(food)
		unlocked_count += 1
	return unlocked_count


func _debug_max_all_foods() -> int:
	_debug_unlock_all_foods()
	var level_count: int = 0
	for food_id: StringName in state.foods:
		while state.can_level_food(food_id):
			state.level_food(food_id)
			level_count += 1
	return level_count


func _debug_unlock_all_specials() -> int:
	_debug_unlock_all_foods()
	_ensure_special_upgrade_data()
	var unlocked_count: int = 0
	# 可重复能力只补到一层，使“一键解锁”保持幂等且不意外堆叠数值。
	for upgrade: SpecialUpgradeData in _special_upgrades_by_id.values():
		if upgrade.effect_kind == SpecialUpgradeData.EffectKind.FOOD_CARD:
			continue
		if state.specials.has(upgrade.id):
			continue
		match upgrade.effect_kind:
			SpecialUpgradeData.EffectKind.SERVING:
				state.servings += maxi(1, roundi(upgrade.effect_value))
			SpecialUpgradeData.EffectKind.TARGET_AIM:
				state.enable_target_aim(upgrade.target_id)
			SpecialUpgradeData.EffectKind.EVOLUTION:
				state.enable_food_evolution(upgrade.id)
			SpecialUpgradeData.EffectKind.PIERCE:
				state.add_pierce_bonus(maxi(1, roundi(upgrade.effect_value)))
		state.add_special(upgrade.id)
		unlocked_count += 1
	return unlocked_count


func _debug_apply_all_normal_upgrades() -> int:
	var applied_count: int = 0
	for template: UpgradeData in _normal_upgrade_pool:
		var upgrade: UpgradeData = template.duplicate() as UpgradeData
		upgrade.set_value_ratio(1.0)
		state.apply_upgrade(upgrade)
		applied_count += 1
	if applied_count > 0:
		cart.play_upgrade_feedback(Color("#f0c45f"))
	return applied_count


func _debug_queue_customer(customer_data: CustomerData) -> bool:
	if phase != Phase.FORWARD or customer_data == null:
		return false
	_queue_customer(customer_data, _current_baseline_appetite())
	return true


func _debug_satisfy_targets() -> int:
	if boss != null and is_instance_valid(boss) and boss.active:
		boss.receive_satisfaction(boss.remaining_appetite)
		return 1
	var satisfied_count: int = 0
	var active_customers: Array[Customer3D] = customers.duplicate()
	for customer: Customer3D in active_customers:
		if not is_instance_valid(customer) or not customer.active:
			continue
		customer.receive_satisfaction(customer.remaining_appetite)
		satisfied_count += 1
	return satisfied_count


func _clear_forward_objects() -> void:
	_forward_spawn_requests.clear()
	_reward_spawn_requests.clear()
	for customer: Customer3D in customers:
		if is_instance_valid(customer):
			customer.queue_free()
	customers.clear()
	for child: Node in gates.get_children():
		child.queue_free()
	for child: Node in projectiles.get_children():
		child.queue_free()
	for child: Node in drops.get_children():
		child.queue_free()


func _target_is_better(
	forward: float,
	horizontal: float,
	spawn_index: int,
	best_forward: float,
	best_horizontal: float,
	best_spawn_index: int
) -> bool:
	var distance_squared: float = forward * forward + horizontal * horizontal
	var best_distance_squared: float = (
		best_forward * best_forward + best_horizontal * best_horizontal
	)
	if distance_squared < best_distance_squared - 0.0001:
		return true
	if absf(distance_squared - best_distance_squared) > 0.0001:
		return false
	if horizontal < best_horizontal - 0.0001:
		return true
	if absf(horizontal - best_horizontal) > 0.0001:
		return false
	return spawn_index < best_spawn_index


# 烟雾测试记录真实运行中的最小门客距离，防止预测公式接入错误。
func _track_smoke_gate_customer_gap() -> void:
	for customer: Customer3D in customers:
		if (
			not is_instance_valid(customer)
			or not customer.active
			or customer.position.z >= cart_destination_z()
		):
			continue
		for child: Node in gates.get_children():
			if not child is UpgradeGate3D or child.is_queued_for_deletion():
				continue
			var gate: UpgradeGate3D = child as UpgradeGate3D
			if gate.position.z >= cart_destination_z():
				continue
			var gate_gap: float = absf(customer.position.z - gate.position.z)
			_track_smoke_gap(gate_gap, "customer_gate")
		for child: Node in drops.get_children():
			if not child is UpgradeDrop3D or child.is_queued_for_deletion():
				continue
			var reward_gate: UpgradeDrop3D = child as UpgradeDrop3D
			if reward_gate.position.z >= cart_destination_z():
				continue
			var reward_width: float = reward_gate._panel_width()
			var customer_rect: Rect2 = customer.collision_rect_xz()
			var reward_rect_x: Rect2 = Rect2(
				reward_gate.position.x - reward_width * 0.5,
				0.0,
				reward_width,
				1.0
			)
			var customer_rect_x: Rect2 = Rect2(
				customer_rect.position.x,
				0.0,
				customer_rect.size.x,
				1.0
			)
			if not customer_rect_x.intersects(reward_rect_x):
				continue
			var reward_gap: float = absf(customer.position.z - reward_gate.position.z)
			_track_smoke_gap(
				reward_gap,
				"customer_reward",
				"cz=%.2f rz=%.2f cs=%.2f rs=%.2f p=%.3f" % [
					customer.position.z,
					reward_gate.position.z,
					customer.travel_speed(),
					reward_gate.travel_speed(),
					forward_progress(),
				],
				REWARD_GATE_MIN_CENTER_DISTANCE
			)
	var reward_gates: Array[UpgradeDrop3D] = []
	for child: Node in drops.get_children():
		if child is UpgradeDrop3D and not child.is_queued_for_deletion():
			var reward_gate: UpgradeDrop3D = child as UpgradeDrop3D
			if reward_gate.position.z >= cart_destination_z():
				continue
			reward_gates.append(reward_gate)
			for gate_child: Node in gates.get_children():
				if not gate_child is UpgradeGate3D or gate_child.is_queued_for_deletion():
					continue
				if (gate_child as UpgradeGate3D).position.z >= cart_destination_z():
					continue
				var reward_gate_gap: float = absf(
					reward_gate.position.z - (gate_child as UpgradeGate3D).position.z
				)
				_track_smoke_gap(
					reward_gate_gap,
					"reward_gate",
					"",
					REWARD_GATE_MIN_CENTER_DISTANCE
				)
	for first_index: int in range(reward_gates.size()):
		for second_index: int in range(first_index + 1, reward_gates.size()):
			var first_gate: UpgradeDrop3D = reward_gates[first_index]
			var second_gate: UpgradeDrop3D = reward_gates[second_index]
			var first_width: float = first_gate._panel_width()
			var second_width: float = second_gate._panel_width()
			if (
				first_gate.position.x + first_width * 0.5 <= second_gate.position.x - second_width * 0.5
				or second_gate.position.x + second_width * 0.5 <= first_gate.position.x - first_width * 0.5
			):
				continue
			var reward_pair_gap: float = absf(first_gate.position.z - second_gate.position.z)
			_track_smoke_gap(
				reward_pair_gap,
				"reward_pair",
				"",
				REWARD_GATE_MIN_CENTER_DISTANCE
			)


# 不同对象组合使用各自允许间距；记录最接近违规的组合，避免放宽奖励门后削弱普通门检查。
func _track_smoke_gap(
	gap: float,
	kind: String,
	detail: String = "",
	required_gap: float = SMOKE_MINIMUM_GEOMETRY_GAP
) -> void:
	var current_margin: float = gap - required_gap
	var recorded_margin: float = _smoke_minimum_gate_customer_gap - _smoke_minimum_required_gap
	if current_margin >= recorded_margin:
		return
	_smoke_minimum_gate_customer_gap = gap
	_smoke_minimum_required_gap = required_gap
	_smoke_minimum_gap_kind = kind
	_smoke_minimum_gap_detail = detail


func _build_results_text() -> String:
	var food_lines: PackedStringArray = []
	for food_id: StringName in state.foods:
		food_lines.append(
			"%s Lv.%d 贡献 %.0f" % [
				String(food_id),
				state.food_level(food_id),
				state.satisfaction_by_food.get(food_id, 0.0),
			]
		)
	var elite_lines: PackedStringArray = []
	for duration: float in state.elite_durations:
		elite_lines.append("%.1fs" % duration)
	return (
		"随机种子：%d\n"
		+ "用时：%02d:%02d\n"
		+ "强化门：%d\n"
		+ "取得奖励门：%d\n"
		+ "击败敌人：%d\n"
		+ "撞击击败：%d\n"
		+ "受击次数：%d\n"
		+ "耐久损失：%.0f\n"
		+ "精英耗时：%s\n"
		+ "Boss耗时：%.1fs\n"
		+ "构筑：%s\n"
		+ "剩余耐久：%.0f / %.0f"
	) % [
		state.run_seed,
		floori(state.elapsed_seconds / 60.0),
		floori(state.elapsed_seconds) % 60,
		state.gate_choices,
		state.dropped_upgrades,
		state.customers_satisfied,
		state.collided_defeats,
		state.hits_taken,
		state.durability_lost,
		" / ".join(elite_lines),
		state.boss_duration,
		"；".join(food_lines),
		state.current_durability,
		state.maximum_durability,
	]


func _save_playtest_record(outcome: StringName) -> void:
	if _playtest_record_saved:
		return
	_playtest_record_saved = true
	var food_levels_record: Dictionary = {}
	var food_satisfaction_record: Dictionary = {}
	for food_id: StringName in state.foods:
		food_levels_record[String(food_id)] = state.food_level(food_id)
		food_satisfaction_record[String(food_id)] = state.satisfaction_by_food.get(food_id, 0.0)
	var record: Dictionary = {
		"schema": "xiaochuxi.playtest_run.v1",
		"seed": state.run_seed,
		"outcome": String(outcome),
		"elapsed_seconds": state.elapsed_seconds,
		"food_levels": food_levels_record,
		"food_evolutions": _string_name_array_to_strings(state.food_evolutions),
		"special_choices": state.special_choice_records_as_array(),
		"normal_upgrades": _build_normal_upgrade_playtest_record(),
		"final_food_multipliers": _build_final_food_multiplier_record(),
		"common_gate_choices": state.gate_choices,
		"reward_gate_choices": state.dropped_upgrades,
		"satisfaction_by_food": food_satisfaction_record,
		"elite_durations": state.elite_durations,
		"boss_duration": state.boss_duration,
		"boss_durations": state.boss_durations,
		"durability_lost": state.durability_lost,
		"final_durability": state.current_durability,
		"maximum_durability": state.maximum_durability,
		"temporary_shield": state.temporary_shield,
		"hits_taken": state.hits_taken,
		"normal_defeats": state.normal_defeats,
		"normal_customers_spawned": state.normal_customers_spawned,
		"collided_defeats": state.collided_defeats,
		"post_boss_performance": _build_post_boss_performance_record(),
	}
	var file: FileAccess
	if FileAccess.file_exists(PLAYTEST_RECORD_PATH):
		file = FileAccess.open(PLAYTEST_RECORD_PATH, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(PLAYTEST_RECORD_PATH, FileAccess.WRITE)
	if file == null:
		push_error("PLAYTEST_RECORD_SAVE_FAILED error=%d" % FileAccess.get_open_error())
		return
	file.store_line(JSON.stringify(record))
	file.close()
	print("PLAYTEST_RECORD_SAVED path=%s seed=%d" % [PLAYTEST_RECORD_PATH, state.run_seed])


# 每项同时保留提供、选择、实际结算值与点数贡献，供12局横向比较。
func _build_normal_upgrade_playtest_record() -> Array[Dictionary]:
	var ids: Array[String] = []
	for upgrade_id: StringName in state.normal_upgrade_offer_counts:
		ids.append(String(upgrade_id))
	for upgrade_id: StringName in state.normal_upgrade_choice_counts:
		if not ids.has(String(upgrade_id)):
			ids.append(String(upgrade_id))
	ids.sort()
	var records: Array[Dictionary] = []
	for id_text: String in ids:
		var upgrade_id: StringName = StringName(id_text)
		records.append({
			"id": id_text,
			"offered": state.normal_upgrade_offer_counts.get(upgrade_id, 0),
			"selected": state.normal_upgrade_choice_counts.get(upgrade_id, 0),
			"selected_value": state.normal_upgrade_value_totals.get(upgrade_id, 0.0),
			"contribution": state.normal_upgrade_contribution_totals.get(upgrade_id, 0.0),
		})
	return records


# 物理属性记录食材转译后的终局倍率，避免复盘时把原始累计值误当成实际收益。
func _build_final_food_multiplier_record() -> Dictionary:
	var records: Dictionary = {}
	for food_id: StringName in state.foods:
		var food: FoodData = _food_data_for_id(food_id)
		if food == null:
			continue
		var wine_multiplier: float = (
			state.effective_orbit_angular_speed(food) / maxf(0.001, food.orbit_angular_speed)
			if food.attack_kind == FoodData.AttackKind.ORBITING_MUSHROOM
			else state.effective_projectile_speed(food) / maxf(0.001, food.projectile_speed)
		)
		records[String(food_id)] = {
			"satisfaction": state.effective_satisfaction(food) / maxf(0.001, food.base_satisfaction),
			"attack_speed": 1.0 + state.attack_speed_bonus * food.attack_speed_upgrade_scale,
			"wine": wine_multiplier,
			"range": state.effective_projectile_radius(food) / maxf(0.001, food.projectile_radius),
			"duration": state.effective_duration(food) / maxf(0.001, food.base_lifetime),
		}
	return records


func _build_post_boss_performance_record() -> Dictionary:
	var satisfaction_delta: Dictionary = {}
	for food_id: StringName in state.foods:
		satisfaction_delta[String(food_id)] = (
			state.satisfaction_by_food.get(food_id, 0.0)
			- _post_boss_satisfaction_start.get(food_id, 0.0)
		)
	var boss_reward: String = ""
	if not state.special_choice_records.is_empty():
		boss_reward = String(state.special_choice_records.back().selected)
	return {
		"reward": boss_reward,
		"duration_seconds": maxf(0.0, state.elapsed_seconds - _post_boss_started_at),
		"common_gates_collected": maxi(0, state.gate_choices - _post_boss_gate_choices_start),
		"durability_lost": maxf(0.0, state.durability_lost - _post_boss_durability_lost_start),
		"satisfaction_by_food": satisfaction_delta,
	}


func _string_name_array_to_strings(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in values:
		result.append(String(value))
	return result


func _build_prototype_upgrades() -> void:
	if not _normal_upgrade_pool.is_empty():
		return
	_normal_upgrade_pool = [
		_make_upgrade_range(&"sugar", "糖", UpgradeData.Kind.SUGAR, 0.05, 0.30, "%"),
		_make_upgrade_range(&"quick_prep", "快速备餐", UpgradeData.Kind.QUICK_PREP, 0.05, 0.30, "%"),
		_make_upgrade_range(&"light_cart", "轻便餐车", UpgradeData.Kind.LIGHT_CART, 50.0, 300.0, "速度"),
		_make_upgrade_range(&"sturdy_cart", "餐车改造", UpgradeData.Kind.STURDY_CART, 0.02, 0.11, "%"),
		_make_upgrade_range(&"repair", "紧急维修", UpgradeData.Kind.REPAIR, 0.12, 0.55, "%"),
		_make_upgrade_range(&"wine", "酒", UpgradeData.Kind.WINE, 0.10, 0.50, "%"),
		_make_upgrade_range(&"scallion", "葱", UpgradeData.Kind.SCALLION, 0.10, 0.60, "%"),
		_make_upgrade_range(&"starch", "淀粉", UpgradeData.Kind.STARCH, 0.15, 0.75, "%"),
	]


# 门模板只保存区间，每个实际门选项都会复制后独立抽取百分位。
func _make_upgrade_range(
	id: StringName,
	display_name: String,
	kind: UpgradeData.Kind,
	minimum_value: float,
	maximum_value: float,
	suffix: String
) -> UpgradeData:
	var upgrade: UpgradeData = UpgradeData.new()
	upgrade.id = id
	upgrade.display_name = display_name
	upgrade.kind = kind
	upgrade.value_suffix = suffix
	upgrade.configure_value_range(minimum_value, maximum_value)
	return upgrade


func _roll_gate_upgrade(template: UpgradeData) -> UpgradeData:
	var rolled: UpgradeData = template.duplicate() as UpgradeData
	rolled.set_value_ratio(_upgrade_rng.randf())
	return rolled


# 普通门取两项、食客奖励取一项；同次抽选无放回且各自独立生成数值。
func _roll_normal_upgrade_options(option_count: int) -> Array[UpgradeData]:
	var available: Array[UpgradeData] = _normal_upgrade_pool.duplicate()
	var options: Array[UpgradeData] = []
	var target_count: int = mini(maxi(option_count, 0), available.size())
	while options.size() < target_count:
		var index: int = _upgrade_rng.randi_range(0, available.size() - 1)
		options.append(_roll_gate_upgrade(available[index]))
		available.remove_at(index)
	return options


# 开局门从已解锁池无放回抽取；只有一种食材时两侧显示同一候选。
func _roll_start_food_options() -> Array[UpgradeData]:
	var available: Array[FoodData] = _available_start_foods()
	var options: Array[UpgradeData] = []
	while not available.is_empty() and options.size() < 2:
		var index: int = _upgrade_rng.randi_range(0, available.size() - 1)
		options.append(_make_start_food_option(available[index]))
		available.remove_at(index)
	if options.size() == 1:
		options.append(_make_start_food_option(_food_data_for_id(options[0].id)))
	return options


# 当前原型未配置解锁子集时，三种已装配食材共同构成默认解锁池。
func _available_start_foods() -> Array[FoodData]:
	var configured_foods: Array[FoodData] = unlocked_foods.duplicate()
	if configured_foods.is_empty() and not _food_data_by_id.is_empty():
		for food: FoodData in _food_data_by_id.values():
			configured_foods.append(food)
	if configured_foods.is_empty():
		configured_foods = [potato_data, baguette_data, mushroom_data]
	var available: Array[FoodData] = []
	var seen_ids: Dictionary[StringName, bool] = {}
	for food: FoodData in configured_foods:
		if food == null or seen_ids.has(food.id):
			continue
		seen_ids[food.id] = true
		available.append(food)
	return available


func _make_start_food_option(food: FoodData) -> UpgradeData:
	var option: UpgradeData = UpgradeData.new()
	option.id = food.id
	option.display_name = food.display_name
	return option


func _food_data_for_id(food_id: StringName) -> FoodData:
	if _food_data_by_id.has(food_id):
		return _food_data_by_id[food_id]
	for food: FoodData in _available_start_foods():
		if food.id == food_id:
			return food
	return null


# 普通食客从普通强化共用池锁定一项及其百分位，胃口和奖励门共享结果。
func _roll_customer_reward() -> UpgradeData:
	var options: Array[UpgradeData] = _roll_normal_upgrade_options(1)
	if options.is_empty():
		return null
	var reward: UpgradeData = options[0]
	reward.set_source_scale(_reward_effect_scale, "小份奖励")
	if state != null:
		state.record_normal_upgrade_offer([reward])
	return reward


# 从当前有效池完全随机抽出三个不同选项；不做新食材或进化保底。
func _roll_special_choices() -> Array[StringName]:
	_ensure_special_upgrade_data()
	var available: Array[StringName] = []
	for choice_id: StringName in _special_choice_pool:
		if _special_choice_is_valid(choice_id):
			available.append(choice_id)
	var choices: Array[StringName] = []
	var choice_count: int = mini(3, available.size())
	while choices.size() < choice_count:
		var index: int = _upgrade_rng.randi_range(0, available.size() - 1)
		choices.append(available[index])
		available.remove_at(index)
	return choices


func _special_choice_is_valid(choice_id: StringName) -> bool:
	_ensure_special_upgrade_data()
	var upgrade: SpecialUpgradeData = _special_upgrades_by_id.get(choice_id)
	if upgrade == null:
		return false
	match upgrade.effect_kind:
		SpecialUpgradeData.EffectKind.FOOD_CARD:
			return state.food_level(upgrade.target_id) < state.food_max_level
		SpecialUpgradeData.EffectKind.TARGET_AIM:
			return (
				state.has_food(upgrade.target_id)
				and not state.is_food_target_aimed(upgrade.target_id)
			)
		SpecialUpgradeData.EffectKind.EVOLUTION:
			return (
				state.has_food(upgrade.target_id)
				and not state.has_food_evolution(upgrade.id)
			)
		SpecialUpgradeData.EffectKind.SERVING, SpecialUpgradeData.EffectKind.PIERCE:
			return upgrade.repeatable or not state.specials.has(upgrade.id)
	return false


func _ensure_special_upgrade_data() -> void:
	if _special_upgrades_by_id.is_empty():
		_build_fallback_special_upgrades()


func _set_special_upgrades(upgrades: Array[SpecialUpgradeData]) -> void:
	_special_upgrades_by_id.clear()
	_special_choice_pool.clear()
	for upgrade: SpecialUpgradeData in upgrades:
		_special_upgrades_by_id[upgrade.id] = upgrade
		_special_choice_pool.append(upgrade.id)


# 回退池完整保留当前实现，确保三个 Excel 任一损坏时仍可开始新局。
func _build_fallback_special_upgrades() -> void:
	_set_special_upgrades([
		_make_special_upgrade(&"potato", "土豆", SpecialUpgradeData.EffectKind.FOOD_CARD, &"potato", 1.0, true, "获得新食材并加入自动投喂", "提高自身基础满足值"),
		_make_special_upgrade(&"baguette", "法棍", SpecialUpgradeData.EffectKind.FOOD_CARD, &"baguette", 1.0, true, "获得新食材并加入自动投喂", "提高自身基础满足值"),
		_make_special_upgrade(&"mushroom", "蘑菇", SpecialUpgradeData.EffectKind.FOOD_CARD, &"mushroom", 1.0, true, "获得新食材并加入自动投喂", "提高自身基础满足值"),
		_make_special_upgrade(&"serving", "全局加量", SpecialUpgradeData.EffectKind.SERVING, &"", 1.0, true, "当前与未来食材增加攻击份数", ""),
		_make_special_upgrade(&"potato_aim", "瞄准投喂", SpecialUpgradeData.EffectKind.TARGET_AIM, &"potato", 1.0, false, "土豆发射时朝向当前目标", ""),
		_make_special_upgrade(&"baguette_giant", "巨型法棍", SpecialUpgradeData.EffectKind.EVOLUTION, &"baguette", 1.0, false, "以3秒基础间隔额外发射一根横跨四格、滚动直行的巨型法棍", ""),
		_make_special_upgrade(&"mushroom_breath", "呼吸菌圈", SpecialUpgradeData.EffectKind.EVOLUTION, &"mushroom", 1.0, false, "蘑菇环绕半径按武器表周期与倍率呼吸", ""),
		_make_special_upgrade(&"soy_sauce", "酱油", SpecialUpgradeData.EffectKind.PIERCE, &"", 1.0, true, "提高全部食材可命中目标数", ""),
	])


func _make_special_upgrade(
	id: StringName,
	display_name: String,
	effect_kind: SpecialUpgradeData.EffectKind,
	target_id: StringName,
	effect_value: float,
	repeatable: bool,
	description: String,
	upgrade_description: String
) -> SpecialUpgradeData:
	var upgrade: SpecialUpgradeData = SpecialUpgradeData.new()
	upgrade.id = id
	upgrade.display_name = display_name
	upgrade.effect_kind = effect_kind
	upgrade.target_id = target_id
	upgrade.effect_value = effect_value
	upgrade.repeatable = repeatable
	upgrade.description = description
	upgrade.upgrade_description = upgrade_description
	return upgrade


func _special_choice_texts(choice_ids: Array[StringName]) -> Dictionary[StringName, String]:
	var texts: Dictionary[StringName, String] = {}
	for choice_id: StringName in choice_ids:
		var upgrade: SpecialUpgradeData = _special_upgrades_by_id.get(choice_id)
		if upgrade == null:
			texts[choice_id] = String(choice_id)
			continue
		if upgrade.effect_kind == SpecialUpgradeData.EffectKind.FOOD_CARD:
			var current_level: int = state.food_level(upgrade.target_id)
			if current_level <= 0:
				texts[choice_id] = "%s\n%s" % [upgrade.display_name, upgrade.description]
			else:
				texts[choice_id] = "%s Lv.%d → Lv.%d\n%s ×%.2f" % [
					upgrade.display_name,
					current_level,
					current_level + 1,
					upgrade.upgrade_description,
					state.food_level_satisfaction_multiplier,
				]
			continue
		if upgrade.effect_kind == SpecialUpgradeData.EffectKind.SERVING:
			texts[choice_id] = "%s\n当前与未来食材各多发 %d 份" % [
				upgrade.display_name,
				maxi(1, roundi(upgrade.effect_value)),
			]
			continue
		if upgrade.effect_kind == SpecialUpgradeData.EffectKind.PIERCE:
			texts[choice_id] = "%s\n所有当前与未来食材穿透次数 +%d" % [
				upgrade.display_name,
				maxi(1, roundi(upgrade.effect_value)),
			]
			continue
		texts[choice_id] = "%s\n%s" % [upgrade.display_name, upgrade.description]
	return texts


func _current_baseline_appetite() -> float:
	return _baseline_appetite_at(state.elapsed_seconds if state != null else 0.0)


func _baseline_appetite_at(elapsed_seconds: float) -> float:
	if director.timeline == null:
		return 20.0
	return director.timeline.baseline_appetite_at_elapsed_seconds(elapsed_seconds)


func _scheduled_baseline_appetite(event_id: StringName) -> float:
	return _current_baseline_appetite()


func _requested_run_seed() -> int:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--run-seed="):
			continue
		var value: String = argument.trim_prefix("--run-seed=")
		if value.is_valid_int():
			return maxi(0, value.to_int())
	return -1
