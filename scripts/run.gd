class_name RunController
extends Node2D

enum Phase {
	INTRO,
	FORWARD,
	CHOICE,
	BOSS,
	RESULTS,
	FAILED,
}

@export_group("Prototype data")
@export var potato_data: FoodData
@export var baguette_data: FoodData
@export var basic_guest_data: CustomerData
@export var fast_guest_data: CustomerData
@export var ranged_guest_data: CustomerData
@export var elite_guest_data: CustomerData
@export var boss_data: BossPatternData

@onready var background: WorldBackground = %Background
@onready var entities: Node2D = %Entities
@onready var projectiles: Node2D = %Projectiles
@onready var drops: Node2D = %Drops
@onready var gates: Node2D = %Gates
@onready var cart: Cart = %Cart
@onready var weapon_controller: WeaponController = %WeaponController
@onready var director: EncounterDirector = %EncounterDirector
@onready var hud: GameHud = %Hud

var world_scroll_speed: float = 205.0
var state: RunState
var playfield: Playfield
var phase: Phase = Phase.INTRO
var customers: Array[Customer] = []
var boss: PrototypeBoss
var _spawn_counter: int = 0
var _elite_started_at: float = 0.0
var _boss_started_at: float = 0.0
var _debug_accumulator: float = 0.0
var _upgrade_pairs: Array[UpgradeData] = []
var _drop_upgrades: Array[UpgradeData] = []
var _drop_counter: int = 0
var _normal_wave_index: int = 0
var _next_normal_spawn_time: float = 8.0
var _smoke_test: bool = false


func _ready() -> void:
	_smoke_test = OS.get_cmdline_user_args().has("--smoke-test")
	state = RunState.new()
	if _smoke_test:
		state.maximum_durability = 10000.0
		state.current_durability = 10000.0
		Engine.time_scale = 20.0
	playfield = Playfield.new()
	add_child(playfield)
	cart.configure(state, playfield)
	weapon_controller.configure(self, cart, state)
	weapon_controller.add_food(potato_data)
	_build_prototype_upgrades()
	_build_drop_upgrades()
	director.event_triggered.connect(_on_timeline_event)
	cart.damaged.connect(_on_cart_damaged)
	cart.destroyed.connect(_on_cart_destroyed)
	state.durability_changed.connect(hud.set_durability)
	state.inventory_changed.connect(_refresh_inventory)
	hud.special_choice_selected.connect(_on_special_choice_selected)
	hud.restart_requested.connect(_on_restart_requested)
	hud.set_durability(state.current_durability, state.maximum_durability)
	hud.set_inventory(state)
	hud.set_phase("准备出餐 · 横向拖动餐车")
	hud.show_toast("按住并横向拖动，松手后餐车留在原位")
	phase = Phase.FORWARD


func _process(delta: float) -> void:
	if phase == Phase.FORWARD or phase == Phase.BOSS:
		state.elapsed_seconds += delta
		director.advance(state.elapsed_seconds)
		if phase == Phase.FORWARD:
			_advance_normal_waves()
		hud.set_time(state.elapsed_seconds)
		if _smoke_test:
			cart.target_x = 360.0 + sin(state.elapsed_seconds * 1.7) * 245.0
	_debug_accumulator += delta
	if _debug_accumulator >= 0.25:
		_debug_accumulator = 0.0
		hud.set_debug_text(
			"FPS %d  食客 %d  投射物 %d\n门 %d  掉落 %d  击败 %d" % [
				Engine.get_frames_per_second(),
				customers.size(),
				projectiles.get_child_count(),
				state.gate_choices,
				state.dropped_upgrades,
				state.customers_satisfied,
			]
		)


func is_world_scrolling() -> bool:
	return phase == Phase.FORWARD


func can_weapons_fire() -> bool:
	return phase == Phase.FORWARD or phase == Phase.BOSS


