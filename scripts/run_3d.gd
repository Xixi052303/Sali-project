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
const COMBAT_RULES_WORKBOOK_PATH: String = "res://balance_tables/战斗规则.xlsx"
const CUSTOMER_WORKBOOK_PATH: String = "res://balance_tables/食客.xlsx"
const WEAPON_WORKBOOK_PATH: String = "res://balance_tables/武器.xlsx"
const NORMAL_UPGRADE_WORKBOOK_PATH: String = "res://balance_tables/普通强化.xlsx"
const SPECIAL_UPGRADE_WORKBOOK_PATH: String = "res://balance_tables/特殊强化.xlsx"
const DEFAULT_CUSTOMER_SCENE: PackedScene = preload(
	"res://scenes/characters/customers/customer_base_3d.tscn"
)
const CART_SCENE: PackedScene = preload("res://scenes/cart_3d.tscn")
const BOSS_SCENE: PackedScene = preload(
	"res://scenes/characters/bosses/prototype_boss_3d.tscn"
)
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/foods/projectiles/food_projectile_3d.tscn")
const EGG_PUDDLE_SCENE: PackedScene = preload("res://scenes/foods/derived/egg_puddle_3d.tscn")
const GATE_SCENE: PackedScene = preload("res://scenes/upgrade_gate_3d.tscn")
const REWARD_GATE_SCENE: PackedScene = preload("res://scenes/upgrade_drop_3d.tscn")
const LEGACY_CUSTOMER_SPAWN_Z: float = -6.4
const LEGACY_GATE_SPAWN_Z: float = 0.0
const FORWARD_GATE_SPEED: float = 2.5
const BASE_WORLD_SCROLL_SPEED: float = 2.05
const TARGET_FORWARD_EPSILON: float = 0.0001
const TARGET_ANGLE_EPSILON_DEGREES: float = 0.0001
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
# 客户端回大厅前留出一小段时间，让当前 MultiplayerSpawner 消化房主的 despawn 包。
const NETWORK_SCENE_RELOAD_DELAY_SECONDS: float = 0.5
const PLAYTEST_RECORD_PATH: String = "user://playtest_runs.jsonl"
const SPAWN_SEED_SALT: int = 0x5EED5EED

@export_group("Prototype data")
@export var potato_data: FoodData
@export var baguette_data: FoodData
@export var mushroom_data: FoodData
@export var egg_data: FoodData
@export var carrot_data: FoodData
# 武器表“衍生攻击”页的蛋液参数；工作簿失败时由代码回退值补齐。
@export var egg_puddle_data: FoodData
# 空数组表示当前原型默认解锁全部食材；后续局外解锁可在场景中显式配置子集。
@export var unlocked_foods: Array[FoodData] = []
@export var basic_guest_data: CustomerData
@export var fast_guest_data: CustomerData
@export var ranged_guest_data: CustomerData
@export var elite_guest_data: CustomerData
@export var boss_data: BossPatternData

@onready var background: WorldBackground3D = %Background
@onready var entities: Node3D = %Entities
@onready var players_root: Node3D = %Players
@onready var projectiles: Node3D = %Projectiles
@onready var drops: Node3D = %Drops
@onready var gates: Node3D = %Gates
@onready var customer_spawner: MultiplayerSpawner = %CustomerSpawner
@onready var gate_spawner: MultiplayerSpawner = %GateSpawner
@onready var drop_spawner: MultiplayerSpawner = %DropSpawner
@onready var boss_spawner: MultiplayerSpawner = %BossSpawner
@onready var cart: Cart3D = %Cart3D
@onready var weapon_controller: WeaponController3D = %WeaponController3D
@onready var director: EncounterDirector = %EncounterDirector
@onready var hud: GameHud = %Hud
@onready var debug_menu: DebugMenu = %DebugMenu
@onready var main_menu: MainMenu = %MainMenu

var world_scroll_speed: float = BASE_WORLD_SCROLL_SPEED
var state: RunState
var playfield: Playfield
var phase: Phase = Phase.INTRO
var _manual_pause_active: bool = false
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
# 最终Boss结算时记录持久化结果，供结算文案和试玩记录共同使用。
var _final_boss_unlock_status: StringName = &"not_checked"
var _post_boss_satisfaction_start: Dictionary[StringName, float] = {}
var _post_boss_durability_lost_start: float = 0.0
var _post_boss_gate_choices_start: int = 0
var _upgrade_rng: RandomNumberGenerator = RandomNumberGenerator.new()
# 开局食材与特殊候选按玩家槽位分流，避免一名玩家的选择改变队友候选序列。
var _player_choice_rngs: Dictionary[int, RandomNumberGenerator] = {}
# 波次间隔与食客路线共用独立随机流，避免改变强化奖励序列。
var _spawn_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _target_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _run_seed: int = 0
var _normal_wave_progresses: PackedFloat32Array = PackedFloat32Array()
var _active_special_choices: Array[StringName] = []
var _special_choice_source: StringName = &""
var _active_special_choices_by_slot: Dictionary[int, Array] = {}
var _selected_special_choices_by_slot: Dictionary[int, StringName] = {}
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
# 普通食客奖励在没有精英节点前使用的初始缩放；实际生成时会锁定当前值。
var _reward_effect_scale_initial: float = 0.7
# 每只精英出现后的目标缩放，前三项由普通强化配置表驱动，之后保持最后一项。
var _reward_effect_scale_after_elite: PackedFloat32Array = PackedFloat32Array([
	0.6, 0.4, 0.25,
])
# 精英节点后当前缩放过渡到目标值所用的有效游戏时间。
var _reward_effect_scale_transition_seconds: float = 10.0
var _reward_effect_scale: float = 0.7
var _reward_effect_scale_transition_start: float = 0.7
var _reward_effect_scale_transition_target: float = 0.7
var _reward_effect_scale_transition_elapsed: float = 0.0
var _elites_spawned: int = 0
var _wine_curve_c: float = RunState.WINE_CURVE_C
var _range_curve_c: float = RunState.RANGE_CURVE_C
var _duration_curve_c: float = RunState.DURATION_CURVE_C
var _cart_speed_curve_c: float = RunState.CART_SPEED_CURVE_C
var _range_multiplier_cap: float = RunState.RANGE_MULTIPLIER_CAP
var _cart_invincibility_duration_seconds: float = (
	Cart3D.DEFAULT_INVINCIBILITY_DURATION_SECONDS
)
var _respawn_base_seconds: float = RunState.DEFAULT_RESPAWN_BASE_SECONDS
var _respawn_increment_seconds: float = RunState.DEFAULT_RESPAWN_INCREMENT_SECONDS
var _respawn_max_seconds: float = RunState.DEFAULT_RESPAWN_MAX_SECONDS
var _ghost_damage_multiplier: float = RunState.DEFAULT_GHOST_DAMAGE_MULTIPLIER
var _respawn_durability_ratio: float = RunState.DEFAULT_RESPAWN_DURABILITY_RATIO
var _respawn_invincibility_seconds: float = RunState.DEFAULT_RESPAWN_INVINCIBILITY_SECONDS
# 多人模式按槽位持有独立强化与餐车，敌人、门和时间轴仍由本控制器共享。
var _player_contexts: Dictionary[int, PlayerRunContext] = {}
var _network_active: bool = false
# 通过根节点获取 Autoload，保证编辑器主场景与 --script 专项测试都能解析同一会话。
var _network_session: Variant
var _network_player_count: int = 1
var _network_snapshot_accumulator: float = 0.0
var _network_stats_accumulator: float = 0.0
var _network_customer_snapshot_cycle: int = 0
var _network_customer_fragment_cycle: int = -1
var _network_customer_fragment_seen: Dictionary[int, bool] = {}
var _team_death_count: int = 0
var _network_run_finished: bool = false
# 回大厅与断线可能连续触发；该门闩保证旧场景只重载一次。
var _network_scene_reload_pending: bool = false
# 主机只为新出现的世界对象发送一次可靠配置，避免每帧重复传输资源字段。
var _network_announced_customer_ids: Dictionary[int, bool] = {}
var _network_announced_gate_ids: Dictionary[int, bool] = {}
var _network_announced_drop_ids: Dictionary[int, bool] = {}
var _network_announced_boss: bool = false
var _debug_invincible: bool = false
# 食材卡取得后转为等级卡；进化按持有状态进入池，全局效果可以重复取得。
var _special_choice_pool: Array[StringName] = [
	&"potato",
	&"baguette",
	&"mushroom",
	&"egg",
	&"carrot",
	&"serving",
	&"potato_aim",
	&"baguette_giant",
	&"mushroom_breath",
	&"soy_sauce",
]


func _ready() -> void:
	_network_session = get_node_or_null("/root/NetworkSession")
	_configure_network_spawners()
	_load_timeline_balance()
	_load_combat_rules_balance()
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
	_spawn_rng.seed = _run_seed ^ SPAWN_SEED_SALT
	_target_rng.seed = _run_seed ^ 0x7A26BEEF
	_normal_wave_progresses = _build_normal_wave_progresses(director.timeline)
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
	cart.configure(state, playfield, _cart_invincibility_duration_seconds)
	cart.set_player_slot(1)
	background.set_cart(cart)
	# 主菜单展示期间冻结道路滚动，保持启动画面可读且不改变开局距离。
	background.scrolling = false
	weapon_controller.configure(self, cart, state)
	_register_player_context(1, 1, state, cart, weapon_controller)
	_build_prototype_upgrades()
	director.event_triggered.connect(_on_timeline_event)
	cart.damaged.connect(_on_cart_damaged)
	cart.destroyed.connect(_on_cart_destroyed)
	state.inventory_changed.connect(_refresh_hud_inventory)
	weapon_controller.food_added.connect(_on_weapon_food_added)
	weapon_controller.food_removed.connect(_on_weapon_food_removed)
	weapon_controller.cooking_progress_changed.connect(
		_on_player_cooking_progress_changed.bind(1)
	)
	hud.special_choice_selected.connect(_on_special_choice_selected)
	hud.restart_requested.connect(_on_restart_requested)
	hud.pause_requested.connect(_on_pause_requested)
	hud.resume_requested.connect(_on_resume_requested)
	main_menu.start_requested.connect(_on_main_menu_start_requested)
	_network_session.match_started.connect(_on_network_match_started)
	_network_session.remote_input_received.connect(_on_network_input_received)
	_network_session.pause_changed.connect(_on_network_pause_changed)
	_network_session.network_event_received.connect(_on_network_event_received)
	_network_session.choice_received.connect(_on_network_choice_received)
	_network_session.match_returned_to_lobby.connect(_on_network_match_returned_to_lobby)
	_network_session.connection_state_changed.connect(_on_network_connection_state_changed)
	_network_session.roster_changed.connect(_on_network_roster_changed)
	debug_menu.action_requested.connect(_on_debug_action_requested)
	debug_menu.menu_opened.connect(_on_debug_menu_opened)
	debug_menu.menu_closed.connect(_on_debug_menu_closed)
	hud.set_durability(
		state.current_durability,
		state.maximum_durability,
		state.temporary_shield
	)
	hud.set_phase("厨房待命 · 点击开始出餐")
	hud.set_pause_available(false)
	hud.visible = false
	phase = Phase.INTRO
	main_menu.open()
	if _smoke_test:
		_start_run()


# 使用 Godot 原生生成器复制动态对象；稳定 ID 快照仍负责状态、MTU 拆包和丢包后的校正。
func _configure_network_spawners() -> void:
	if customer_spawner != null:
		customer_spawner.spawn_path = NodePath("../Entities")
		customer_spawner.spawn_function = _spawn_customer_from_network_payload
	if gate_spawner != null:
		gate_spawner.spawn_path = NodePath("../Gates")
		gate_spawner.spawn_function = _spawn_gate_from_network_payload
	if drop_spawner != null:
		drop_spawner.spawn_path = NodePath("../Drops")
		drop_spawner.spawn_function = _spawn_drop_from_network_payload
	if boss_spawner != null:
		boss_spawner.spawn_path = NodePath("../Entities")
		boss_spawner.spawn_function = _spawn_boss_from_network_payload


func _native_network_spawning_enabled() -> bool:
	return (
		_network_active
		and _network_session != null
		and _network_session.is_networked()
		and customer_spawner != null
		and gate_spawner != null
		and drop_spawner != null
		and boss_spawner != null
	)


# 给动态对象配置只包含基础类型的同步器；Resource、随机结果和统计仍走显式快照。
# 根节点属性必须使用 .:property 形式，避免 Godot 将 property 当作子节点查找。
func _attach_network_synchronizer(node: Node, properties: Array[NodePath]) -> void:
	if node == null or node.get_node_or_null("NetworkSynchronizer") != null:
		return
	var synchronizer: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	synchronizer.name = "NetworkSynchronizer"
	synchronizer.root_path = NodePath("..")
	var replication_config: SceneReplicationConfig = SceneReplicationConfig.new()
	for property_path: NodePath in properties:
		replication_config.add_property(property_path)
	synchronizer.replication_config = replication_config
	synchronizer.replication_interval = 0.05
	synchronizer.delta_interval = 0.0
	node.add_child(synchronizer)
	node.set_multiplayer_authority(1, true)


func _on_main_menu_start_requested() -> void:
	_start_run()


func _register_player_context(
	player_slot: int,
	player_peer_id: int,
	player_state: RunState,
	player_cart: Cart3D,
	player_weapon_controller: WeaponController3D
) -> PlayerRunContext:
	var context: PlayerRunContext = PlayerRunContext.new()
	context.configure(
		player_slot,
		player_peer_id,
		player_state,
		player_cart,
		player_weapon_controller
	)
	_player_contexts[player_slot] = context
	player_cart.set_player_slot(player_slot)
	player_cart.target_changed.connect(_on_player_target_changed.bind(player_slot))
	player_state.durability_changed.connect(
		_on_player_context_durability_changed.bind(player_slot)
	)
	if player_slot != 1:
		player_state.inventory_changed.connect(
			_on_player_context_inventory_changed.bind(player_slot)
		)
	if player_slot != 1:
		player_weapon_controller.food_added.connect(
			_on_player_weapon_food_added.bind(player_slot)
		)
		player_weapon_controller.food_removed.connect(
			_on_player_weapon_food_removed.bind(player_slot)
		)
		player_weapon_controller.cooking_progress_changed.connect(
			_on_player_cooking_progress_changed.bind(player_slot)
		)
	return context


func _on_player_context_durability_changed(
	current: float,
	maximum: float,
	shield: float,
	player_slot: int
) -> void:
	_refresh_player_durability_display(player_slot, current, maximum, shield)
	if _network_active:
		_update_party_hud()


# 每个窗口都刷新所有餐车头顶状态，但底部精确耐久只属于本机槽位。
func _refresh_player_durability_display(
	player_slot: int,
	current: float,
	maximum: float,
	shield: float
) -> void:
	var context: PlayerRunContext = _player_contexts.get(player_slot)
	if context == null:
		return
	if context.cart != null and is_instance_valid(context.cart):
		context.cart.set_durability_display(current, maximum, shield)
	var is_local_player: bool = (
		not _network_active
		or (
			_network_session != null
			and player_slot == int(_network_session.local_slot)
		)
	)
	if is_local_player and hud != null:
		hud.set_durability(current, maximum, shield)


func _on_player_context_inventory_changed(player_slot: int) -> void:
	if not _network_active or player_slot != _network_session.local_slot:
		return
	var context: PlayerRunContext = _player_contexts.get(player_slot)
	if context == null:
		return
	for runtime: FoodRuntime in context.weapon_controller.foods:
		hud.set_cooking_level(runtime.data.id, context.state.food_level(runtime.data.id))


func _configure_player_state(player_state: RunState, seed: int) -> void:
	player_state.run_seed = seed
	player_state.food_max_level = _special_food_max_level
	player_state.food_level_satisfaction_multiplier = _special_food_level_multiplier
	player_state.baguette_giant_interval_seconds = _baguette_giant_interval_seconds
	player_state.baguette_giant_attack_speed_scale = _baguette_giant_attack_speed_scale
	player_state.baguette_giant_minimum_interval_seconds = _baguette_giant_minimum_interval_seconds
	player_state.baguette_giant_width_regions = _baguette_giant_width_regions
	player_state.baguette_giant_pierce_count = _baguette_giant_pierce_count
	player_state.baguette_giant_duration_multiplier = _baguette_giant_duration_multiplier
	player_state.baguette_giant_satisfaction_multiplier = _baguette_giant_satisfaction_multiplier
	player_state.wine_curve_c = _wine_curve_c
	player_state.range_curve_c = _range_curve_c
	player_state.duration_curve_c = _duration_curve_c
	player_state.cart_speed_curve_c = _cart_speed_curve_c
	player_state.range_multiplier_cap = _range_multiplier_cap


# 联机开局沿用当前场景，主机先锁定人数和种子，再为每个槽位建立独立 RunState。
func _on_network_match_started(seed: int, player_count: int, roster: Array[Dictionary]) -> void:
	if phase != Phase.INTRO:
		return
	_network_active = true
	_network_player_count = clampi(player_count, 1, _network_session.MAX_PLAYERS)
	_network_announced_customer_ids.clear()
	_network_announced_gate_ids.clear()
	_network_announced_drop_ids.clear()
	_network_announced_boss = false
	_run_seed = seed
	_upgrade_rng.seed = seed
	_spawn_rng.seed = seed ^ SPAWN_SEED_SALT
	_target_rng.seed = seed ^ 0x7A26BEEF
	_player_choice_rngs.clear()
	_normal_wave_progresses = _build_normal_wave_progresses(director.timeline)
	_crosswind_sign = -1.0 if (seed & 1) == 0 else 1.0
	_configure_player_state(state, seed)
	for record: Dictionary in roster:
		var player_slot: int = int(record.get("slot", 0))
		if player_slot <= 1 or player_slot > _network_session.MAX_PLAYERS:
			continue
		var player_state: RunState = RunState.new()
		_configure_player_state(player_state, seed + player_slot * 7919)
		var player_cart: Cart3D = CART_SCENE.instantiate() as Cart3D
		if player_cart == null:
			continue
		players_root.add_child(player_cart)
		player_cart.position = cart.position
		player_cart.position.x = playfield.clamp_cart_x(
			cart.position.x + float(player_slot - 1) * 0.35
		)
		player_cart.position.z = cart.position.z
		player_cart.scale = cart.scale
		player_cart.configure(player_state, playfield, _cart_invincibility_duration_seconds)
		var player_weapon_controller: WeaponController3D = WeaponController3D.new()
		players_root.add_child(player_weapon_controller)
		player_weapon_controller.configure(
			self,
			player_cart,
			player_state,
			player_slot
		)
		_register_player_context(
			player_slot,
			int(record.get("peer_id", 0)),
			player_state,
			player_cart,
			player_weapon_controller
		)
	for player_slot: int in _player_contexts:
		var context: PlayerRunContext = _player_contexts[player_slot]
		var is_local: bool = (
			(not _network_session.is_networked() and player_slot == 1)
			or (_network_session.is_networked() and player_slot == _network_session.local_slot)
		)
		context.cart.set_input_enabled(is_local)
		context.cart.set_network_interpolation(
			_network_session.is_client() and not is_local
		)
		context.cart.set_peer_indicator_visible(
			not is_local,
			player_slot,
			_network_session.player_color(player_slot)
		)
		context.weapon_controller.set_player_slot(player_slot)
		# 主机计算所有玩家的攻击；客户端只预测本机，远端由房主发射事件重放。
		context.weapon_controller.set_process(
			not _network_session.is_client() or is_local
		)
	if _network_session.is_client() and _player_contexts.has(_network_session.local_slot):
		var local_context: PlayerRunContext = _player_contexts[_network_session.local_slot]
		state = local_context.state
		cart = local_context.cart
		weapon_controller = local_context.weapon_controller
	background.set_cart(cart)
	_start_run()


func _on_network_input_received(
	player_slot: int,
	target_x: float,
	target_z: float,
	sequence: int,
	one_way_latency_seconds: float
) -> void:
	var context: PlayerRunContext = _player_contexts.get(player_slot)
	if context == null or sequence <= context.last_input_sequence:
		return
	context.last_input_sequence = sequence
	context.cart.apply_network_target(target_x, target_z)
	if _network_session.is_host() and player_slot != _network_session.local_slot:
		context.cart.compensate_network_latency(one_way_latency_seconds)


func _on_player_target_changed(target_x: float, target_z: float, player_slot: int) -> void:
	if not _network_active or _network_session.local_slot != player_slot:
		return
	_network_session.queue_input(target_x, target_z)


func _on_network_pause_changed(paused: bool, owner_slot: int) -> void:
	if not _network_active:
		return
	# 特殊三选一必须等剩余成员全部提交，任何旧的恢复请求都不能解除它的冻结。
	if not paused and phase == Phase.CHOICE and (
		(_network_session.is_host() and not _active_special_choices_by_slot.is_empty())
		or (_network_session.is_client() and not _active_special_choices.is_empty())
	):
		get_tree().paused = true
		hud.set_pause_available(false)
		return
	_manual_pause_active = paused
	if paused:
		hud.show_pause("P%d 暂停了出餐\n暂停者或房主可以继续" % owner_slot)
		get_tree().paused = true
	else:
		hud.hide_pause()
		get_tree().paused = false
		hud.set_pause_available(phase == Phase.FORWARD or phase == Phase.BOSS)


func _on_network_event_received(event: Dictionary) -> void:
	if event.get("type", "") == "snapshot":
		_apply_network_snapshot(event.get("data", {}))
		return
	if event.get("type", "") == "world_snapshot":
		_apply_network_world_snapshot(event.get("data", {}))
		return
	if event.get("type", "") == "world_customers_fragment":
		_apply_network_customer_fragment(event.get("data", {}))
		return
	if event.get("type", "") == "world_structures":
		_apply_network_world_snapshot(event.get("data", {}))
		return
	if event.get("type", "") == "world_drops":
		_apply_network_world_snapshot(event.get("data", {}))
		return
	if event.get("type", "") == "world_config":
		_apply_network_world_config(event.get("data", {}))
		return
	if event.get("type", "") == "projectile_burst":
		var burst_data: Dictionary = event.get("data", {}) as Dictionary
		if int(burst_data.get("slot", 0)) != _network_session.local_slot:
			replay_network_projectile_burst(burst_data)
		return
	if event.get("type", "") == "egg_puddle_spawned":
		_spawn_network_egg_puddle(event.get("data", {}) as Dictionary)
		return
	if event.get("type", "") == "player_stats":
		_apply_network_player_stats(
			int(event.get("slot", 0)),
			event.get("stats", {})
		)
		return
	if event.get("type", "") == "player_stats_final":
		_apply_network_player_stats(
			int(event.get("slot", 0)),
			event.get("stats", {})
		)
		return
	if event.get("type", "") == "player_stats_final_upgrades":
		_apply_network_player_stats(
			int(event.get("slot", 0)),
			event.get("stats", {})
		)
		return
	if event.get("type", "") == "player_food_added":
		var food_slot: int = int(event.get("slot", 0))
		var food_id: StringName = StringName(str(event.get("food_id", "")))
		var food_data: FoodData = _food_data_for_id(food_id)
		var food_context: PlayerRunContext = _player_contexts.get(food_slot)
		if food_context != null and food_data != null and not food_context.state.has_food(food_id):
			food_context.weapon_controller.add_food(food_data)
			if food_slot == _network_session.local_slot:
				hud.show_toast("%s装车！自动寻找最近的食客" % food_data.display_name)
		return
	if event.get("type", "") == "upgrade_applied":
		var upgrade_slot: int = int(event.get("slot", 0))
		var network_upgrade: UpgradeData = _deserialize_network_upgrade(event.get("upgrade", {}))
		if network_upgrade != null:
			_apply_upgrade_for_player(
				upgrade_slot,
				network_upgrade,
				bool(event.get("count_as_gate", true)),
				bool(event.get("was_ghost", false)),
				upgrade_slot == _network_session.local_slot
			)
		return
	if event.get("type", "") == "special_choices":
		var choices_by_slot: Dictionary = event.get("choices", {})
		var local_choices: Array[StringName] = []
		for choice_text: String in choices_by_slot.get(str(_network_session.local_slot), []):
			local_choices.append(StringName(choice_text))
		_active_special_choices = local_choices
		_special_choice_source = StringName(event.get("source", "special"))
		_boss_reward_pending = bool(event.get("boss_reward", false))
		state.record_special_offer(_special_choice_source, local_choices)
		hud.show_special_choices(
			local_choices,
			_special_choice_texts(local_choices),
			str(event.get("title", "选择特别强化"))
		)
		get_tree().paused = true
		return
	if event.get("type", "") == "special_choice_applied":
		var applied_slot: int = int(event.get("slot", 0))
		_apply_special_choice_for_player(
			applied_slot,
			StringName(str(event.get("choice", "")))
		)
		return
	if event.get("type", "") == "special_choices_complete":
		_finish_special_choice_phase()
		return
	if event.get("type", "") == "match_failed":
		if not _network_session.is_host():
			phase = Phase.FAILED
			_save_playtest_record(&"failed")
			hud.set_phase("全员幽灵 · 本局结束")
			hud.show_results("服务失败", "所有玩家同时失去行动资格。")
			get_tree().paused = true
		return
	if event.get("type", "") == "match_completed":
		if not _network_session.is_host():
			phase = Phase.RESULTS
			_record_final_boss_unlock()
			_save_playtest_record(&"completed")
			hud.set_phase("构筑验证完成")
			hud.show_results("最终Boss满意离场，八分钟服务完成！", "房主已完成本局结算。")
			get_tree().paused = true
		return
	if event.get("type", "") == "player_left":
		var player_slot: int = int(event.get("slot", 0))
		var context: PlayerRunContext = _player_contexts.get(player_slot)
		if context != null:
			context.cart.visible = false


func _broadcast_player_snapshot() -> void:
	if not _network_active or not _network_session.is_host():
		return
	var players: Array[Dictionary] = []
	for player_slot: int in _player_contexts:
		var context: PlayerRunContext = _player_contexts[player_slot]
		players.append({
			"slot": player_slot,
			"x": context.cart.position.x,
			"z": context.cart.position.z,
			"input_sequence": context.last_input_sequence,
			"current": context.state.current_durability,
			"maximum": context.state.maximum_durability,
			"shield": context.state.temporary_shield,
			"ghost": context.is_ghost(),
			"respawn": context.respawn_remaining,
			"deaths": context.death_count,
			"ghost_seconds": context.ghost_elapsed_seconds,
			"team_death_count": _team_death_count,
		})
	var snapshot: Dictionary = {
		"phase": int(phase),
		"elapsed": state.elapsed_seconds,
		"forward_distance": state.forward_distance,
		"players": players,
	}
	var customer_snapshot: Dictionary = {
		"customers": _network_customer_snapshots(),
	}
	var world_structures_snapshot: Dictionary = {
		"gates": _network_gate_snapshots(),
	}
	var world_drops_snapshot: Dictionary = {
		"drops": _network_drop_snapshots(),
		"boss": boss.network_snapshot() if boss != null and is_instance_valid(boss) else {},
	}
	_apply_network_snapshot(snapshot)
	_apply_network_world_snapshot(customer_snapshot)
	_apply_network_world_snapshot(world_structures_snapshot)
	_apply_network_world_snapshot(world_drops_snapshot)
	var world_config: Dictionary = _network_world_config_for_new_objects()
	if not world_config.is_empty():
		_send_network_world_config(world_config)
	_network_session.send_snapshot(snapshot)
	_network_customer_snapshot_cycle += 1
	_network_session.send_world_customers_snapshot(
		_network_customer_snapshot_cycle,
		customer_snapshot.get("customers", [])
	)
	_network_session.send_world_structures_snapshot(world_structures_snapshot)
	_network_session.send_world_drops_snapshot(world_drops_snapshot)


# 可靠配置按对象拆分，长局中同时生成多个对象时仍保持每个事件低于MTU。
func _send_network_world_config(config: Dictionary) -> void:
	for key: String in ["customers", "gates", "drops"]:
		for record: Dictionary in config.get(key, []):
			_network_session.send_game_event({
				"type": "world_config",
				"data": {key: [record]},
			})
	if config.has("boss"):
		_network_session.send_game_event({
			"type": "world_config",
			"data": {"boss": config.get("boss", {})},
		})


# 每位玩家的统计单独发送，客户端用于个人战绩，核心位置包只保留高频状态。
func _broadcast_player_stats_snapshot() -> void:
	if not _network_active or not _network_session.is_host():
		return
	for player_slot: int in _player_contexts:
		var context: PlayerRunContext = _player_contexts[player_slot]
		_network_session.send_player_stats(player_slot, _network_live_player_stats_payload(context))


func _network_live_player_stats_payload(context: PlayerRunContext) -> Dictionary:
	return {
		"hits_taken": context.state.hits_taken,
		"durability_lost": context.state.durability_lost,
		"customers_satisfied": context.state.customers_satisfied,
		"normal_defeats": context.state.normal_defeats,
		"normal_customers_spawned": context.state.normal_customers_spawned,
		"collided_defeats": context.state.collided_defeats,
		"upgrade_drops_spawned": context.state.upgrade_drops_spawned,
		"gate_choices": context.state.gate_choices,
		"dropped_upgrades": context.state.dropped_upgrades,
		"satisfaction_by_food": _serialize_float_dictionary(
			context.state.satisfaction_by_food
		),
	}


func _network_upgrade_stats_payload(context: PlayerRunContext) -> Dictionary:
	return {
		"normal_upgrade_offer_counts": _serialize_int_dictionary(
			context.state.normal_upgrade_offer_counts
		),
		"normal_upgrade_choice_counts": _serialize_int_dictionary(
			context.state.normal_upgrade_choice_counts
		),
		"normal_upgrade_value_totals": _serialize_float_dictionary(
			context.state.normal_upgrade_value_totals
		),
		"normal_upgrade_contribution_totals": _serialize_float_dictionary(
			context.state.normal_upgrade_contribution_totals
		),
	}


# 结算事件前可靠补发最终统计，保证客户端记录不会落后最后一次不可靠快照。
func _broadcast_final_player_stats() -> void:
	if not _network_active or not _network_session.is_host():
		return
	for player_slot: int in _player_contexts:
		var context: PlayerRunContext = _player_contexts[player_slot]
		_network_session.send_game_event({
			"type": "player_stats_final",
			"slot": player_slot,
			"stats": _network_live_player_stats_payload(context),
		})
		_network_session.send_game_event({
			"type": "player_stats_final_upgrades",
			"slot": player_slot,
			"stats": _network_upgrade_stats_payload(context),
		})


func _apply_network_player_stats(player_slot: int, stats_variant: Variant) -> void:
	if not stats_variant is Dictionary:
		return
	var context: PlayerRunContext = _player_contexts.get(player_slot)
	if context == null:
		return
	var stats: Dictionary = stats_variant as Dictionary
	context.state.hits_taken = int(stats.get("hits_taken", context.state.hits_taken))
	context.state.durability_lost = float(
		stats.get("durability_lost", context.state.durability_lost)
	)
	context.state.customers_satisfied = int(
		stats.get("customers_satisfied", context.state.customers_satisfied)
	)
	context.state.normal_defeats = int(stats.get("normal_defeats", context.state.normal_defeats))
	context.state.normal_customers_spawned = int(
		stats.get("normal_customers_spawned", context.state.normal_customers_spawned)
	)
	context.state.collided_defeats = int(
		stats.get("collided_defeats", context.state.collided_defeats)
	)
	context.state.upgrade_drops_spawned = int(
		stats.get("upgrade_drops_spawned", context.state.upgrade_drops_spawned)
	)
	context.state.gate_choices = int(stats.get("gate_choices", context.state.gate_choices))
	context.state.dropped_upgrades = int(
		stats.get("dropped_upgrades", context.state.dropped_upgrades)
	)
	var satisfaction: Variant = stats.get("satisfaction_by_food", null)
	if satisfaction is Dictionary:
		context.state.satisfaction_by_food = _deserialize_float_dictionary(satisfaction)
	var offers: Variant = stats.get("normal_upgrade_offer_counts", null)
	if offers is Dictionary:
		context.state.normal_upgrade_offer_counts = _deserialize_int_dictionary(offers)
	var choices: Variant = stats.get("normal_upgrade_choice_counts", null)
	if choices is Dictionary:
		context.state.normal_upgrade_choice_counts = _deserialize_int_dictionary(choices)
	var values: Variant = stats.get("normal_upgrade_value_totals", null)
	if values is Dictionary:
		context.state.normal_upgrade_value_totals = _deserialize_float_dictionary(values)
	var contributions: Variant = stats.get("normal_upgrade_contribution_totals", null)
	if contributions is Dictionary:
		context.state.normal_upgrade_contribution_totals = _deserialize_float_dictionary(
			contributions
		)


func _serialize_int_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in source:
		result[str(key)] = int(source[key])
	return result


func _serialize_float_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in source:
		result[str(key)] = float(source[key])
	return result


func _deserialize_int_dictionary(source: Dictionary) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for key: Variant in source:
		result[StringName(str(key))] = int(source[key])
	return result


func _deserialize_float_dictionary(source: Dictionary) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for key: Variant in source:
		result[StringName(str(key))] = float(source[key])
	return result