func get_priority_target() -> Node2D:
	var best_target: Node2D = null
	var best_forward: float = INF
	var best_horizontal: float = INF
	var best_spawn_index: int = 2147483647
	for customer: Customer in customers:
		if not is_instance_valid(customer) or not customer.active or customer.position.y >= cart.position.y:
			continue
		var forward: float = cart.position.y - customer.position.y
		var horizontal: float = absf(customer.position.x - cart.position.x)
		if _target_is_better(forward, horizontal, customer.spawn_index, best_forward, best_horizontal, best_spawn_index):
			best_target = customer
			best_forward = forward
			best_horizontal = horizontal
			best_spawn_index = customer.spawn_index
	if boss != null and is_instance_valid(boss) and boss.active:
		var boss_forward: float = cart.position.y - boss.position.y
		var boss_horizontal: float = absf(boss.position.x - cart.position.x)
		if _target_is_better(boss_forward, boss_horizontal, 2000000000, best_forward, best_horizontal, best_spawn_index):
			best_target = boss
	return best_target


func spawn_projectile(
	start_position: Vector2,
	direction: Vector2,
	food: FoodData,
	amount: float,
	speed: float,
	radius: float,
	target: Node2D
) -> void:
	var projectile: FoodProjectile = FoodProjectile.new()
	projectile.z_index = 20
	projectiles.add_child(projectile)
	var should_home: bool = (
		food.initial_tracking_mode == FoodData.TrackingMode.HOMING
		or state.is_food_homing(food.id)
	)
	var lifetime: float = state.effective_duration(food)
	projectile.configure(self, start_position, direction, food, amount, speed, radius, lifetime, target, should_home)


func resolve_projectile_hits(projectile: FoodProjectile) -> void:
	if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
		return
	for customer: Customer in customers:
		if not is_instance_valid(customer) or not customer.active or not projectile.can_hit(customer):
			continue
		var distance: float = projectile.global_position.distance_to(customer.global_position)
		if distance <= projectile.radius + customer.hit_radius():
			customer.receive_satisfaction(projectile.satisfaction)
			if projectile.register_hit(customer):
				return
	if boss != null and is_instance_valid(boss) and boss.active and projectile.can_hit(boss):
		var boss_distance: float = projectile.global_position.distance_to(boss.global_position)
		if boss_distance <= projectile.radius + boss.hit_radius():
			boss.receive_satisfaction(projectile.satisfaction)
			projectile.register_hit(boss)


func on_gate_selected(upgrade: UpgradeData, start_food_gate: bool) -> void:
	if start_food_gate:
		hud.show_toast("土豆装车！自动寻找最近的食客")
		return
	state.apply_upgrade(upgrade)
	cart.play_upgrade_feedback(upgrade.rarity_color)
	hud.show_toast(
		"%s：%s\n%s" % [
			upgrade.display_name,
			upgrade.effect_text(state.maximum_durability),
			state.cumulative_effect_text(upgrade.kind),
		],
		upgrade.rarity_color
	)


func on_upgrade_drop_collected(upgrade: UpgradeData) -> void:
	state.apply_upgrade(upgrade, false)
	cart.play_upgrade_feedback(upgrade.rarity_color)
	hud.show_toast(
		"掉落 %s：%s\n%s" % [
			upgrade.display_name,
			upgrade.effect_text(state.maximum_durability),
			state.cumulative_effect_text(upgrade.kind),
		],
		upgrade.rarity_color
	)


func damage_cart(amount: float, source: String) -> void:
	if cart.take_damage(amount):
		hud.show_toast("%s：耐久 -%.0f" % [source, amount], Color("#ff7858"))


func _on_timeline_event(event_id: StringName) -> void:
	if event_id == &"start_gate":
		_spawn_gate(0, true)
	elif event_id == &"basic":
		_spawn_customer(basic_guest_data)
	elif event_id == &"fast":
		_spawn_customer(fast_guest_data)
	elif event_id == &"ranged":
		_spawn_customer(ranged_guest_data)
	elif event_id == &"elite":
		_spawn_elite()
	elif event_id == &"boss":
		_start_boss()
	elif String(event_id).begins_with("gate_"):
		var gate_index: int = String(event_id).trim_prefix("gate_").to_int()
		_spawn_gate(gate_index, false)


func _spawn_customer(customer_data: CustomerData) -> void:
	if phase != Phase.FORWARD:
		return
	_spawn_counter += 1
	var customer: Customer = Customer.new()
	customer.z_index = 10
	var max_start: int = Playfield.REGION_COUNT - customer_data.occupied_regions
	var first_region: int = (_spawn_counter * 2 + customer_data.kind) % (max_start + 1)
	customer.position = Vector2(playfield.spawn_x(first_region, customer_data.occupied_regions), -95.0)
	entities.add_child(customer)
	customer.configure(customer_data, self, _spawn_counter)
	customer.satisfied.connect(_on_customer_satisfied)
	customer.leaked.connect(_on_customer_leaked)
	customer.ranged_attack.connect(_on_customer_ranged_attack)
	customers.append(customer)


func _advance_normal_waves() -> void:
	var elapsed: float = state.elapsed_seconds
	if elapsed >= 132.0:
		return
	if elapsed >= 78.0 and elapsed < 96.0:
		_next_normal_spawn_time = 96.0
		return
	while elapsed >= _next_normal_spawn_time and _next_normal_spawn_time < 132.0:
		var pattern: int = _normal_wave_index % 5
		var customer_data: CustomerData = basic_guest_data
		if pattern == 2:
			customer_data = fast_guest_data
		elif pattern == 4:
			customer_data = ranged_guest_data
		_spawn_customer(customer_data)
		if _normal_wave_index % 4 == 3:
			_spawn_customer(basic_guest_data if pattern == 4 else fast_guest_data)
		_normal_wave_index += 1
		_next_normal_spawn_time += 3.2 if _next_normal_spawn_time < 78.0 else 2.8


func _spawn_elite() -> void:
	if phase != Phase.FORWARD:
		return
	_elite_started_at = state.elapsed_seconds
	_spawn_counter += 1
	var elite: Customer = Customer.new()
	elite.z_index = 12
	elite.position = Vector2(360.0, -95.0)
	entities.add_child(elite)
	elite.configure(elite_guest_data, self, _spawn_counter)
	elite.satisfied.connect(_on_customer_satisfied)
	elite.leaked.connect(_on_customer_leaked)
	elite.ranged_attack.connect(_on_customer_ranged_attack)
	customers.append(elite)
	hud.set_phase("精英检查 · 六区无法绕行")
	hud.show_toast("六席贵客挡住整条路，尽快满足它！", Color("#f0c45f"))


func _spawn_gate(index: int, is_start_gate: bool) -> void:
	if phase != Phase.FORWARD:
		return
	var gate: UpgradeGate = UpgradeGate.new()
	gate.z_index = 28
	gates.add_child(gate)
	if is_start_gate:
		gate.configure(self, _upgrade_pairs[0], _upgrade_pairs[0], true)
		return
	var pair_start: int = (index * 2) % _upgrade_pairs.size()
	var left: UpgradeData = _upgrade_pairs[pair_start]
	var right: UpgradeData = _upgrade_pairs[(pair_start + 1) % _upgrade_pairs.size()]
	gate.configure(self, left, right)


func _start_boss() -> void:
	if phase == Phase.BOSS or phase == Phase.RESULTS or phase == Phase.FAILED:
		return
	phase = Phase.BOSS
	background.scrolling = false
	_clear_forward_objects()
	_boss_started_at = state.elapsed_seconds
	boss = PrototypeBoss.new()
	boss.z_index = 30
	entities.add_child(boss)
	boss.configure(boss_data, self)
	boss.satisfied.connect(_on_boss_satisfied)
	hud.set_phase("Boss服务 · 躲开预警并自动反击")
	hud.show_toast("前进停止！危险预警后会出现反击窗口", Color("#ff7957"))


func _on_customer_satisfied(customer: Customer) -> void:
	_finish_customer(customer, false)


func _on_customer_leaked(customer: Customer) -> void:
	var remaining: float = customer.remaining_appetite
	damage_cart(remaining, "漏客投诉")
	_finish_customer(customer, true)