func _apply_network_snapshot(snapshot: Dictionary) -> void:
	if not _network_active:
		return
	if snapshot.has("phase"):
		phase = int(snapshot.get("phase", int(phase)))
	if snapshot.has("elapsed") and state != null:
		state.elapsed_seconds = float(snapshot.get("elapsed", state.elapsed_seconds))
		state.forward_distance = float(snapshot.get("forward_distance", state.forward_distance))
		hud.set_time(state.elapsed_seconds)
	for record: Dictionary in snapshot.get("players", []):
		var player_slot: int = int(record.get("slot", 0))
		var context: PlayerRunContext = _player_contexts.get(player_slot)
		if context == null:
			continue
		var authoritative_position: Vector3 = Vector3(
			float(record.get("x", context.cart.position.x)),
			context.cart.position.y,
			float(record.get("z", context.cart.position.z))
		)
		var is_local_player: bool = player_slot == _network_session.local_slot
		if _network_session.is_client() and is_local_player:
			var acknowledged_sequence: int = int(record.get("input_sequence", 0))
			if acknowledged_sequence >= _network_session.latest_input_sequence():
				var compensated_position: Vector3 = context.cart.extrapolate_network_position(
					authoritative_position,
					_network_session.estimated_one_way_latency_seconds(1)
				)
				context.cart.apply_network_position(compensated_position, true, false)
		else:
			context.cart.apply_network_position(
				authoritative_position,
				false,
				_network_session.is_client()
			)
		context.state.current_durability = float(
			record.get("current", context.state.current_durability)
		)
		context.state.maximum_durability = float(
			record.get("maximum", context.state.maximum_durability)
		)
		context.state.temporary_shield = float(
			record.get("shield", context.state.temporary_shield)
		)
		context.respawn_remaining = float(record.get("respawn", context.respawn_remaining))
		context.death_count = int(record.get("deaths", context.death_count))
		context.ghost_elapsed_seconds = float(
			record.get("ghost_seconds", context.ghost_elapsed_seconds)
		)
		_team_death_count = int(record.get("team_death_count", _team_death_count))
		context.state.hits_taken = int(record.get("hits_taken", context.state.hits_taken))
		context.state.durability_lost = float(
			record.get("durability_lost", context.state.durability_lost)
		)
		context.state.customers_satisfied = int(
			record.get("customers_satisfied", context.state.customers_satisfied)
		)
		context.state.normal_defeats = int(record.get("normal_defeats", context.state.normal_defeats))
		context.state.normal_customers_spawned = int(
			record.get("normal_customers_spawned", context.state.normal_customers_spawned)
		)
		context.state.collided_defeats = int(
			record.get("collided_defeats", context.state.collided_defeats)
		)
		context.state.gate_choices = int(record.get("gate_choices", context.state.gate_choices))
		context.state.dropped_upgrades = int(
			record.get("dropped_upgrades", context.state.dropped_upgrades)
		)
		var satisfaction_by_food: Variant = record.get("satisfaction_by_food", null)
		if satisfaction_by_food is Dictionary:
			var normalized_satisfaction: Dictionary[StringName, float] = {}
			for food_id: Variant in satisfaction_by_food:
				normalized_satisfaction[StringName(str(food_id))] = float(
					satisfaction_by_food[food_id]
				)
			context.state.satisfaction_by_food = normalized_satisfaction
		var ghost: bool = bool(record.get("ghost", context.is_ghost()))
		context.life_state = (
			PlayerRunContext.LifeState.GHOST
			if ghost
			else PlayerRunContext.LifeState.ALIVE
		)
		context.cart.set_ghost_visual(ghost)
		_refresh_player_durability_display(
			player_slot,
			context.state.current_durability,
			context.state.maximum_durability,
			context.state.temporary_shield
		)
	_update_party_hud()


func _network_customer_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for customer: Customer3D in customers:
		if is_instance_valid(customer):
			snapshots.append(customer.network_snapshot())
	return snapshots


func _network_gate_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for child: Node in gates.get_children():
		if child is UpgradeGate3D and not child.is_queued_for_deletion():
			snapshots.append((child as UpgradeGate3D).network_snapshot())
	return snapshots


func _network_drop_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for child: Node in drops.get_children():
		if child is UpgradeDrop3D and not child.is_queued_for_deletion():
			snapshots.append((child as UpgradeDrop3D).network_snapshot())
	return snapshots


# 收集本次快照中首次出现的对象配置，并通过可靠事件发送给客户端。
func _network_world_config_for_new_objects() -> Dictionary:
	var config: Dictionary = {}
	var customer_config: Array[Dictionary] = []
	for customer: Customer3D in customers:
		if not is_instance_valid(customer) or _network_announced_customer_ids.has(customer.spawn_index):
			continue
		var customer_snapshot: Dictionary = customer.network_snapshot()
		customer_snapshot["data_id"] = str(customer.data.id) if customer.data != null else ""
		customer_snapshot["baseline_appetite"] = customer.reward_baseline_appetite
		customer_snapshot["reward_upgrade_ref"] = _serialize_network_upgrade_ref(customer.reward_upgrade)
		customer_config.append(customer_snapshot)
		_network_announced_customer_ids[customer.spawn_index] = true
	if not customer_config.is_empty():
		config["customers"] = customer_config
	var gate_config: Array[Dictionary] = []
	for child: Node in gates.get_children():
		if not child is UpgradeGate3D or child.is_queued_for_deletion():
			continue
		var gate: UpgradeGate3D = child as UpgradeGate3D
		if _network_announced_gate_ids.has(gate.spawn_index):
			continue
		var gate_snapshot: Dictionary = gate.network_snapshot()
		gate_snapshot["start_food_gate"] = gate.start_food_gate
		gate_snapshot["baseline_appetite"] = gate.baseline_appetite
		gate_snapshot["left_upgrade_ref"] = _serialize_network_upgrade_ref(gate.left_upgrade)
		gate_snapshot["right_upgrade_ref"] = _serialize_network_upgrade_ref(gate.right_upgrade)
		var options_by_slot: Dictionary = {}
		for player_slot: int in gate.start_options_by_slot:
			var options: Array = []
			for option: Variant in gate.start_options_by_slot[player_slot]:
				if option is UpgradeData:
					options.append(_serialize_network_upgrade_ref(option as UpgradeData))
			options_by_slot[str(player_slot)] = options
		gate_snapshot["start_options_by_slot"] = options_by_slot
		gate_config.append(gate_snapshot)
		_network_announced_gate_ids[gate.spawn_index] = true
	if not gate_config.is_empty():
		config["gates"] = gate_config
	var drop_config: Array[Dictionary] = []
	for child: Node in drops.get_children():
		if not child is UpgradeDrop3D or child.is_queued_for_deletion():
			continue
		var drop: UpgradeDrop3D = child as UpgradeDrop3D
		if _network_announced_drop_ids.has(drop.spawn_index):
			continue
		var drop_snapshot: Dictionary = drop.network_snapshot()
		drop_snapshot["baseline_appetite"] = drop.baseline_appetite
		drop_snapshot["occupied_regions"] = drop.occupied_regions
		drop_snapshot["upgrade_ref"] = _serialize_network_upgrade_ref(drop.upgrade)
		drop_config.append(drop_snapshot)
		_network_announced_drop_ids[drop.spawn_index] = true
	if not drop_config.is_empty():
		config["drops"] = drop_config
	if boss != null and is_instance_valid(boss) and not _network_announced_boss:
		config["boss"] = boss.network_snapshot()
		_network_announced_boss = true
	return config


func _apply_network_world_snapshot(snapshot: Dictionary) -> void:
	if _network_session.is_host():
		return
	if snapshot.has("customers"):
		var seen_customers: Dictionary[int, bool] = {}
		for record: Dictionary in snapshot.get("customers", []):
			var customer_index: int = int(record.get("spawn_index", 0))
			seen_customers[customer_index] = true
			var target_customer: Customer3D = _find_customer_by_spawn_index(customer_index)
			if target_customer == null:
				if _native_network_spawning_enabled():
					continue
				target_customer = _instantiate_network_customer(record)
			if target_customer != null:
				target_customer.apply_network_snapshot(record)
		if not _native_network_spawning_enabled():
			for customer: Customer3D in customers.duplicate():
				if is_instance_valid(customer) and not seen_customers.has(customer.spawn_index):
					customers.erase(customer)
					customer.queue_free()
	if snapshot.has("gates"):
		var seen_gates: Dictionary[int, bool] = {}
		for record: Dictionary in snapshot.get("gates", []):
			var gate_index: int = int(record.get("spawn_index", 0))
			seen_gates[gate_index] = true
			var target_gate: UpgradeGate3D = _find_gate_by_spawn_index(gate_index)
			if target_gate == null:
				if _native_network_spawning_enabled():
					continue
				target_gate = _instantiate_network_gate(record)
			if target_gate != null:
				target_gate.apply_network_snapshot(record)
		if not _native_network_spawning_enabled():
			for child: Node in gates.get_children().duplicate():
				if child is UpgradeGate3D:
					var gate: UpgradeGate3D = child as UpgradeGate3D
					if not seen_gates.has(gate.spawn_index):
						gate.queue_free()
	if snapshot.has("drops"):
		var seen_drops: Dictionary[int, bool] = {}
		for record: Dictionary in snapshot.get("drops", []):
			var drop_index: int = int(record.get("spawn_index", 0))
			seen_drops[drop_index] = true
			var target_drop: UpgradeDrop3D = _find_drop_by_spawn_index(drop_index)
			if target_drop == null:
				if _native_network_spawning_enabled():
					continue
				target_drop = _instantiate_network_drop(record)
			if target_drop != null:
				target_drop.apply_network_snapshot(record)
		if not _native_network_spawning_enabled():
			for child: Node in drops.get_children().duplicate():
				if child is UpgradeDrop3D:
					var drop: UpgradeDrop3D = child as UpgradeDrop3D
					if not seen_drops.has(drop.spawn_index):
						drop.queue_free()
	if snapshot.has("boss"):
		var boss_snapshot: Dictionary = snapshot.get("boss", {})
		if boss_snapshot.is_empty():
			if not _native_network_spawning_enabled() and boss != null and is_instance_valid(boss):
				boss.queue_free()
			boss = null
		elif boss == null or not is_instance_valid(boss):
			if _native_network_spawning_enabled():
				return
			boss = _spawn_boss_from_network_payload(boss_snapshot) as PrototypeBoss3D
			if boss != null and not boss.is_inside_tree():
				entities.add_child(boss)
		if boss != null and is_instance_valid(boss):
			boss.apply_network_snapshot(boss_snapshot)


# 应用食客动态小分片；只有收到本周期末片才清理上一周期不存在的食客。
func _apply_network_customer_fragment(fragment_variant: Variant) -> void:
	if _network_session.is_host() or not fragment_variant is Dictionary:
		return
	var fragment: Dictionary = fragment_variant as Dictionary
	var cycle: int = int(fragment.get("cycle", -1))
	if cycle < 0:
		return
	if cycle != _network_customer_fragment_cycle:
		_network_customer_fragment_cycle = cycle
		_network_customer_fragment_seen.clear()
	for record: Dictionary in fragment.get("records", []):
		var customer_index: int = int(record.get("spawn_index", 0))
		_network_customer_fragment_seen[customer_index] = true
		var target_customer: Customer3D = _find_customer_by_spawn_index(customer_index)
		if target_customer != null:
			target_customer.apply_network_snapshot(record)
	if not bool(fragment.get("complete", false)):
		return
	if not _native_network_spawning_enabled():
		for customer: Customer3D in customers.duplicate():
			if is_instance_valid(customer) and not _network_customer_fragment_seen.has(customer.spawn_index):
				customers.erase(customer)
				customer.queue_free()


# 应用可靠对象配置；动态快照只负责更新位置、血量和活动状态。
func _apply_network_world_config(config: Dictionary) -> void:
	if _network_session.is_host():
		return
	for record: Dictionary in config.get("customers", []):
		var customer: Customer3D = _find_customer_by_spawn_index(int(record.get("spawn_index", 0)))
		if customer == null:
			if _native_network_spawning_enabled():
				continue
			customer = _instantiate_network_customer(record)
		if customer != null:
			customer.apply_network_snapshot(record)
	for record: Dictionary in config.get("gates", []):
		var gate: UpgradeGate3D = _find_gate_by_spawn_index(int(record.get("spawn_index", 0)))
		if gate == null:
			if _native_network_spawning_enabled():
				continue
			gate = _instantiate_network_gate(record)
		if gate != null:
			gate.apply_network_snapshot(record)
	for record: Dictionary in config.get("drops", []):
		var drop: UpgradeDrop3D = _find_drop_by_spawn_index(int(record.get("spawn_index", 0)))
		if drop == null:
			if _native_network_spawning_enabled():
				continue
			drop = _instantiate_network_drop(record)
		if drop != null:
			drop.apply_network_snapshot(record)
	var boss_config: Dictionary = config.get("boss", {})
	if not boss_config.is_empty():
		if boss == null or not is_instance_valid(boss):
			if _native_network_spawning_enabled():
				return
			boss = _spawn_boss_from_network_payload(boss_config) as PrototypeBoss3D
			if boss != null and not boss.is_inside_tree():
				entities.add_child(boss)
		if boss != null and is_instance_valid(boss):
			boss.apply_network_snapshot(boss_config)


# 按稳定食客 ID 创建客户端视觉对象，不在客户端增加运行统计。
func _instantiate_network_customer(record: Dictionary) -> Customer3D:
	var customer: Customer3D = _spawn_customer_from_network_payload(record) as Customer3D
	if customer != null and not customer.is_inside_tree():
		entities.add_child(customer)
	return customer


# MultiplayerSpawner 的统一食客构造回调；主机和客户端都只从稳定字段恢复对象。
func _spawn_customer_from_network_payload(payload: Variant) -> Node:
	if not payload is Dictionary:
		return null
	var record: Dictionary = payload as Dictionary
	var customer_data: CustomerData = _customer_data_by_id.get(
		StringName(str(record.get("data_id", "")))
	)
	if customer_data == null:
		return null
	var customer: Customer3D = _instantiate_customer(customer_data)
	if customer == null:
		return null
	customer.position = Vector3(
		float(record.get("x", 0.0)),
		0.0,
		float(record.get("z", Playfield.FORWARD_SPAWN_Z))
	)
	customer.configure(
		customer_data,
		self,
		int(record.get("spawn_index", 0)),
		float(record.get("appetite", 1.0)),
		_deserialize_network_upgrade_ref(
			record.get("reward_upgrade_ref", record.get("reward_upgrade", {}))
		),
		float(record.get("baseline_appetite", 1.0))
	)
	customer.satisfied.connect(_on_customer_satisfied)
	customer.collided_with_cart.connect(_on_customer_collided_with_cart)
	customer.escaped.connect(_on_customer_escaped)
	customer.ranged_attack.connect(_on_customer_ranged_attack)
	_attach_network_synchronizer(
		customer,
		[NodePath(".:position"), NodePath(".:active"), NodePath(".:remaining_appetite")]
	)
	_track_customer(customer)
	return customer


# 按稳定强化引用创建普通门，并保留每个槽位的开局候选。
func _instantiate_network_gate(record: Dictionary) -> UpgradeGate3D:
	var gate: UpgradeGate3D = _spawn_gate_from_network_payload(record) as UpgradeGate3D
	if gate != null and not gate.is_inside_tree():
		gates.add_child(gate)
	return gate


# MultiplayerSpawner 的统一普通门构造回调；候选和门血量仍由稳定快照字段恢复。
func _spawn_gate_from_network_payload(payload: Variant) -> Node:
	if not payload is Dictionary:
		return null
	var record: Dictionary = payload as Dictionary
	var left_upgrade: UpgradeData = _deserialize_network_upgrade_ref(
		record.get("left_upgrade_ref", record.get("left_upgrade", {}))
	)
	var right_upgrade: UpgradeData = _deserialize_network_upgrade_ref(
		record.get("right_upgrade_ref", record.get("right_upgrade", {}))
	)
	if left_upgrade == null or right_upgrade == null:
		return null
	var gate: UpgradeGate3D = GATE_SCENE.instantiate() as UpgradeGate3D
	if gate == null:
		return null
	var options_by_slot: Dictionary[int, Array] = {}
	var options_payload: Dictionary = record.get("start_options_by_slot", {}) as Dictionary
	for slot_text: String in options_payload:
		var options: Array = []
		for upgrade_payload: Variant in options_payload[slot_text]:
			var option: UpgradeData = _deserialize_network_upgrade_ref(upgrade_payload)
			if option != null:
				options.append(option)
		options_by_slot[int(slot_text)] = options
	gate.configure(
		self,
		left_upgrade,
		right_upgrade,
		bool(record.get("start_food_gate", false)),
		float(record.get("baseline_appetite", 1.0)),
		int(record.get("spawn_index", 0)),
		options_by_slot,
		float(record.get("display_maximum_durability", 100.0))
	)
	_attach_network_synchronizer(
		gate,
		[
			NodePath(".:position"),
			NodePath(".:resolved"),
			NodePath(".:left_base_health"),
			NodePath(".:right_base_health"),
		]
	)
	return gate


# 按稳定强化引用创建奖励门视觉对象。
func _instantiate_network_drop(record: Dictionary) -> UpgradeDrop3D:
	var drop: UpgradeDrop3D = _spawn_drop_from_network_payload(record) as UpgradeDrop3D
	if drop != null and not drop.is_inside_tree():
		drops.add_child(drop)
	return drop


# MultiplayerSpawner 的统一奖励门构造回调；领取资格由稳定槽位快照继续维护。
func _spawn_drop_from_network_payload(payload: Variant) -> Node:
	if not payload is Dictionary:
		return null
	var record: Dictionary = payload as Dictionary
	var upgrade: UpgradeData = _deserialize_network_upgrade_ref(
		record.get("upgrade_ref", record.get("upgrade", {}))
	)
	if upgrade == null:
		return null
	var drop: UpgradeDrop3D = REWARD_GATE_SCENE.instantiate() as UpgradeDrop3D
	if drop == null:
		return null
	drop.configure(
		self,
		upgrade,
		Vector3(float(record.get("x", 0.0)), 0.0, float(record.get("z", 0.0))),
		float(record.get("baseline_appetite", 1.0)),
		int(record.get("occupied_regions", 2)),
		int(record.get("spawn_index", 0)),
		float(record.get("display_maximum_durability", 100.0))
	)
	_attach_network_synchronizer(
		drop,
		[NodePath(".:position"), NodePath(".:resolved"), NodePath(".:upgrade_health")]
	)
	return drop