func _finish_customer(customer: Customer, collided: bool) -> void:
	var was_elite: bool = customer.data.kind == CustomerData.Kind.ELITE
	var defeat_position: Vector2 = customer.global_position
	state.customers_satisfied += 1
	if collided:
		state.collided_defeats += 1
	customers.erase(customer)
	customer.queue_free()
	if phase == Phase.FAILED:
		return
	if was_elite:
		state.elite_duration = state.elapsed_seconds - _elite_started_at
		phase = Phase.CHOICE
		hud.set_phase("特别赏赐 · 三选一")
		hud.show_toast("撞击也算击败！" if collided else "精英已击败！", Color("#f0c45f"))
		hud.show_special_choices()
		if _smoke_test:
			_on_special_choice_selected(&"baguette")
		else:
			get_tree().paused = true
	else:
		state.normal_defeats += 1
		_spawn_upgrade_drop(defeat_position)
		hud.show_toast("撞击击败，掉落强化" if collided else "击败食客，掉落强化", Color("#f0d36e"))


func _spawn_upgrade_drop(start_position: Vector2) -> void:
	if _drop_upgrades.is_empty():
		return
	state.upgrade_drops_spawned += 1
	var upgrade: UpgradeData = _drop_upgrades[_drop_counter % _drop_upgrades.size()]
	_drop_counter += 1
	var drop: UpgradeDrop = UpgradeDrop.new()
	drop.z_index = 25
	drops.add_child(drop)
	drop.configure(self, upgrade, start_position)


func _on_customer_ranged_attack(_customer: Customer, amount: float) -> void:
	damage_cart(amount, "拍桌投诉")


func _on_special_choice_selected(choice_id: StringName) -> void:
	get_tree().paused = false
	match choice_id:
		&"baguette":
			weapon_controller.add_food(baguette_data)
			state.add_special(&"baguette_reward")
			hud.show_toast("获得法棍：直线穿透最多3名食客")
		&"serving":
			state.servings += 1
			state.add_special(&"serving")
			hud.show_toast("全局加量：每种食材多发一份")
		&"potato_aim":
			state.enable_target_aim(&"potato")
			state.add_special(&"potato_aim")
			hud.show_toast("瞄准投喂：土豆发射时朝向当前目标")
	hud.hide_special_choices()
	hud.set_phase("继续前进 · 构筑已变化")
	hud.set_inventory(state)
	phase = Phase.FORWARD


func _on_boss_satisfied() -> void:
	state.boss_duration = state.elapsed_seconds - _boss_started_at
	state.customers_satisfied += 1
	phase = Phase.RESULTS
	hud.set_phase("服务完成")
	var body: String = _build_results_text()
	hud.show_results("Boss满意离场！", body)
	if _smoke_test:
		if state.upgrade_drops_spawned != state.normal_defeats:
			push_error("SMOKE_TEST_FAILED drops=%d normal_defeats=%d" % [state.upgrade_drops_spawned, state.normal_defeats])
			Engine.time_scale = 1.0
			get_tree().quit(1)
			return
		print(
			"SMOKE_TEST_OK elapsed=%.2f gates=%d defeated=%d collisions=%d drops=%d" % [
				state.elapsed_seconds,
				state.gate_choices,
				state.customers_satisfied,
				state.collided_defeats,
				state.upgrade_drops_spawned,
			]
		)
		Engine.time_scale = 1.0
		get_tree().quit(0)
	else:
		get_tree().paused = true


func _on_cart_damaged(_amount: float) -> void:
	pass


func _on_cart_destroyed() -> void:
	if phase == Phase.RESULTS or phase == Phase.FAILED:
		return
	phase = Phase.FAILED
	hud.set_phase("餐车失控 · 本局结束")
	hud.show_results("服务失败", _build_results_text())
	get_tree().paused = true


func _on_restart_requested() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _refresh_inventory() -> void:
	hud.set_inventory(state)


func _clear_forward_objects() -> void:
	for customer: Customer in customers:
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
	if forward < best_forward - 0.01:
		return true
	if absf(forward - best_forward) > 0.01:
		return false
	if horizontal < best_horizontal - 0.01:
		return true
	if absf(horizontal - best_horizontal) > 0.01:
		return false
	return spawn_index < best_spawn_index