# Boss 也通过原生生成器复制；攻击锁定和命中时刻仍由主机权威裁决。
func _spawn_boss_from_network_payload(payload: Variant) -> Node:
	if not payload is Dictionary:
		return null
	var record: Dictionary = payload as Dictionary
	var spawned_boss: PrototypeBoss3D = BOSS_SCENE.instantiate() as PrototypeBoss3D
	if spawned_boss == null:
		return null
	spawned_boss.configure(
		boss_data,
		self,
		float(record.get("baseline_appetite", _current_baseline_appetite())),
		int(record.get("player_count", _network_player_count))
	)
	spawned_boss.satisfied.connect(_on_boss_satisfied)
	_attach_network_synchronizer(
		spawned_boss,
		[
			NodePath(".:position"),
			NodePath(".:active"),
			NodePath(".:remaining_appetite"),
			NodePath(".:host_execution_time"),
		]
	)
	boss = spawned_boss
	return spawned_boss


# 客户端的原生 despawn 可能先释放节点；查找时先剔除遗留引用再做强类型访问。
func _find_customer_by_spawn_index(spawn_index: int) -> Customer3D:
	var index: int = 0
	while index < customers.size():
		var candidate: Variant = customers[index]
		if not is_instance_valid(candidate):
			customers.remove_at(index)
			continue
		var customer: Customer3D = candidate as Customer3D
		if customer.spawn_index == spawn_index:
			return customer
		index += 1
	return null


# 统一维护食客集合生命周期，确保 MultiplayerSpawner 销毁客户端节点时同步注销引用。
func _track_customer(customer: Customer3D) -> void:
	if customer == null or customers.has(customer):
		return
	customers.append(customer)
	customer.tree_exiting.connect(_on_customer_tree_exiting.bind(customer), CONNECT_ONE_SHOT)


func _on_customer_tree_exiting(customer: Customer3D) -> void:
	customers.erase(customer)


func _find_gate_by_spawn_index(spawn_index: int) -> UpgradeGate3D:
	for child: Node in gates.get_children():
		if child is UpgradeGate3D and (child as UpgradeGate3D).spawn_index == spawn_index:
			return child as UpgradeGate3D
	return null


func _find_drop_by_spawn_index(spawn_index: int) -> UpgradeDrop3D:
	for child: Node in drops.get_children():
		if child is UpgradeDrop3D and (child as UpgradeDrop3D).spawn_index == spawn_index:
			return child as UpgradeDrop3D
	return null


func _update_party_hud() -> void:
	if not _network_active:
		return
	var records: Array[Dictionary] = []
	for player_slot: int in _player_contexts:
		var context: PlayerRunContext = _player_contexts[player_slot]
		var record: Dictionary = {
			"slot": player_slot,
			"color": _network_session.player_color(player_slot).to_html(false),
		}
		for roster_record: Dictionary in _network_session.get_roster():
			if int(roster_record.get("slot", 0)) == player_slot:
				record = roster_record.duplicate(true)
				break
		record["current"] = context.state.current_durability
		record["maximum"] = context.state.maximum_durability
		record["shield"] = context.state.temporary_shield
		record["ghost"] = context.is_ghost()
		record["respawn"] = context.respawn_remaining
		records.append(record)
	hud.set_party_health(records, _network_session.local_slot if _network_session.local_slot > 0 else 1)


func _on_network_match_returned_to_lobby() -> void:
	_schedule_network_scene_reload()


func _on_network_connection_state_changed(connection_state: StringName, _message: String) -> void:
	if connection_state != &"server_disconnected" or not _network_active:
		return
	_network_active = false
	get_tree().paused = false
	_schedule_network_scene_reload()


func _on_network_roster_changed(roster: Array[Dictionary]) -> void:
	if not _network_active:
		return
	var connected_slots: Dictionary[int, bool] = {}
	for record: Dictionary in roster:
		connected_slots[int(record.get("slot", 0))] = true
	for player_slot: int in _player_contexts.keys().duplicate():
		if connected_slots.has(player_slot):
			continue
		var context: PlayerRunContext = _player_contexts[player_slot]
		_player_contexts.erase(player_slot)
		if context.cart != null and is_instance_valid(context.cart):
			context.cart.queue_free()
		if context.weapon_controller != null and is_instance_valid(context.weapon_controller):
			context.weapon_controller.queue_free()
	if phase == Phase.CHOICE and not _active_special_choices_by_slot.is_empty():
		if _selected_special_choices_by_slot.size() >= _player_contexts.size():
			_finish_special_choice_phase()
	_update_party_hud()


func _schedule_network_scene_reload() -> void:
	if _network_scene_reload_pending:
		return
	_network_scene_reload_pending = true
	call_deferred("_reload_after_network_match")


func _reload_after_network_match() -> void:
	get_tree().paused = false
	if _network_session != null and _network_session.is_client():
		# 客户端仍保留原 Spawner 一帧以上，避免迟到的主机销毁包落到新场景。
		await get_tree().create_timer(NETWORK_SCENE_RELOAD_DELAY_SECONDS).timeout
	if not is_inside_tree():
		return
	get_tree().reload_current_scene()


func _reload_after_network_disconnect() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_player_weapon_food_added(food: FoodData, player_slot: int) -> void:
	if not _is_local_hud_player(player_slot):
		return
	var context: PlayerRunContext = _player_contexts.get(player_slot)
	if context == null:
		return
	hud.add_cooking_food(food, context.state.food_level(food.id))


func _on_player_weapon_food_removed(food_id: StringName, player_slot: int) -> void:
	if _is_local_hud_player(player_slot):
		hud.remove_cooking_food(food_id)


func _on_player_cooking_progress_changed(
	food_id: StringName,
	progress: float,
	remaining_seconds: float,
	player_slot: int
) -> void:
	if not _is_local_hud_player(player_slot):
		return
	hud.set_cooking_progress(food_id, progress, remaining_seconds)


# HUD 只接收当前窗口本地玩家的食材状态；远端构筑仍保留在对应上下文中参与网络重放。
func _is_local_hud_player(player_slot: int) -> bool:
	if not _network_active:
		return player_slot == 1
	return _network_session != null and int(_network_session.local_slot) == player_slot


# 从启动菜单进入单局，只有这里把 INTRO 变为正式前进阶段。
func _start_run() -> void:
	if phase != Phase.INTRO:
		return
	phase = Phase.FORWARD
	background.scrolling = true
	hud.visible = true
	main_menu.close()
	hud.set_phase("准备出餐 · 横向拖动餐车")
	hud.show_toast("按住并横向拖动，松手后餐车留在原位")
	hud.set_pause_available(true)
	_update_party_hud()


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


# 战斗规则只在开局读取一次，缺表或非法值时沿用代码中的当前安全值。
func _load_combat_rules_balance() -> void:
	var load_result: GameplayExcelLoader.CombatRulesLoadResult = (
		GameplayExcelLoader.load_combat_rules(COMBAT_RULES_WORKBOOK_PATH)
	)
	if load_result.loaded_from_excel:
		# 只有整表通过严格校验才应用，避免坏表把前面已解析的部分值带入本局。
		_cart_invincibility_duration_seconds = load_result.cart_invincibility_duration_seconds
		# Excel值写入运行时副本，避免改写场景引用的共享Boss Resource。
		if boss_data != null:
			var runtime_boss_data: BossPatternData = boss_data.duplicate(true) as BossPatternData
			if runtime_boss_data != null:
				runtime_boss_data.appetite_multiplier = load_result.boss_appetite_multiplier
				boss_data = runtime_boss_data
		_respawn_base_seconds = load_result.respawn_base_seconds
		_respawn_increment_seconds = load_result.respawn_increment_seconds
		_respawn_max_seconds = load_result.respawn_max_seconds
		_ghost_damage_multiplier = load_result.ghost_damage_multiplier
		_respawn_durability_ratio = load_result.respawn_durability_ratio
		_respawn_invincibility_seconds = load_result.respawn_invincibility_seconds
		print(
			"BALANCE_COMBAT_RULES_LOADED path=%s boss_multiplier=%.3f cart_invincibility=%.3f respawn=%.1f/%.1f/%.1f ghost=%.3f" % [
				COMBAT_RULES_WORKBOOK_PATH,
				load_result.boss_appetite_multiplier,
				_cart_invincibility_duration_seconds,
				_respawn_base_seconds,
				_respawn_increment_seconds,
				_respawn_max_seconds,
				_ghost_damage_multiplier,
			]
		)
	else:
		push_warning(
			"BALANCE_COMBAT_RULES_FALLBACK path=%s reason=%s" % [
				COMBAT_RULES_WORKBOOK_PATH,
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
		if _food_data_by_id.has(&"egg"):
			egg_data = _food_data_by_id[&"egg"]
		if _food_data_by_id.has(&"carrot"):
			carrot_data = _food_data_by_id[&"carrot"]
		if load_result.egg_puddle_data != null:
			egg_puddle_data = load_result.egg_puddle_data
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
		_reward_effect_scale_initial = load_result.reward_effect_scale
		_reward_effect_scale_after_elite = load_result.reward_effect_scale_after_elite
		_reward_effect_scale_transition_seconds = load_result.reward_effect_scale_transition_seconds
		_wine_curve_c = load_result.wine_curve_c
		_range_curve_c = load_result.range_curve_c
		_duration_curve_c = load_result.duration_curve_c
		_cart_speed_curve_c = load_result.cart_speed_curve_c
		_range_multiplier_cap = load_result.range_multiplier_cap
		_reset_reward_effect_scale()
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
	_reset_reward_effect_scale()


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
	for food: FoodData in [potato_data, baguette_data, mushroom_data, egg_data, carrot_data]:
		if food != null:
			_food_data_by_id[food.id] = food
	if egg_data != null:
		# 回退时仍从当前鸡蛋资源重建，避免场景中的旧副本绕过继承规则。
		egg_puddle_data = _make_fallback_egg_puddle_data()
	elif egg_puddle_data == null:
		egg_puddle_data = _make_fallback_egg_puddle_data()


func _make_fallback_egg_puddle_data() -> FoodData:
	var puddle: FoodData = (
		egg_data.duplicate(true) as FoodData
		if egg_data != null
		else FoodData.new()
	)
	puddle.id = &"egg_puddle"
	puddle.display_name = "蛋液"
	puddle.attack_kind = FoodData.AttackKind.EGG_PUDDLE
	puddle.base_interval = 0.5
	if egg_data == null:
		puddle.base_satisfaction = 10.0
		puddle.projectile_radius = 17.0
		puddle.base_lifetime = 1.3473684
	return puddle


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
				str(upgrade.id),
				str(upgrade.target_id),
			]
	return ""


func _process(delta: float) -> void:
	if _network_active and _network_session.is_host():
		_tick_network_lives(delta)
		_network_snapshot_accumulator += delta
		_network_stats_accumulator += delta
		if _network_snapshot_accumulator >= 0.05:
			_network_snapshot_accumulator = 0.0
			_broadcast_player_snapshot()
		if _network_stats_accumulator >= 0.5:
			_network_stats_accumulator = 0.0
			_broadcast_player_stats_snapshot()
	hud.set_pause_available(phase == Phase.FORWARD or phase == Phase.BOSS)
	var network_client_visual_only: bool = (
		_network_active and _network_session.is_client()
	)
	if not network_client_visual_only and phase == Phase.FORWARD:
		state.elapsed_seconds += delta
		_update_reward_effect_scale(delta)
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
	elif not network_client_visual_only and phase == Phase.BOSS:
		state.elapsed_seconds += delta
		_update_reward_effect_scale(delta)
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
	while _normal_wave_index < _normal_wave_progresses.size():
		var wave_progress: float = _normal_wave_progresses[_normal_wave_index]
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


# 成对生成一长一短的路程间隔后打乱，保证总路程与波次数不被随机改变。
func _build_normal_wave_progresses(timeline: EncounterTimeline) -> PackedFloat32Array:
	var progresses: PackedFloat32Array = PackedFloat32Array()
	if timeline == null or timeline.normal_wave_count < 1:
		return progresses
	var gap_count: int = timeline.normal_wave_count + 1
	var base_gap: float = 1.0 / float(gap_count)
	var jitter_ratio: float = clampf(timeline.normal_wave_interval_jitter_ratio, 0.0, 0.45)
	var gaps: Array[float] = []
	while gaps.size() + 1 < gap_count:
		var jitter: float = base_gap * _spawn_rng.randf_range(0.0, jitter_ratio)
		gaps.append(base_gap - jitter)
		gaps.append(base_gap + jitter)
	if gaps.size() < gap_count:
		gaps.append(base_gap)
	for index: int in range(gaps.size() - 1, 0, -1):
		var swap_index: int = _spawn_rng.randi_range(0, index)
		var swap_value: float = gaps[index]
		gaps[index] = gaps[swap_index]
		gaps[swap_index] = swap_value
	var cumulative_progress: float = 0.0
	for wave_index: int in range(timeline.normal_wave_count):
		cumulative_progress += gaps[wave_index]
		progresses.append(cumulative_progress)
	return progresses


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


func state_for_slot(player_slot: int) -> RunState:
	var context: PlayerRunContext = _player_contexts.get(player_slot)
	return context.state if context != null and context.state != null else state


func cart_for_slot(player_slot: int) -> Cart3D:
	var context: PlayerRunContext = _player_contexts.get(player_slot)
	return context.cart if context != null and context.cart != null else cart


func get_player_contexts() -> Array[PlayerRunContext]:
	var contexts: Array[PlayerRunContext] = []
	for player_slot: int in _player_contexts:
		contexts.append(_player_contexts[player_slot])
	contexts.sort_custom(func(a: PlayerRunContext, b: PlayerRunContext) -> bool:
		return a.slot < b.slot
	)
	return contexts


func output_multiplier_for_slot(player_slot: int) -> float:
	if not _network_active:
		return 1.0
	var context: PlayerRunContext = _player_contexts.get(player_slot)
	return context.output_multiplier(_ghost_damage_multiplier) if context != null else 1.0


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
	if customer == null:
		return false
	if _network_active and _network_session.is_client():
		return false
	if not _network_active:
		return cart != null and customer.collision_rect_xz().intersects(cart.collision_rect_xz())
	for context: PlayerRunContext in get_player_contexts():
		if context.is_ghost() or context.cart == null:
			continue
		if customer.collision_rect_xz().intersects(context.cart.collision_rect_xz()):
			return true
	return false


# 高压档或低帧率下一帧可能跨过餐车，使用前后包围矩形补足连续接触判定。
func customer_swept_collides_with_cart(customer: Customer3D, previous_z: float) -> bool:
	if customer == null:
		return false
	if _network_active and _network_session.is_client():
		return false
	var current_rect: Rect2 = customer.collision_rect_xz()
	var previous_rect: Rect2 = current_rect
	previous_rect.position.y += previous_z - customer.position.z
	if not _network_active:
		return cart != null and previous_rect.merge(current_rect).intersects(cart.collision_rect_xz())
	var swept_rect: Rect2 = previous_rect.merge(current_rect)
	for context: PlayerRunContext in get_player_contexts():
		if context.is_ghost() or context.cart == null:
			continue
		if swept_rect.intersects(context.cart.collision_rect_xz()):
			return true
	return false


func get_priority_target() -> Node3D:
	return _get_priority_target(null)


func get_priority_target_for_food(food: FoodData, player_slot: int = 1) -> Node3D:
	return _get_priority_target(food, player_slot)


func _get_priority_target(food: FoodData, player_slot: int = 1) -> Node3D:
	var source_cart: Cart3D = cart_for_slot(player_slot)
	if source_cart == null:
		return null
	var best_target: Node3D = null
	var best_forward: float = INF
	var best_horizontal: float = INF
	var best_spawn_index: int = 2147483647
	for customer: Customer3D in customers:
		if not is_instance_valid(customer) or not customer.active or customer.position.z >= source_cart.position.z:
			continue
		if not _target_is_allowed_for_food(food, logic_position(customer), source_cart):
			continue
		var forward: float = source_cart.position.z - customer.position.z
		var horizontal: float = absf(customer.position.x - source_cart.position.x)
		if _target_is_better(forward, horizontal, customer.spawn_index, best_forward, best_horizontal, best_spawn_index):
			best_target = customer
			best_forward = forward
			best_horizontal = horizontal
			best_spawn_index = customer.spawn_index
	for child: Node in gates.get_children():
		if not child is UpgradeGate3D or child.is_queued_for_deletion():
			continue
		var gate: UpgradeGate3D = child as UpgradeGate3D
		if gate.position.z >= source_cart.position.z:
			continue
		var gate_target: Node3D = gate.target_for_cart_x(source_cart.position.x)
		if gate_target == null:
			continue
		if not _target_is_allowed_for_food(food, logic_position(gate_target), source_cart):
			continue
		var gate_forward: float = source_cart.position.z - gate.position.z
		var gate_horizontal: float = absf(logic_position(gate_target).x - logic_position(source_cart).x)
		if _target_is_better(gate_forward, gate_horizontal, gate.spawn_index, best_forward, best_horizontal, best_spawn_index):
			best_target = gate_target
			best_forward = gate_forward
			best_horizontal = gate_horizontal
			best_spawn_index = gate.spawn_index
	for child: Node in drops.get_children():
		if not child is UpgradeDrop3D or child.is_queued_for_deletion():
			continue
		var reward_gate: UpgradeDrop3D = child as UpgradeDrop3D
		if reward_gate.position.z >= source_cart.position.z:
			continue
		var reward_target: Node3D = reward_gate.target_for_cart_x(
			source_cart.position.x,
			player_slot
		)
		if reward_target == null:
			continue
		if not _target_is_allowed_for_food(food, logic_position(reward_target), source_cart):
			continue
		var reward_forward: float = source_cart.position.z - reward_gate.position.z
		var reward_horizontal: float = absf(logic_position(reward_target).x - logic_position(source_cart).x)
		if _target_is_better(reward_forward, reward_horizontal, reward_gate.spawn_index, best_forward, best_horizontal, best_spawn_index):
			best_target = reward_target
			best_forward = reward_forward
			best_horizontal = reward_horizontal
			best_spawn_index = reward_gate.spawn_index
	if boss != null and is_instance_valid(boss) and boss.active:
		if not _target_is_allowed_for_food(food, logic_position(boss), source_cart):
			return best_target
		var boss_forward: float = source_cart.position.z - boss.position.z
		var boss_horizontal: float = absf(boss.position.x - source_cart.position.x)
		if _target_is_better(boss_forward, boss_horizontal, 2000000000, best_forward, best_horizontal, best_spawn_index):
			best_target = boss
	return best_target


# 食材可用武器表半角收窄前方寻敌扇区；边界目标计入候选。
func _target_is_allowed_for_food(
	food: FoodData,
	target_position: Vector3,
	source_cart: Cart3D = null
) -> bool:
	if food == null or food.targeting_half_angle_degrees >= 90.0:
		return true
	var aim_cart: Cart3D = source_cart if source_cart != null else cart
	var offset: Vector3 = target_position - logic_position(aim_cart)
	return (
		offset.z < -TARGET_FORWARD_EPSILON
		and absf(rad_to_deg(atan2(offset.x, -offset.z)))
		<= food.targeting_half_angle_degrees + TARGET_ANGLE_EPSILON_DEGREES
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
	giant_baguette: bool = false,
	player_slot: int = 1
) -> void:
	var projectile: FoodProjectile3D = PROJECTILE_SCENE.instantiate() as FoodProjectile3D
	projectiles.add_child(projectile)
	var source_state: RunState = state_for_slot(player_slot)
	var should_home: bool = (
		not giant_baguette
		and (
			food.initial_tracking_mode == FoodData.TrackingMode.HOMING
			or source_state.is_food_homing(food.id)
		)
	)
	var lifetime: float = (
		source_state.effective_duration(food) * source_state.baguette_giant_duration_multiplier
		if giant_baguette
		else source_state.effective_duration(food)
	)
	var hit_count: int = (
		source_state.baguette_giant_pierce_count
		if giant_baguette
		else source_state.effective_pierce_count(food)
	)
	var breathing_enabled: bool = (
		food.id == &"mushroom"
		and source_state.has_food_evolution(&"mushroom_breath")
	)
	var giant_range_scale: float = (
		source_state.effective_projectile_radius(food) / maxf(0.001, food.projectile_radius)
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
		Playfield.REGION_WIDTH * source_state.baguette_giant_width_regions * giant_range_scale if giant_baguette else 0.0,
		breathing_enabled,
		player_slot
	)
	if giant_baguette and is_instance_valid(background):
		background.shake_camera()


# 主机生成真实投射物并发送一次批量发射事件；客户端调用同一入口只重放视觉。
func spawn_projectile_burst(
	start_position: Vector3,
	burst: Array[Dictionary],
	food: FoodData,
	amount: float,
	speed: float,
	radius: float,
	target: Node3D,
	giant_baguette: bool,
	player_slot: int
) -> void:
	if food == null or burst.is_empty():
		return
	for record: Dictionary in burst:
		spawn_projectile(
			start_position,
			_vector_from_payload(record.get("direction", {}), Vector3.FORWARD),
			food,
			amount,
			speed,
			radius,
			target,
			float(record.get("orbit_phase", 0.0)),
			giant_baguette,
			player_slot
		)
	if not _network_active or not _network_session.is_host():
		return
	var descriptors: Array[Dictionary] = []
	for record: Dictionary in burst:
		descriptors.append(record.duplicate(true))
	_network_session.send_projectile_burst({
		"slot": player_slot,
		"food_id": str(food.id),
		"start": _vector_payload(start_position),
		"amount": amount,
		"speed": speed,
		"radius": radius,
		"giant": giant_baguette,
		"bursts": descriptors,
		"target": _network_target_reference(target),
	})


# 客户端重放房主发来的发射批次，并只复现命中表现，不写入权威数值或统计。
func replay_network_projectile_burst(payload: Dictionary) -> void:
	if not _network_active or not _network_session.is_client():
		return
	var source_slot: int = int(payload.get("slot", 0))
	if _player_contexts.get(source_slot) == null:
		return
	var food: FoodData = _food_data_for_id(StringName(str(payload.get("food_id", ""))))
	if food == null:
		return
	var target: Node3D = _resolve_network_target(payload.get("target", {}))
	var burst: Array[Dictionary] = []
	for record: Variant in payload.get("bursts", []):
		if record is Dictionary:
			burst.append(record as Dictionary)
	spawn_projectile_burst(
		_vector_from_payload(payload.get("start", {}), Vector3.ZERO),
		burst,
		food,
		float(payload.get("amount", 0.0)),
		float(payload.get("speed", 0.0)),
		float(payload.get("radius", 0.0)),
		target,
		bool(payload.get("giant", false)),
		source_slot
	)


func _network_target_reference(target: Node3D) -> Dictionary:
	if target is Customer3D:
		return {"kind": "customer", "index": (target as Customer3D).spawn_index}
	if target is UpgradeGate3D:
		return {"kind": "gate", "index": (target as UpgradeGate3D).spawn_index}
	if target is UpgradeDrop3D:
		return {"kind": "drop", "index": (target as UpgradeDrop3D).spawn_index}
	if target is PrototypeBoss3D:
		return {"kind": "boss"}
	return {}


func _resolve_network_target(reference_variant: Variant) -> Node3D:
	if not reference_variant is Dictionary:
		return null
	var reference: Dictionary = reference_variant as Dictionary
	match str(reference.get("kind", "")):
		"customer":
			return _find_customer_by_spawn_index(int(reference.get("index", 0)))
		"gate":
			return _find_gate_by_spawn_index(int(reference.get("index", 0)))
		"drop":
			return _find_drop_by_spawn_index(int(reference.get("index", 0)))
		"boss":
			return boss if boss != null and is_instance_valid(boss) else null
	return null


func _vector_payload(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


func _vector_from_payload(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if not value is Dictionary:
		return fallback
	var payload: Dictionary = value as Dictionary
	return Vector3(
		float(payload.get("x", fallback.x)),
		float(payload.get("y", fallback.y)),
		float(payload.get("z", fallback.z))
	)


# 蘑菇随餐车环绕不受位移风；巨型法棍只承受普通投射物四分之一风偏。
func _projectile_environment_velocity(food: FoodData, giant_baguette: bool) -> Vector3:
	if food == null or food.attack_kind in [
		FoodData.AttackKind.ORBITING_MUSHROOM,
		FoodData.AttackKind.CARROT_SWEEP,
	]:
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
	# 客户端保留同一套几何与穿透回收，避免远端子弹穿模；数值始终只由房主写入。
	var client_visual_only: bool = _network_active and _network_session.is_client()
	for customer: Customer3D in customers:
		if not is_instance_valid(customer) or not customer.active or not projectile.can_hit(customer):
			continue
		if projectile.overlaps_target(logic_position(customer), customer.hit_radius()):
			if client_visual_only:
				customer.play_hit_feedback()
			elif projectile.attack_kind == FoodData.AttackKind.EGG_PROJECTILE:
				_spawn_egg_puddle(projectile, customer)
			else:
				_apply_customer_satisfaction(
					customer,
					projectile.satisfaction,
					projectile.food_id,
					projectile.owner_slot
				)
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
			if client_visual_only:
				boss.play_hit_feedback()
			elif projectile.attack_kind == FoodData.AttackKind.EGG_PROJECTILE:
				_spawn_egg_puddle(projectile, boss)
			else:
				_apply_boss_satisfaction(
					boss,
					projectile.satisfaction,
					projectile.food_id,
					projectile.owner_slot
				)
			projectile.register_hit(boss)


# 鸡蛋命中任何可攻击目标时只生成蛋液；首跳由蛋液立即结算，鸡蛋本体不扣目标数值。
func _spawn_egg_puddle(projectile: FoodProjectile3D, target: Node3D) -> void:
	var source_food: FoodData = _food_data_for_id(projectile.food_id)
	var source_state: RunState = state_for_slot(projectile.owner_slot)
	var puddle_data: FoodData = egg_puddle_data
	if (
		source_food == null
		or puddle_data == null
		or target == null
		or not is_instance_valid(target)
	):
		return
	var puddle: FoodPuddle3D = EGG_PUDDLE_SCENE.instantiate() as FoodPuddle3D
	projectiles.add_child(puddle)
	var target_position: Vector3 = logic_position(target)
	var puddle_damage: float = MultiplayerRules.ghost_output(
		source_state.effective_derived_satisfaction(puddle_data, source_food),
		output_multiplier_for_slot(projectile.owner_slot)
	)
	var puddle_radius: float = Playfield.design_to_world(
		source_state.effective_projectile_radius(puddle_data)
	)
	var puddle_duration: float = source_state.effective_duration(puddle_data)
	var puddle_interval: float = source_state.effective_derived_interval(puddle_data, source_food)
	puddle.configure(
		self,
		Vector3(target_position.x, 0.03, target_position.z),
		source_food,
		puddle_data,
		puddle_damage,
		puddle_radius,
		puddle_duration,
		puddle_interval
	)
	puddle.owner_slot = projectile.owner_slot
	apply_puddle_damage(target, puddle.satisfaction, puddle.food_id, projectile.owner_slot)
	puddle.prime_target(target)
	if _network_active and _network_session.is_host():
		_network_session.send_game_event({
			"type": "egg_puddle_spawned",
			"data": {
				"owner_slot": projectile.owner_slot,
				"source_food_id": str(source_food.id),
				"derived_attack_id": str(puddle_data.id),
				"position": _vector_payload(puddle.position),
				"satisfaction": puddle_damage,
				"radius": puddle_radius,
				"duration": puddle_duration,
				"interval": puddle_interval,
			},
		})


# 客户端只恢复蛋液表现；FoodPuddle3D 的客户端命中入口不会写入任何权威数值。
func _spawn_network_egg_puddle(payload: Dictionary) -> void:
	if not _network_active or not _network_session.is_client():
		return
	var source_food: FoodData = _food_data_for_id(
		StringName(str(payload.get("source_food_id", "")))
	)
	var puddle_data: FoodData = egg_puddle_data
	if (
		source_food == null
		or puddle_data == null
		or StringName(str(payload.get("derived_attack_id", ""))) != puddle_data.id
	):
		return
	var puddle: FoodPuddle3D = EGG_PUDDLE_SCENE.instantiate() as FoodPuddle3D
	if puddle == null:
		return
	projectiles.add_child(puddle)
	puddle.configure(
		self,
		_vector_from_payload(payload.get("position", {}), Vector3.ZERO),
		source_food,
		puddle_data,
		float(payload.get("satisfaction", 0.0)),
		maxf(0.001, float(payload.get("radius", 0.001))),
		maxf(0.01, float(payload.get("duration", 0.01))),
		maxf(0.01, float(payload.get("interval", 0.01)))
	)
	puddle.owner_slot = maxi(1, int(payload.get("owner_slot", 1)))


func _apply_customer_satisfaction(
	customer: Customer3D,
	amount: float,
	food_id: StringName,
	player_slot: int = 1
) -> void:
	var applied: float = minf(amount, customer.remaining_appetite)
	customer.receive_satisfaction(amount)
	state_for_slot(player_slot).record_food_satisfaction(food_id, applied)


func _apply_boss_satisfaction(
	target_boss: PrototypeBoss3D,
	amount: float,
	food_id: StringName,
	player_slot: int = 1
) -> void:
	var applied: float = minf(amount, target_boss.remaining_appetite)
	target_boss.receive_satisfaction(amount)
	state_for_slot(player_slot).record_food_satisfaction(food_id, applied)


# 蛋液与普通投射物共用目标效果语义；门和奖励门通过父节点暴露自己的扣血接口。
func apply_puddle_damage(
	target: Node3D,
	amount: float,
	food_id: StringName,
	player_slot: int = 1
) -> void:
	if target == null or not is_instance_valid(target) or amount <= 0.0:
		return
	if target is Customer3D:
		var customer: Customer3D = target as Customer3D
		if customer.active:
			_apply_customer_satisfaction(customer, amount, food_id, player_slot)
		return
	if target is PrototypeBoss3D:
		var target_boss: PrototypeBoss3D = target as PrototypeBoss3D
		if target_boss.active:
			_apply_boss_satisfaction(target_boss, amount, food_id, player_slot)
		return
	var parent: Node = target.get_parent()
	if parent is UpgradeGate3D:
		(parent as UpgradeGate3D).receive_puddle_damage(target, amount)
	elif parent is UpgradeDrop3D:
		(parent as UpgradeDrop3D).receive_puddle_damage(target, amount)


func resolve_gate_projectile_hit(
	gate: UpgradeGate3D,
	hit_left: bool,
	target: Node3D,
	projectile: FoodProjectile3D
) -> void:
	if _network_active and _network_session.is_client():
		gate.play_hit_feedback(hit_left)
		return
	if projectile.attack_kind == FoodData.AttackKind.EGG_PROJECTILE:
		_spawn_egg_puddle(projectile, target)
	else:
		gate.receive_damage(hit_left, projectile.satisfaction)


func resolve_reward_projectile_hit(
	reward_gate: UpgradeDrop3D,
	target: Node3D,
	projectile: FoodProjectile3D
) -> void:
	if _network_active and _network_session.is_client():
		reward_gate.play_hit_feedback()
		return
	if projectile.attack_kind == FoodData.AttackKind.EGG_PROJECTILE:
		_spawn_egg_puddle(projectile, target)
	else:
		reward_gate.receive_damage(projectile.satisfaction)


func resolve_puddle_hits(puddle: FoodPuddle3D) -> void:
	if not is_instance_valid(puddle) or puddle.is_queued_for_deletion():
		return
	if _network_active and _network_session.is_client():
		return
	puddle.begin_contact_scan()
	for customer: Customer3D in customers:
		if (
			not is_instance_valid(customer)
			or not customer.active
			or not puddle.overlaps_target(logic_position(customer), customer.hit_radius())
		):
			continue
		if puddle.observe_target(customer):
			apply_puddle_damage(
				customer,
				puddle.satisfaction,
				puddle.food_id,
				puddle.owner_slot
			)
	for child: Node in gates.get_children():
		if child is UpgradeGate3D and not child.is_queued_for_deletion():
			(child as UpgradeGate3D).try_receive_puddle(puddle)
	for child: Node in drops.get_children():
		if child is UpgradeDrop3D and not child.is_queued_for_deletion():
			(child as UpgradeDrop3D).try_receive_puddle(puddle)
	if boss != null and is_instance_valid(boss) and boss.active:
		if puddle.overlaps_target(logic_position(boss), boss.hit_radius()):
			if puddle.observe_target(boss):
				apply_puddle_damage(
					boss,
					puddle.satisfaction,
					puddle.food_id,
					puddle.owner_slot
				)
	puddle.end_contact_scan()


# 生成适合重复网络传输的强化稳定引用，而不是复制整份 Resource 文案。
func _serialize_network_upgrade_ref(upgrade: UpgradeData) -> Dictionary:
	if upgrade == null:
		return {}
	return {
		"id": str(upgrade.id),
		"value": upgrade.value,
		"value_ratio": upgrade.value_ratio,
		"source_scale": upgrade.source_scale,
		"source_label": upgrade.source_label,
		"uses_value_range": upgrade.uses_value_range,
	}


func _serialize_start_options(options_by_slot: Dictionary[int, Array]) -> Dictionary:
	var payload: Dictionary = {}
	for player_slot: int in options_by_slot:
		var options: Array = []
		for option: UpgradeData in options_by_slot[player_slot]:
			options.append(_serialize_network_upgrade_ref(option))
		payload[str(player_slot)] = options
	return payload


# 用本地已加载模板还原强化；找不到模板时才回退到数值快照。
func _deserialize_network_upgrade_ref(payload: Variant) -> UpgradeData:
	if not payload is Dictionary:
		return null
	var data: Dictionary = payload as Dictionary
	var upgrade_id: StringName = StringName(str(data.get("id", "")))
	for template: UpgradeData in _normal_upgrade_pool:
		if template.id != upgrade_id:
			continue
		var upgrade: UpgradeData = template.duplicate(true) as UpgradeData
		upgrade.source_scale = maxf(0.0, float(data.get("source_scale", upgrade.source_scale)))
		upgrade.source_label = str(data.get("source_label", upgrade.source_label))
		upgrade.set_value_ratio(float(data.get("value_ratio", upgrade.value_ratio)))
		return upgrade
	var food: FoodData = _food_data_for_id(upgrade_id)
	if food != null:
		var food_option: UpgradeData = _make_start_food_option(food)
		food_option.source_scale = maxf(0.0, float(data.get("source_scale", 1.0)))
		food_option.source_label = str(data.get("source_label", ""))
		return food_option
	return _deserialize_network_upgrade(payload)


func _serialize_network_upgrade(upgrade: UpgradeData) -> Dictionary:
	if upgrade == null:
		return {}
	return {
		"id": str(upgrade.id),
		"display_name": upgrade.display_name,
		"kind": int(upgrade.kind),
		"value": upgrade.value,
		"value_suffix": upgrade.value_suffix,
		"effect_text_template": upgrade.effect_text_template,
		"minimum_value": upgrade.minimum_value,
		"maximum_value": upgrade.maximum_value,
		"value_ratio": upgrade.value_ratio,
		"uses_value_range": upgrade.uses_value_range,
		"source_scale": upgrade.source_scale,
		"source_label": upgrade.source_label,
		"rarity_name": upgrade.rarity_name,
		"rarity_color": upgrade.rarity_color.to_html(false),
	}


func _deserialize_network_upgrade(payload: Variant) -> UpgradeData:
	if not payload is Dictionary:
		return null
	var data: Dictionary = payload as Dictionary
	var upgrade: UpgradeData = UpgradeData.new()
	upgrade.id = StringName(str(data.get("id", "network_upgrade")))
	upgrade.display_name = str(data.get("display_name", "强化"))
	upgrade.kind = int(data.get("kind", UpgradeData.Kind.SUGAR))
	upgrade.value = float(data.get("value", 0.0))
	upgrade.value_suffix = str(data.get("value_suffix", "%"))
	upgrade.effect_text_template = str(data.get("effect_text_template", ""))
	upgrade.minimum_value = float(data.get("minimum_value", 0.0))
	upgrade.maximum_value = float(data.get("maximum_value", 0.0))
	upgrade.value_ratio = clampf(float(data.get("value_ratio", 0.0)), 0.0, 1.0)
	upgrade.uses_value_range = bool(data.get("uses_value_range", false))
	upgrade.source_scale = maxf(0.0, float(data.get("source_scale", 1.0)))
	upgrade.source_label = str(data.get("source_label", ""))
	upgrade.rarity_name = str(data.get("rarity_name", "寻常"))
	var rarity_color_text: String = str(data.get("rarity_color", "d7c59a"))
	if not rarity_color_text.begins_with("#"):
		rarity_color_text = "#" + rarity_color_text
	upgrade.rarity_color = Color(rarity_color_text)
	return upgrade


func _apply_upgrade_for_player(
	player_slot: int,
	upgrade: UpgradeData,
	count_as_gate: bool,
	was_ghost: bool,
	show_feedback: bool = true
) -> bool:
	var context: PlayerRunContext = _player_contexts.get(player_slot)
	if context == null or upgrade == null:
		return false
	var repair_points: float = (
		context.state.maximum_durability * upgrade.value
		if upgrade.kind == UpgradeData.Kind.REPAIR
		else 0.0
	)
	context.state.apply_upgrade(upgrade, count_as_gate, not was_ghost)
	if was_ghost and upgrade.kind == UpgradeData.Kind.REPAIR:
		context.cache_repair(repair_points)
	if show_feedback and (player_slot == _network_session.local_slot or not _network_active):
		context.cart.play_upgrade_feedback(upgrade.rarity_color)
		hud.show_toast(
			"%s：%s\n%s" % [
				upgrade.display_name,
				upgrade.effect_text(context.state.maximum_durability),
				_cumulative_upgrade_text(upgrade.kind, context.state),
			],
			upgrade.rarity_color
		)
	return true


func on_gate_selected(
	upgrade: UpgradeData,
	start_food_gate: bool,
	remaining_base_health: float = 0.0
) -> void:
	on_gate_selected_for_player(1, upgrade, start_food_gate, remaining_base_health)


func on_gate_selected_for_player(
	player_slot: int,
	upgrade: UpgradeData,
	start_food_gate: bool,
	remaining_base_health: float = 0.0
) -> void:
	var context: PlayerRunContext = _player_contexts.get(player_slot)
	if context == null:
		return
	if _network_active and not _network_session.is_host():
		return
	if start_food_gate:
		if upgrade == null:
			push_error("START_FOOD_SELECTION_MISSING")
			return
		var selected_food: FoodData = _food_data_for_id(upgrade.id)
		if selected_food == null:
			push_error("START_FOOD_NOT_UNLOCKED food=%s" % str(upgrade.id))
			return
		context.weapon_controller.add_food(selected_food)
		if _network_active:
			_network_session.send_game_event({
				"type": "player_food_added",
				"slot": player_slot,
				"food_id": str(selected_food.id),
			})
		if player_slot == _network_session.local_slot or not _network_active:
			hud.show_toast("%s装车！自动寻找最近的食客" % selected_food.display_name)
		return
	if upgrade == null:
		return
	var was_ghost: bool = context.is_ghost()
	if not _apply_upgrade_for_player(player_slot, upgrade, true, was_ghost):
		return
	if _network_active:
		_network_session.send_game_event({
			"type": "upgrade_applied",
			"slot": player_slot,
			"count_as_gate": true,
			"was_ghost": was_ghost,
			"upgrade": _serialize_network_upgrade(upgrade),
		})
	if remaining_base_health > 0.0:
		damage_cart(remaining_base_health, "撞门", player_slot)


func on_customer_reward_gate_collected(upgrade: UpgradeData) -> void:
	on_customer_reward_gate_collected_for_player(1, upgrade)


func on_customer_reward_gate_collected_for_player(
	player_slot: int,
	upgrade: UpgradeData
) -> void:
	var context: PlayerRunContext = _player_contexts.get(player_slot)
	if context == null or upgrade == null:
		return
	if _network_active and not _network_session.is_host():
		return
	var was_ghost: bool = context.is_ghost()
	if not _apply_upgrade_for_player(player_slot, upgrade, false, was_ghost):
		return
	if _network_active:
		_network_session.send_game_event({
			"type": "upgrade_applied",
			"slot": player_slot,
			"count_as_gate": false,
			"was_ghost": was_ghost,
			"upgrade": _serialize_network_upgrade(upgrade),
		})


# 物理强化按已拥有食材显示实际倍率，避免把门牌原始百分比误读为线性终值。
func _cumulative_upgrade_text(kind: UpgradeData.Kind, source_state: RunState = null) -> String:
	var display_state: RunState = source_state if source_state != null else state
	if kind not in [
		UpgradeData.Kind.WINE,
		UpgradeData.Kind.SCALLION,
		UpgradeData.Kind.STARCH,
	]:
		if kind == UpgradeData.Kind.LIGHT_CART:
			var bonus: float = display_state.effective_cart_speed_bonus(Cart3D.BASE_MOVE_SPEED_DESIGN)
			return "实际横移加值 +%.0f · 基础保留 %.0f%%" % [
				bonus,
				display_state.cart_base_speed_factor * 100.0,
			]
		return display_state.cumulative_effect_text(kind)
	var texts: PackedStringArray = []
	for food_id: StringName in display_state.foods:
		var food: FoodData = _food_data_for_id(food_id)
		if food == null:
			continue
		var multiplier: float = 1.0
		match kind:
			UpgradeData.Kind.WINE:
				if food.attack_kind == FoodData.AttackKind.ORBITING_MUSHROOM:
					multiplier = display_state.effective_orbit_angular_speed(food) / food.orbit_angular_speed
				else:
					multiplier = display_state.effective_projectile_speed(food) / food.projectile_speed
			UpgradeData.Kind.SCALLION:
				multiplier = display_state.effective_projectile_radius(food) / food.projectile_radius
			UpgradeData.Kind.STARCH:
				multiplier = display_state.effective_duration(food) / food.base_lifetime
		texts.append("%s×%.2f" % [food.display_name, multiplier])
	return "实际：%s" % (" · ".join(texts) if not texts.is_empty() else "待装车后生效")


func damage_cart(amount: float, source: String, player_slot: int = 1) -> void:
	if _network_active:
		if not _network_session.is_host():
			return
		_apply_network_damage_batch({player_slot: amount}, source)
		return
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


func damage_carts(damages: Dictionary[int, float], source: String) -> void:
	if not _network_active:
		if damages.has(1):
			damage_cart(float(damages[1]), source)
		return
	if not _network_session.is_host():
		return
	_apply_network_damage_batch(damages, source)


func _apply_network_damage_batch(damages: Dictionary[int, float], source: String) -> void:
	if _debug_invincible:
		return
	var newly_dead: Array[int] = []
	for player_slot: int in damages:
		var context: PlayerRunContext = _player_contexts.get(player_slot)
		if context == null or not context.can_receive_damage():
			continue
		var applied: bool = context.cart.take_damage(
			maxf(0.0, float(damages[player_slot])),
			false
		)
		if not applied:
			continue
		if context.state.current_durability <= 0.0:
			newly_dead.append(player_slot)
		if player_slot == _network_session.local_slot:
			hud.show_toast("%s：耐久受到影响" % source, Color("#ff7858"))
	if newly_dead.is_empty():
		return
	var respawn_seconds: float = MultiplayerRules.respawn_delay(
		_respawn_base_seconds,
		_respawn_increment_seconds,
		_respawn_max_seconds,
		_team_death_count
	)
	for player_slot: int in newly_dead:
		var context: PlayerRunContext = _player_contexts[player_slot]
		context.enter_ghost(respawn_seconds)
	_team_death_count += newly_dead.size()
	if _all_network_players_ghost():
		_on_cart_destroyed()
	else:
		_broadcast_player_snapshot()


func _all_network_players_ghost() -> bool:
	var life_states: Array[bool] = []
	for context: PlayerRunContext in _player_contexts.values():
		life_states.append(context.is_ghost())
	return MultiplayerRules.all_players_ghost(life_states)


func _tick_network_lives(delta: float) -> void:
	if not _network_active or not _network_session.is_host():
		return
	var respawned: Array[int] = []
	for player_slot: int in _player_contexts:
		var context: PlayerRunContext = _player_contexts[player_slot]
		if context.tick_respawn(delta):
			context.respawn(_respawn_durability_ratio, _respawn_invincibility_seconds)
			respawned.append(player_slot)
	if not respawned.is_empty():
		_broadcast_player_snapshot()


func _on_timeline_event(event_id: StringName) -> void:
	if _network_active and _network_session.is_client():
		return
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
	elif str(event_id).begins_with("gate_"):
		var gate_index: int = str(event_id).trim_prefix("gate_").to_int()
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
	var candidate_z: float = Playfield.FORWARD_SPAWN_Z
	var speed_multiplier: float = forward_speed_multiplier()
	var candidate_speed: float = FORWARD_GATE_SPEED * speed_multiplier
	var candidate_is_customer: bool = false
	if request.kind == ForwardSpawnRequest.Kind.CUSTOMER:
		if request.customer_data == null:
			return false
		candidate_z = Playfield.FORWARD_SPAWN_Z
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
	if candidate_is_customer:
		var safe_regions: Array[int] = _find_safe_customer_first_regions(
			request.customer_data,
			candidate_z,
			candidate_speed
		)
		request.spawn_first_region = _choose_spawn_first_region(safe_regions)
		if request.spawn_first_region < 0:
			return false
	return true


# 收集整条接近路径都不会追尾的合法路线，再交给种子随机选择。
func _find_safe_customer_first_regions(
	customer_data: CustomerData,
	candidate_z: float,
	candidate_speed: float
) -> Array[int]:
	var safe_regions: Array[int] = []
	var occupied_regions: int = customer_data.occupied_regions
	var max_start: int = Playfield.REGION_COUNT - occupied_regions
	var candidate_width: float = maxf(
		0.82,
		float(occupied_regions) * Playfield.REGION_WIDTH - 0.18
	)
	for first_region: int in range(max_start + 1):
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
			safe_regions.append(first_region)
	return safe_regions


# 只在请求确定能立即生成时消耗随机数，使同种子不受帧率与等待帧数影响。
func _choose_spawn_first_region(safe_regions: Array[int]) -> int:
	if safe_regions.is_empty():
		return -1
	return safe_regions[_spawn_rng.randi_range(0, safe_regions.size() - 1)]


func _spawn_customer_now(
	customer_data: CustomerData,
	scheduled_baseline_appetite: float = 0.0,
	spawn_first_region: int = -1
) -> void:
	state.normal_customers_spawned += 1
	_spawn_counter += 1
	var max_start: int = Playfield.REGION_COUNT - customer_data.occupied_regions
	var first_region: int = spawn_first_region
	if first_region < 0:
		first_region = _spawn_rng.randi_range(0, max_start)
	var spawn_position: Vector3 = Vector3(
		playfield.spawn_x(first_region, customer_data.occupied_regions),
		0.0,
		Playfield.FORWARD_SPAWN_Z
	)
	var baseline_appetite: float = scheduled_baseline_appetite
	if baseline_appetite <= 0.0:
		baseline_appetite = _current_baseline_appetite()
	var reward_upgrade: UpgradeData = _roll_customer_reward()
	var appetite: float = customer_data.appetite_at(
		baseline_appetite,
		reward_upgrade.value_ratio,
		reward_upgrade.source_scale
	)
	if _network_active:
		appetite = MultiplayerRules.scale_enemy_appetite(appetite, _network_player_count)
	var payload: Dictionary = {
		"data_id": str(customer_data.id),
		"spawn_index": _spawn_counter,
		"x": spawn_position.x,
		"z": spawn_position.z,
		"appetite": appetite,
		"baseline_appetite": baseline_appetite,
		"reward_upgrade_ref": _serialize_network_upgrade_ref(reward_upgrade),
	}
	if _network_active and _network_session.is_host() and customer_spawner != null:
		var spawned_customer: Customer3D = customer_spawner.spawn(payload) as Customer3D
		if spawned_customer != null:
			return
	var customer: Customer3D = _instantiate_customer(customer_data)
	if customer == null:
		return
	customer.position = spawn_position
	entities.add_child(customer)
	customer.configure(customer_data, self, _spawn_counter, appetite, reward_upgrade, baseline_appetite)
	customer.satisfied.connect(_on_customer_satisfied)
	customer.collided_with_cart.connect(_on_customer_collided_with_cart)
	customer.escaped.connect(_on_customer_escaped)
	customer.ranged_attack.connect(_on_customer_ranged_attack)
	_track_customer(customer)


func _spawn_elite_now() -> void:
	_begin_reward_effect_scale_transition()
	_elite_started_at = state.elapsed_seconds
	_spawn_counter += 1
	var baseline_appetite: float = _current_baseline_appetite()
	var appetite: float = elite_guest_data.appetite_at(baseline_appetite)
	if _network_active:
		appetite = MultiplayerRules.scale_enemy_appetite(appetite, _network_player_count)
	var payload: Dictionary = {
		"data_id": str(elite_guest_data.id),
		"spawn_index": _spawn_counter,
		"x": 3.6,
		"z": Playfield.FORWARD_SPAWN_Z,
		"appetite": appetite,
		"baseline_appetite": baseline_appetite,
		"reward_upgrade_ref": {},
	}
	if _network_active and _network_session.is_host() and customer_spawner != null:
		var spawned_elite: Customer3D = customer_spawner.spawn(payload) as Customer3D
		if spawned_elite == null:
			push_error("NETWORK_ELITE_SPAWN_FAILED")
		else:
			hud.set_phase("精英检查 · 六区无法绕行")
			hud.show_toast("六席贵客挡住整条路，尽快满足它！", Color("#f0c45f"))
			return
	var elite: Customer3D = _instantiate_customer(elite_guest_data)
	if elite == null:
		return
	elite.position = Vector3(3.6, 0.0, Playfield.FORWARD_SPAWN_Z)
	entities.add_child(elite)
	elite.configure(elite_guest_data, self, _spawn_counter, appetite)
	elite.satisfied.connect(_on_customer_satisfied)
	elite.collided_with_cart.connect(_on_customer_collided_with_cart)
	elite.escaped.connect(_on_customer_escaped)
	elite.ranged_attack.connect(_on_customer_ranged_attack)
	_track_customer(elite)
	hud.set_phase("精英检查 · 六区无法绕行")
	hud.show_toast("六席贵客挡住整条路，尽快满足它！", Color("#f0c45f"))


# 新精英出现后只改变后续奖励的目标缩放；已生成对象保留生成时快照。
func _begin_reward_effect_scale_transition() -> void:
	_elites_spawned += 1
	if _reward_effect_scale_after_elite.is_empty():
		return
	var target_index: int = mini(
		_elites_spawned - 1,
		_reward_effect_scale_after_elite.size() - 1
	)
	_reward_effect_scale_transition_start = _reward_effect_scale
	_reward_effect_scale_transition_target = clampf(
		_reward_effect_scale_after_elite[target_index],
		0.0,
		1.0
	)
	_reward_effect_scale_transition_elapsed = 0.0


# 按有效游戏时间平滑推进奖励缩放，选择阶段暂停时不会偷偷消耗过渡时间。
func _update_reward_effect_scale(delta: float) -> void:
	if delta <= 0.0:
		return
	var transition_duration: float = maxf(0.001, _reward_effect_scale_transition_seconds)
	if (
		is_equal_approx(
			_reward_effect_scale_transition_start,
			_reward_effect_scale_transition_target
		)
		or _reward_effect_scale_transition_elapsed >= transition_duration
	):
		_reward_effect_scale = _reward_effect_scale_transition_target
		return
	_reward_effect_scale_transition_elapsed = minf(
		transition_duration,
		_reward_effect_scale_transition_elapsed + delta
	)
	var ratio: float = clampf(
		_reward_effect_scale_transition_elapsed / transition_duration,
		0.0,
		1.0
	)
	# Smoothstep让精英节点后的变化在起止两端都逐渐收敛，避免奖励数值跳变。
	var eased_ratio: float = ratio * ratio * (3.0 - 2.0 * ratio)
	_reward_effect_scale = lerpf(
		_reward_effect_scale_transition_start,
		_reward_effect_scale_transition_target,
		eased_ratio
	)


# 重开一局时恢复初始缩放和精英阶段，避免上一局的目标值泄漏到新局。
func _reset_reward_effect_scale() -> void:
	_reward_effect_scale = clampf(_reward_effect_scale_initial, 0.0, 1.0)
	_reward_effect_scale_transition_start = _reward_effect_scale
	_reward_effect_scale_transition_target = _reward_effect_scale
	_reward_effect_scale_transition_elapsed = 0.0
	_elites_spawned = 0


# 食客数据只选择完整预制场景；错误或缺失配置回退到通用纸片场景。
func _instantiate_customer(customer_data: CustomerData) -> Customer3D:
	var packed_scene: PackedScene = customer_data.customer_scene
	if packed_scene == null:
		packed_scene = DEFAULT_CUSTOMER_SCENE
	var customer: Customer3D = packed_scene.instantiate() as Customer3D
	if customer != null:
		return customer
	push_error("食客场景根节点必须继承 Customer3D: %s" % str(customer_data.id))
	return DEFAULT_CUSTOMER_SCENE.instantiate() as Customer3D


func _spawn_gate_now(_index: int, is_start_gate: bool, scheduled_baseline_appetite: float = 0.0) -> void:
	_spawn_counter += 1
	if is_start_gate:
		var start_options: Array[UpgradeData] = _roll_start_food_options(1)
		if start_options.size() != 2:
			push_error("START_FOOD_POOL_EMPTY")
			return
		var per_player_start_options: Dictionary[int, Array] = {1: start_options}
		if _network_active:
			for context: PlayerRunContext in get_player_contexts():
				if context.slot == 1:
					continue
				var player_options: Array[UpgradeData] = _roll_start_food_options(context.slot)
				if player_options.size() == 2:
					per_player_start_options[context.slot] = player_options
		var start_payload: Dictionary = {
			"left_upgrade_ref": _serialize_network_upgrade_ref(start_options[0]),
			"right_upgrade_ref": _serialize_network_upgrade_ref(start_options[1]),
			"start_food_gate": true,
			"baseline_appetite": _current_baseline_appetite(),
			"spawn_index": _spawn_counter,
			"start_options_by_slot": _serialize_start_options(per_player_start_options),
			"display_maximum_durability": state.maximum_durability,
		}
		if _network_active and _network_session.is_host() and gate_spawner != null:
			var spawned_start_gate: UpgradeGate3D = gate_spawner.spawn(start_payload) as UpgradeGate3D
			if spawned_start_gate == null:
				push_error("NETWORK_START_GATE_SPAWN_FAILED")
			return
		var start_gate: UpgradeGate3D = GATE_SCENE.instantiate() as UpgradeGate3D
		if start_gate == null:
			return
		gates.add_child(start_gate)
		start_gate.configure(
			self,
			start_options[0],
			start_options[1],
			true,
			_current_baseline_appetite(),
			_spawn_counter,
			per_player_start_options,
			state.maximum_durability
		)
		return
	var baseline_appetite: float = scheduled_baseline_appetite
	if baseline_appetite <= 0.0:
		baseline_appetite = _current_baseline_appetite()
	var options: Array[UpgradeData] = _roll_normal_upgrade_options(2)
	if options.size() != 2:
		push_error("NORMAL_UPGRADE_POOL_TOO_SMALL")
		return
	state.record_normal_upgrade_offer(options)
	var normal_payload: Dictionary = {
		"left_upgrade_ref": _serialize_network_upgrade_ref(options[0]),
		"right_upgrade_ref": _serialize_network_upgrade_ref(options[1]),
		"start_food_gate": false,
		"baseline_appetite": baseline_appetite,
		"spawn_index": _spawn_counter,
		"start_options_by_slot": {},
		"display_maximum_durability": state.maximum_durability,
	}
	if _network_active and _network_session.is_host() and gate_spawner != null:
		var spawned_gate: UpgradeGate3D = gate_spawner.spawn(normal_payload) as UpgradeGate3D
		if spawned_gate == null:
			push_error("NETWORK_GATE_SPAWN_FAILED")
		return
	var gate: UpgradeGate3D = GATE_SCENE.instantiate() as UpgradeGate3D
	if gate == null:
		return
	gates.add_child(gate)
	gate.configure(
		self,
		options[0],
		options[1],
		false,
		baseline_appetite,
		_spawn_counter,
		{},
		state.maximum_durability
	)


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
	_network_announced_boss = false
	_bosses_started += 1
	phase = Phase.BOSS
	background.scrolling = false
	_clear_forward_objects()
	_boss_started_at = state.elapsed_seconds
	var boss_payload: Dictionary = {
		"baseline_appetite": _current_baseline_appetite(),
		"player_count": _network_player_count if _network_active else 1,
	}
	if _network_active and _network_session.is_host() and boss_spawner != null:
		boss = boss_spawner.spawn(boss_payload) as PrototypeBoss3D
	else:
		boss = BOSS_SCENE.instantiate() as PrototypeBoss3D
		if boss != null:
			entities.add_child(boss)
			boss.configure(
				boss_data,
				self,
				_current_baseline_appetite(),
				_network_player_count if _network_active else 1
			)
			boss.satisfied.connect(_on_boss_satisfied)
	if boss == null:
		push_error("NETWORK_BOSS_SPAWN_FAILED")
		return
	cart.begin_boss_movement(boss)
	for context: PlayerRunContext in get_player_contexts():
		if context.cart != cart:
			context.cart.begin_boss_movement(boss)
	hud.set_phase("Boss服务 · 自由移动并自动反击")
	hud.show_toast("前进停止！危险预警后会出现反击窗口", Color("#ff7957"))


func _on_customer_satisfied(customer: Customer3D) -> void:
	if _network_active and not _network_session.is_host():
		return
	_finish_customer(customer, false)


func _on_customer_collided_with_cart(customer: Customer3D) -> void:
	if _network_active and not _network_session.is_host():
		return
	var remaining: float = customer.remaining_appetite
	if _network_active:
		var damages: Dictionary[int, float] = {}
		var per_player_damage: float = MultiplayerRules.per_player_damage(
			remaining,
			_network_player_count
		)
		for context: PlayerRunContext in get_player_contexts():
			if context.is_ghost() or context.cart == null:
				continue
			if customer.collision_rect_xz().intersects(context.cart.collision_rect_xz()):
				damages[context.slot] = per_player_damage
		damage_carts(damages, "漏客投诉")
	else:
		damage_cart(remaining, "漏客投诉")
	_finish_customer(customer, true)


# 绕开餐车的食客只离开模拟，不产生伤害、击败或掉落。
func _on_customer_escaped(customer: Customer3D) -> void:
	if _network_active and not _network_session.is_host():
		return
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
	start_position.z = safe_z
	var payload: Dictionary = {
		"upgrade_ref": _serialize_network_upgrade_ref(upgrade),
		"x": start_position.x,
		"z": start_position.z,
		"baseline_appetite": baseline_appetite,
		"occupied_regions": occupied_regions,
		"spawn_index": _spawn_counter,
		"display_maximum_durability": state.maximum_durability,
	}
	if _network_active and _network_session.is_host() and drop_spawner != null:
		var spawned_drop: UpgradeDrop3D = drop_spawner.spawn(payload) as UpgradeDrop3D
		if spawned_drop != null:
			return
		push_error("NETWORK_REWARD_GATE_SPAWN_FAILED")
	var drop: UpgradeDrop3D = REWARD_GATE_SCENE.instantiate() as UpgradeDrop3D
	if drop == null:
		return
	drops.add_child(drop)
	drop.configure(
		self,
		upgrade,
		start_position,
		baseline_appetite,
		occupied_regions,
		_spawn_counter,
		state.maximum_durability
	)


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
	if not _network_active:
		damage_cart(amount, "拍桌投诉")
		return
	if not _network_session.is_host():
		return
	var candidates: Array[PlayerRunContext] = []
	for context: PlayerRunContext in get_player_contexts():
		if context.can_receive_damage():
			candidates.append(context)
	if candidates.is_empty():
		return
	var target: PlayerRunContext = candidates[_target_rng.randi_range(0, candidates.size() - 1)]
	damage_cart(
		MultiplayerRules.per_player_damage(amount, _network_player_count),
		"拍桌投诉",
		target.slot
	)


func select_boss_target_position(boss_position: Vector3) -> Vector3:
	if _network_active and not _network_session.is_host():
		return cart.position
	var candidates: Array[PlayerRunContext] = []
	for context: PlayerRunContext in get_player_contexts():
		if context.can_receive_damage():
			candidates.append(context)
	if candidates.is_empty():
		return cart.position
	var selected: PlayerRunContext = candidates[_target_rng.randi_range(0, candidates.size() - 1)]
	return selected.cart.position


func resolve_boss_attack(
	base_damage: float,
	locked_target_position: Vector3,
	area_attack: bool,
	source: String
) -> void:
	if not _network_active:
		var hit: bool = (
			PrototypeBoss3D.area_attack_hits(cart.position, locked_target_position)
			if area_attack
			else PrototypeBoss3D.line_attack_hits(cart.position, boss.position, locked_target_position)
		)
		if hit:
			damage_cart(base_damage, source)
		return
	var damages: Dictionary[int, float] = {}
	var per_player_damage: float = MultiplayerRules.per_player_damage(
		base_damage,
		_network_player_count
	)
	for context: PlayerRunContext in get_player_contexts():
		if not context.can_receive_damage():
			continue
		var hit: bool = (
			PrototypeBoss3D.area_attack_hits(context.cart.position, locked_target_position)
			if area_attack
			else PrototypeBoss3D.line_attack_hits(context.cart.position, boss.position, locked_target_position)
		)
		if hit:
			damages[context.slot] = per_player_damage
	damage_carts(damages, source)


func _on_special_choice_selected(choice_id: StringName) -> void:
	if _network_active:
		if _network_session.is_host():
			_on_network_choice_received(1, choice_id)
		else:
			_network_session.submit_choice(choice_id)
		return
	if not _active_special_choices.has(choice_id):
		push_error("SPECIAL_CHOICE_REJECTED choice=%s" % str(choice_id))
		return
	var upgrade: SpecialUpgradeData = _special_upgrades_by_id.get(choice_id)
	if upgrade == null:
		push_error("SPECIAL_CHOICE_DATA_MISSING choice=%s" % str(choice_id))
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
	_finish_special_choice_phase()


func _on_network_choice_received(player_slot: int, choice_id: StringName) -> void:
	if not _network_active or not _network_session.is_host():
		return
	var choices: Array = _active_special_choices_by_slot.get(player_slot, [])
	if not choices.has(str(choice_id)) and not choices.has(choice_id):
		push_error("SPECIAL_CHOICE_REJECTED slot=%d choice=%s" % [player_slot, str(choice_id)])
		return
	if _selected_special_choices_by_slot.has(player_slot):
		return
	var normalized_choice: StringName = StringName(choice_id)
	_selected_special_choices_by_slot[player_slot] = normalized_choice
	_apply_special_choice_for_player(player_slot, normalized_choice)
	_network_session.send_game_event({
		"type": "special_choice_applied",
		"slot": player_slot,
		"choice": str(normalized_choice),
	})
	if _selected_special_choices_by_slot.size() >= _player_contexts.size():
		_finish_special_choice_phase()


func _on_boss_satisfied() -> void:
	if _network_active and not _network_session.is_host():
		return
	state.boss_duration = state.elapsed_seconds - _boss_started_at
	state.boss_durations.append(state.boss_duration)
	_bosses_completed += 1
	state.customers_satisfied += 1
	for context: PlayerRunContext in get_player_contexts():
		context.cart.end_boss_movement()
	if _bosses_completed >= 2:
		if boss != null and is_instance_valid(boss):
			boss.queue_free()
		_finish_run()
		return
	phase = Phase.CHOICE
	_boss_reward_pending = true
	hud.set_phase("Boss赏赐 · 特别三选一")
	hud.show_toast("Boss满意离场！选择本局特别强化", Color("#f0c45f"))
	_show_special_choices(&"boss", "Boss满意了！选择特别强化")


func _show_special_choices(source: StringName, title: String) -> void:
	_special_choice_source = source
	if _network_active and _network_session.is_host():
		_active_special_choices_by_slot.clear()
		_selected_special_choices_by_slot.clear()
		for context: PlayerRunContext in get_player_contexts():
			var player_choices: Array[StringName] = _roll_special_choices(context.state, context.slot)
			_active_special_choices_by_slot[context.slot] = _string_name_array_to_strings(player_choices)
			context.state.record_special_offer(source, player_choices)
		var payload_choices: Dictionary = {}
		for player_slot: int in _active_special_choices_by_slot:
			payload_choices[str(player_slot)] = _active_special_choices_by_slot[player_slot]
		_network_session.send_game_event({
			"type": "special_choices",
			"choices": payload_choices,
			"source": str(source),
			"title": title,
			"boss_reward": _boss_reward_pending,
		})
		_active_special_choices.clear()
		for choice_text: String in _active_special_choices_by_slot.get(1, []):
			_active_special_choices.append(StringName(choice_text))
		hud.show_special_choices(_active_special_choices, _special_choice_texts(_active_special_choices), title)
		if _smoke_test:
			_on_network_choice_received(1, _active_special_choices[0])
		else:
			get_tree().paused = true
		return
	_active_special_choices = _roll_special_choices(state, 1)
	if _active_special_choices.size() != 3:
		push_error(
			"SPECIAL_CHOICE_POOL_INVALID source=%s count=%d" % [
				str(source),
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


func _apply_special_choice_for_player(player_slot: int, choice_id: StringName) -> void:
	var context: PlayerRunContext = _player_contexts.get(player_slot)
	if context == null:
		return
	var upgrade: SpecialUpgradeData = _special_upgrades_by_id.get(choice_id)
	if upgrade == null:
		return
	context.state.record_special_choice(choice_id)
	match upgrade.effect_kind:
		SpecialUpgradeData.EffectKind.FOOD_CARD:
			_apply_food_card_for_player(player_slot, _food_data_for_id(upgrade.target_id))
		SpecialUpgradeData.EffectKind.SERVING:
			context.state.servings += maxi(1, roundi(upgrade.effect_value))
			context.state.add_special(choice_id)
		SpecialUpgradeData.EffectKind.TARGET_AIM:
			context.state.enable_target_aim(upgrade.target_id)
			context.state.add_special(choice_id)
		SpecialUpgradeData.EffectKind.EVOLUTION:
			context.state.enable_food_evolution(choice_id)
			context.state.add_special(choice_id)
		SpecialUpgradeData.EffectKind.PIERCE:
			context.state.add_pierce_bonus(maxi(1, roundi(upgrade.effect_value)))
			context.state.add_special(choice_id)


func _finish_special_choice_phase() -> void:
	if _network_active and _network_session.is_host():
		_network_session.send_game_event({"type": "special_choices_complete"})
	get_tree().paused = false
	_active_special_choices.clear()
	_active_special_choices_by_slot.clear()
	_selected_special_choices_by_slot.clear()
	hud.hide_special_choices()
	if _boss_reward_pending:
		_boss_reward_pending = false
		if (
			boss != null
			and is_instance_valid(boss)
			and (not _native_network_spawning_enabled() or _network_session.is_host())
		):
			boss.queue_free()
	phase = Phase.FORWARD
	_normal_waves_suspended = false
	background.scrolling = true
	hud.set_phase("继续前进 · 构筑已变化")


func _apply_food_card(food: FoodData) -> void:
	_apply_food_card_for_player(1, food)


func _apply_food_card_for_player(player_slot: int, food: FoodData) -> void:
	if food == null:
		return
	var context: PlayerRunContext = _player_contexts.get(player_slot)
	if context == null:
		return
	if context.state.has_food(food.id):
		var next_level: int = context.state.level_food(food.id)
		context.state.add_special(StringName("%s_level_%d" % [str(food.id), next_level]))
		if player_slot == _network_session.local_slot or not _network_active:
			hud.show_toast(
			"%s升至 Lv.%d：自身基础满足值 ×%.2f" % [
				food.display_name,
				next_level,
				context.state.food_level_satisfaction_multiplier,
			]
			)
		return
	context.weapon_controller.add_food(food)
	context.state.add_special(StringName("%s_acquired" % str(food.id)))
	if player_slot == _network_session.local_slot or not _network_active:
		hud.show_toast("获得%s：加入自动投喂构筑" % food.display_name)


func _finish_run() -> void:
	if phase == Phase.RESULTS:
		return
	if _network_active and not _network_session.is_host():
		return
	phase = Phase.RESULTS
	if _network_active and _network_session.is_host():
		_broadcast_final_player_stats()
		_network_session.send_game_event({"type": "match_completed"})
		_network_session.return_to_lobby()
	var unlock_message: String = _record_final_boss_unlock()
	_save_playtest_record(&"completed")
	hud.set_phase("构筑验证完成")
	hud.show_results(
		"最终Boss满意离场，八分钟服务完成！",
		"%s\n\n%s" % [unlock_message, _build_results_text()]
	)
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
		if state.special_choice_records.size() != 7:
			push_error(
				"SMOKE_TEST_FAILED special_choices=%d expected=7"
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


# 首胜状态保存失败只影响持久化提示，不阻断本局完成与结算。
func _record_final_boss_unlock() -> String:
	var unlock_result: int = ProgressionStore.record_final_boss_first_clear()
	match unlock_result:
		ProgressionStore.UnlockResult.UNLOCKED_NOW:
			_final_boss_unlock_status = &"unlocked_now"
			return "首次通关：后续内容已标记为解锁（具体内容待后续接入）。"
		ProgressionStore.UnlockResult.ALREADY_UNLOCKED:
			_final_boss_unlock_status = &"already_unlocked"
			return "后续内容：已解锁（具体内容待后续接入）。"
		_:
			_final_boss_unlock_status = &"save_failed"
			return "首次通关完成；后续内容解锁状态保存失败，请保留本局记录。"


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
	if _network_active and _network_session.is_host():
		_broadcast_final_player_stats()
		_network_session.send_game_event({"type": "match_failed"})
		_network_session.return_to_lobby()
	_save_playtest_record(&"failed")
	hud.set_phase("餐车失控 · 本局结束")
	hud.show_results("服务失败", _build_results_text())
	get_tree().paused = true


func _on_restart_requested() -> void:
	_manual_pause_active = false
	get_tree().paused = false
	if _network_active:
		if _network_session.is_host() and _network_session.is_in_match():
			_network_session.return_to_lobby()
		return
	get_tree().reload_current_scene()


func _on_pause_requested() -> void:
	if _manual_pause_active or (phase != Phase.FORWARD and phase != Phase.BOSS):
		return
	if _network_active:
		cart.cancel_pointer_input()
		_network_session.request_pause()
		return
	_manual_pause_active = true
	cart.cancel_pointer_input()
	hud.show_pause(_build_pause_details_text())
	get_tree().paused = true


func _on_resume_requested() -> void:
	if not _manual_pause_active:
		return
	if _network_active:
		_network_session.request_resume()
		return
	_manual_pause_active = false
	hud.hide_pause()
	get_tree().paused = false
	hud.set_pause_available(phase == Phase.FORWARD or phase == Phase.BOSS)


func _on_weapon_food_added(food: FoodData) -> void:
	_on_player_weapon_food_added(food, 1)


func _on_weapon_food_removed(food_id: StringName) -> void:
	_on_player_weapon_food_removed(food_id, 1)


func _refresh_hud_inventory() -> void:
	for runtime: FoodRuntime in weapon_controller.foods:
		hud.add_cooking_food(runtime.data, state.food_level(runtime.data.id))
		hud.set_cooking_level(runtime.data.id, state.food_level(runtime.data.id))


func _build_pause_details_text() -> String:
	var sections: PackedStringArray = []
	sections.append(
		"餐车\n耐久 %.0f / %.0f　临时护盾 %.0f" % [
			state.current_durability,
			state.maximum_durability,
			state.temporary_shield,
		]
	)
	var upgrade_lines: PackedStringArray = []
	upgrade_lines.append("• %s" % state.cumulative_effect_text(UpgradeData.Kind.SUGAR))
	upgrade_lines.append(
		"• %s" % state.cumulative_effect_text(UpgradeData.Kind.QUICK_PREP)
	)
	upgrade_lines.append("• %s" % state.cumulative_effect_text(UpgradeData.Kind.WINE))
	upgrade_lines.append(
		"• %s" % state.cumulative_effect_text(UpgradeData.Kind.SCALLION)
	)
	upgrade_lines.append(
		"• %s" % state.cumulative_effect_text(UpgradeData.Kind.STARCH)
	)
	upgrade_lines.append(
		"• %s" % state.cumulative_effect_text(UpgradeData.Kind.LIGHT_CART)
	)
	upgrade_lines.append(
		"• %s" % state.cumulative_effect_text(UpgradeData.Kind.STURDY_CART)
	)
	upgrade_lines.append("• %s" % state.cumulative_effect_text(UpgradeData.Kind.REPAIR))
	sections.append("累计强化\n%s" % "\n".join(upgrade_lines))
	var food_lines: PackedStringArray = []
	for runtime: FoodRuntime in weapon_controller.foods:
		var food: FoodData = runtime.data
		var range_multiplier: float = (
			state.effective_projectile_radius(food) / maxf(0.001, food.projectile_radius)
		)
		var traits: PackedStringArray = []
		if state.is_food_target_aimed(food.id):
			traits.append("瞄准投喂")
		if state.is_food_homing(food.id):
			traits.append("飞行追踪")
		if food.id == &"baguette" and state.has_food_evolution(&"baguette_giant"):
			traits.append("巨型法棍 %.1fs" % state.effective_giant_baguette_interval())
		if food.id == &"mushroom" and state.has_food_evolution(&"mushroom_breath"):
			traits.append("呼吸菌圈")
		var trait_text: String = " · ".join(traits) if not traits.is_empty() else "无"
		food_lines.append(
			(
				"%s Lv.%d\n"
				+ "  满足 %.1f　烹饪 %.2fs　范围 ×%.2f\n"
				+ "  持续 %.2fs　份数 %d　命中 %d\n"
				+ "  特性 %s"
			) % [
				food.display_name,
				state.food_level(food.id),
				state.effective_satisfaction(food),
				state.effective_interval(food),
				range_multiplier,
				state.effective_duration(food),
				state.servings,
				state.effective_pierce_count(food),
				trait_text,
			]
		)
	sections.append(
		"食材详情\n%s" % (
			"\n\n".join(food_lines)
			if not food_lines.is_empty()
			else "尚未装车"
		)
	)
	return "\n\n".join(sections)


# Debug菜单只发送动作ID，所有局内写操作继续集中在单局控制器及RunState中。
func _on_debug_action_requested(action_id: StringName) -> void:
	var feedback: String = ""
	var success: bool = true
	var debug_food_id: StringName = _debug_food_id_for_action(action_id)
	if not debug_food_id.is_empty():
		var debug_food: FoodData = _food_data_for_id(debug_food_id)
		if debug_food == null:
			success = false
			feedback = "未找到食材数据：%s" % str(debug_food_id)
		elif state.has_food(debug_food.id):
			success = false
			feedback = "%s 已在车上" % debug_food.display_name
		else:
			weapon_controller.add_food(debug_food)
			feedback = "已获取食材：%s" % debug_food.display_name
		debug_menu.show_feedback(feedback, success)
		_refresh_debug_menu()
		return
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
				_update_reward_effect_scale(30.0)
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
		&"remove_all_foods":
			var removed_count: int = _debug_remove_all_foods()
			success = removed_count > 0
			feedback = (
				"已移除当前所有食材（%d 种）" % removed_count
				if success
				else "当前没有可移除的食材"
			)
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
			feedback = "未知 Debug 操作：%s" % str(action_id)
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
		var display_name: String = food.display_name if food != null else str(food_id)
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


# 将控制台按钮映射到当前武器表中的基础食材ID。
func _debug_food_id_for_action(action_id: StringName) -> StringName:
	match action_id:
		&"get_food_potato":
			return &"potato"
		&"get_food_baguette":
			return &"baguette"
		&"get_food_mushroom":
			return &"mushroom"
		&"get_food_egg":
			return &"egg"
		&"get_food_carrot":
			return &"carrot"
	return &""


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


func _debug_remove_all_foods() -> int:
	var removed_count: int = weapon_controller.remove_all_foods()
	# 已发射的投射物属于当前食材攻击，移除库存时一并回收，避免清空后继续结算命中。
	for child: Node in projectiles.get_children():
		child.queue_free()
	return removed_count


func _clear_forward_objects() -> void:
	_forward_spawn_requests.clear()
	_reward_spawn_requests.clear()
	if _native_network_spawning_enabled() and not _network_session.is_host():
		# 客户端的门、食客和奖励由 MultiplayerSpawner 接收房主 despawn；这里只清本地视觉投射物。
		for child: Node in projectiles.get_children():
			child.queue_free()
		return
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
				str(food_id),
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
		food_levels_record[str(food_id)] = state.food_level(food_id)
		food_satisfaction_record[str(food_id)] = state.satisfaction_by_food.get(food_id, 0.0)
	var record: Dictionary = {
		"schema": "xiaochuxi.playtest_run.v2",
		"seed": state.run_seed,
		"outcome": str(outcome),
		"network_mode": "lan" if _network_active else "solo",
		"room_id": _network_session.room_id if _network_active else "",
		"player_slot": _network_session.local_slot if _network_active else 1,
		"player_count": _network_player_count if _network_active else 1,
		"team_death_count": _team_death_count,
		"players": _build_player_history_record(),
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
		"final_boss_unlock_status": str(_final_boss_unlock_status),
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


func _build_player_history_record() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for player_slot: int in _player_contexts:
		var context: PlayerRunContext = _player_contexts[player_slot]
		records.append({
			"slot": player_slot,
			"deaths": context.death_count,
			"ghost_seconds": context.ghost_elapsed_seconds,
			"final_ghost": context.is_ghost(),
			"respawn_remaining": context.respawn_remaining,
		})
	return records


# 每项同时保留提供、选择、实际结算值与点数贡献，供12局横向比较。
func _build_normal_upgrade_playtest_record() -> Array[Dictionary]:
	var ids: Array[String] = []
	for upgrade_id: StringName in state.normal_upgrade_offer_counts:
		ids.append(str(upgrade_id))
	for upgrade_id: StringName in state.normal_upgrade_choice_counts:
		if not ids.has(str(upgrade_id)):
			ids.append(str(upgrade_id))
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
		records[str(food_id)] = {
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
		satisfaction_delta[str(food_id)] = (
			state.satisfaction_by_food.get(food_id, 0.0)
			- _post_boss_satisfaction_start.get(food_id, 0.0)
		)
	var boss_reward: String = ""
	if not state.special_choice_records.is_empty():
		boss_reward = str(state.special_choice_records.back().selected)
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
		result.append(str(value))
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
func _roll_start_food_options(player_slot: int = 1) -> Array[UpgradeData]:
	var available: Array[FoodData] = _available_start_foods()
	var options: Array[UpgradeData] = []
	var choice_rng: RandomNumberGenerator = _player_choice_rng(player_slot)
	while not available.is_empty() and options.size() < 2:
		var index: int = choice_rng.randi_range(0, available.size() - 1)
		options.append(_make_start_food_option(available[index]))
		available.remove_at(index)
	if options.size() == 1:
		options.append(_make_start_food_option(_food_data_for_id(options[0].id)))
	return options


func _player_choice_rng(player_slot: int) -> RandomNumberGenerator:
	var safe_slot: int = maxi(1, player_slot)
	var existing: RandomNumberGenerator = _player_choice_rngs.get(safe_slot)
	if existing != null:
		return existing
	var choice_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	choice_rng.seed = _run_seed ^ (0x13579BDF + safe_slot * 104729)
	_player_choice_rngs[safe_slot] = choice_rng
	return choice_rng


# 当前原型未配置解锁子集时，全部已装配食材共同构成默认解锁池。
func _available_start_foods() -> Array[FoodData]:
	var configured_foods: Array[FoodData] = unlocked_foods.duplicate()
	if configured_foods.is_empty() and not _food_data_by_id.is_empty():
		for food: FoodData in _food_data_by_id.values():
			configured_foods.append(food)
	if configured_foods.is_empty():
		configured_foods = [potato_data, baguette_data, mushroom_data, egg_data, carrot_data]
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
	reward.set_source_scale(_reward_effect_scale)
	if state != null:
		state.record_normal_upgrade_offer([reward])
	return reward


# 从当前有效池完全随机抽出三个不同选项；不做新食材或进化保底。
func _roll_special_choices(
	source_state: RunState = null,
	player_slot: int = 1
) -> Array[StringName]:
	_ensure_special_upgrade_data()
	var choice_state: RunState = source_state if source_state != null else state
	var available: Array[StringName] = []
	for choice_id: StringName in _special_choice_pool:
		if _special_choice_is_valid(choice_id, choice_state):
			available.append(choice_id)
	var choices: Array[StringName] = []
	var choice_count: int = mini(3, available.size())
	var choice_rng: RandomNumberGenerator = _player_choice_rng(player_slot)
	while choices.size() < choice_count:
		var index: int = choice_rng.randi_range(0, available.size() - 1)
		choices.append(available[index])
		available.remove_at(index)
	return choices


func _special_choice_is_valid(choice_id: StringName, source_state: RunState = null) -> bool:
	_ensure_special_upgrade_data()
	var choice_state: RunState = source_state if source_state != null else state
	var upgrade: SpecialUpgradeData = _special_upgrades_by_id.get(choice_id)
	if upgrade == null:
		return false
	match upgrade.effect_kind:
		SpecialUpgradeData.EffectKind.FOOD_CARD:
			return choice_state.food_level(upgrade.target_id) < choice_state.food_max_level
		SpecialUpgradeData.EffectKind.TARGET_AIM:
			return (
				choice_state.has_food(upgrade.target_id)
				and not choice_state.is_food_target_aimed(upgrade.target_id)
			)
		SpecialUpgradeData.EffectKind.EVOLUTION:
			return (
				choice_state.has_food(upgrade.target_id)
				and not choice_state.has_food_evolution(upgrade.id)
			)
		SpecialUpgradeData.EffectKind.SERVING, SpecialUpgradeData.EffectKind.PIERCE:
			return upgrade.repeatable or not choice_state.specials.has(upgrade.id)
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


# 回退池完整保留当前实现，确保任一 Excel 损坏时仍可开始新局。
func _build_fallback_special_upgrades() -> void:
	_set_special_upgrades([
		_make_special_upgrade(&"potato", "土豆", SpecialUpgradeData.EffectKind.FOOD_CARD, &"potato", 1.0, true, "获得新食材并加入自动投喂", "提高自身基础满足值"),
		_make_special_upgrade(&"baguette", "法棍", SpecialUpgradeData.EffectKind.FOOD_CARD, &"baguette", 1.0, true, "获得新食材并加入自动投喂", "提高自身基础满足值"),
		_make_special_upgrade(&"mushroom", "蘑菇", SpecialUpgradeData.EffectKind.FOOD_CARD, &"mushroom", 1.0, true, "获得新食材并加入自动投喂", "提高自身基础满足值"),
		_make_special_upgrade(&"egg", "鸡蛋", SpecialUpgradeData.EffectKind.FOOD_CARD, &"egg", 1.0, true, "获得新食材并加入自动投喂", "提高自身基础满足值"),
		_make_special_upgrade(&"carrot", "胡萝卜", SpecialUpgradeData.EffectKind.FOOD_CARD, &"carrot", 1.0, true, "获得新食材并加入自动投喂", "提高自身基础满足值"),
		_make_special_upgrade(&"serving", "全局加量", SpecialUpgradeData.EffectKind.SERVING, &"", 1.0, true, "当前与未来食材增加攻击份数", ""),
		_make_special_upgrade(&"potato_aim", "瞄准投喂", SpecialUpgradeData.EffectKind.TARGET_AIM, &"potato", 1.0, false, "土豆发射时朝向当前目标", ""),
		_make_special_upgrade(&"baguette_giant", "巨型法棍", SpecialUpgradeData.EffectKind.EVOLUTION, &"baguette", 1.0, false, "以3秒基础间隔额外发射一根横跨四格、滚动直行的巨型法棍", ""),
		_make_special_upgrade(&"mushroom_breath", "呼吸菌圈", SpecialUpgradeData.EffectKind.EVOLUTION, &"mushroom", 1.0, false, "蘑菇环绕半径按武器表周期与倍率呼吸", ""),
		_make_special_upgrade(&"carrot_bounce", "往返扫掠", SpecialUpgradeData.EffectKind.EVOLUTION, &"carrot", 1.0, false, "胡萝卜扫到端点后反向往返", ""),
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
			texts[choice_id] = str(choice_id)
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