func _build_results_text() -> String:
	return (
		"用时：%02d:%02d\n"
		+ "强化门：%d\n"
		+ "掉落强化：%d\n"
		+ "击败敌人：%d\n"
		+ "撞击击败：%d\n"
		+ "受击次数：%d\n"
		+ "耐久损失：%.0f\n"
		+ "精英耗时：%.1fs\n"
		+ "Boss耗时：%.1fs\n"
		+ "剩余耐久：%.0f / %.0f"
	) % [
		floori(state.elapsed_seconds / 60.0),
		floori(state.elapsed_seconds) % 60,
		state.gate_choices,
		state.dropped_upgrades,
		state.customers_satisfied,
		state.collided_defeats,
		state.hits_taken,
		state.durability_lost,
		state.elite_duration,
		state.boss_duration,
		state.current_durability,
		state.maximum_durability,
	]


func _build_prototype_upgrades() -> void:
	_upgrade_pairs = [
		_make_upgrade(&"sugar", "糖", UpgradeData.Kind.SUGAR, 0.35, "%", "寻常", Color("#d7c59a")),
		_make_upgrade(&"quick_prep", "快速备餐", UpgradeData.Kind.QUICK_PREP, 0.18, "%", "精良", Color("#73b8a6")),
		_make_upgrade(&"light_cart", "轻便餐车", UpgradeData.Kind.LIGHT_CART, 260.0, "速度", "寻常", Color("#d7c59a")),
		_make_upgrade(&"sturdy_cart", "坚固餐车", UpgradeData.Kind.STURDY_CART, 25.0, "点", "精良", Color("#73b8a6")),
		_make_upgrade(&"repair", "现场修理", UpgradeData.Kind.REPAIR, 0.30, "%", "稀罕", Color("#c88ad4")),
		_make_upgrade(&"wine", "酒", UpgradeData.Kind.WINE, 0.35, "%", "寻常", Color("#d7c59a")),
		_make_upgrade(&"scallion", "葱", UpgradeData.Kind.SCALLION, 0.45, "%", "精良", Color("#73b8a6")),
		_make_upgrade(&"starch", "淀粉", UpgradeData.Kind.STARCH, 0.50, "%", "寻常", Color("#d7c59a")),
	]


func _build_drop_upgrades() -> void:
	_drop_upgrades = [
		_make_upgrade(&"drop_sugar", "糖", UpgradeData.Kind.SUGAR, 0.08, "%", "掉落", Color("#d7c59a")),
		_make_upgrade(&"drop_quick", "备餐", UpgradeData.Kind.QUICK_PREP, 0.04, "%", "掉落", Color("#73b8a6")),
		_make_upgrade(&"drop_wine", "酒", UpgradeData.Kind.WINE, 0.08, "%", "掉落", Color("#d7c59a")),
		_make_upgrade(&"drop_scallion", "葱", UpgradeData.Kind.SCALLION, 0.08, "%", "掉落", Color("#73b8a6")),
		_make_upgrade(&"drop_starch", "淀粉", UpgradeData.Kind.STARCH, 0.10, "%", "掉落", Color("#d7c59a")),
		_make_upgrade(&"drop_light", "轻车", UpgradeData.Kind.LIGHT_CART, 45.0, "速度", "掉落", Color("#73b8a6")),
		_make_upgrade(&"drop_sturdy", "坚固", UpgradeData.Kind.STURDY_CART, 4.0, "点", "掉落", Color("#d7c59a")),
		_make_upgrade(&"drop_repair", "修理", UpgradeData.Kind.REPAIR, 0.08, "%", "掉落", Color("#c88ad4")),
	]


func _make_upgrade(
	id: StringName,
	display_name: String,
	kind: UpgradeData.Kind,
	value: float,
	suffix: String,
	rarity: String,
	color: Color
) -> UpgradeData:
	var upgrade: UpgradeData = UpgradeData.new()
	upgrade.id = id
	upgrade.display_name = display_name
	upgrade.kind = kind
	upgrade.value = value
	upgrade.value_suffix = suffix
	upgrade.rarity_name = rarity
	upgrade.rarity_color = color
	return upgrade
