extends SceneTree

var _failures: int = 0


func _init() -> void:
	_test_playfield()
	_test_customer_cart_collision()
	_test_run_state()
	_test_weapon_fires_without_target()
	_test_upgrade_gate()
	_test_customer_reward_gate()
	_test_reward_gate_spacing()
	_test_customer_reward_randomness()
	_test_timeline()
	_test_resources()
	if _failures == 0:
		print("CORE_TESTS_OK")
		quit(0)
	else:
		push_error("CORE_TESTS_FAILED count=%d" % _failures)
		quit(1)


func _test_playfield() -> void:
	var field: Playfield = Playfield.new()
	_check(field.region_at_x(60.0) == 0, "左边界属于第0区")
	_check(field.region_at_x(659.9) == 5, "右边界属于第5区")
	_check(is_equal_approx(field.region_center(2), 310.0), "区域中心计算")
	_check(is_equal_approx(field.clamp_cart_x(-100.0), 108.0), "餐车左边界")
	_check(is_equal_approx(field.clamp_cart_x(900.0), 612.0), "餐车右边界")
	_check(
		field.forward_paths_are_separated(-640.0, 250.0, 0.0, 250.0),
		"同速前进对象保持初始安全距离"
	)
	_check(
		not field.forward_paths_are_separated(-300.0, 301.0, 0.0, 250.0),
		"会在抵达餐车前追尾的对象需要延迟生成"
	)
	field.free()


func _test_customer_cart_collision() -> void:
	var field: Playfield = Playfield.new()
	var state: RunState = RunState.new()
	var cart: Cart = Cart.new()
	cart.configure(state, field)
	var basic_data: CustomerData = load("res://data/customers/basic_guest.tres") as CustomerData
	var customer: Customer = Customer.new()
	customer.configure(basic_data, null, 1, 32.0)
	customer.position = Vector2(160.0, 900.0)
	_check(not customer.collision_rect().intersects(cart.collision_rect()), "食客纵向到达餐车但横向绕开时不算碰撞")
	customer.position = Vector2(360.0, 900.0)
	_check(customer.collision_rect().intersects(cart.collision_rect()), "食客与餐车绘制范围相交时算碰撞")
	customer.position = Vector2(160.0, Playfield.CUSTOMER_DESPAWN_Y)
	_check(not customer.collision_rect().intersects(cart.collision_rect()), "绕开的食客到达屏幕底部时不算碰撞")
	customer.free()
	cart.free()
	field.free()


func _test_run_state() -> void:
	var state: RunState = RunState.new()
	var potato: FoodData = load("res://data/foods/potato.tres") as FoodData
	var sugar: UpgradeData = UpgradeData.new()
	sugar.kind = UpgradeData.Kind.SUGAR
	sugar.value = 0.2
	state.apply_upgrade(sugar)
	_check(is_equal_approx(state.effective_satisfaction(potato), 12.0), "满足值按基础值加算")

	var quick_prep: UpgradeData = UpgradeData.new()
	quick_prep.kind = UpgradeData.Kind.QUICK_PREP
	quick_prep.value = 3.0
	state.apply_upgrade(quick_prep)
	_check(is_equal_approx(state.effective_interval(potato), RunState.MINIMUM_INTERVAL), "攻击间隔限制为每帧一次")
	quick_prep.value = 0.08
	_check(quick_prep.effect_text() == "间隔 -8%", "门使用简洁攻击间隔描述")

	var multiplicative_state: RunState = RunState.new()
	var half_more: UpgradeData = UpgradeData.new()
	half_more.kind = UpgradeData.Kind.SUGAR
	half_more.value = 0.5
	multiplicative_state.apply_upgrade(half_more)
	multiplicative_state.apply_upgrade(half_more, false)
	_check(
		is_equal_approx(multiplicative_state.effective_satisfaction(potato), 22.5),
		"两次满足值加成按1.5乘1.5累计"
	)
	var faster: UpgradeData = UpgradeData.new()
	faster.kind = UpgradeData.Kind.QUICK_PREP
	faster.value = 0.2
	multiplicative_state.apply_upgrade(faster)
	multiplicative_state.apply_upgrade(faster)
	_check(
		is_equal_approx(multiplicative_state.effective_interval(potato), potato.base_interval * 0.64),
		"两次间隔缩短按0.8乘0.8累计"
	)
	_check(multiplicative_state.dropped_upgrades == 1, "掉落百分比强化使用同一乘算链并单独计数")

	var sturdy: UpgradeData = UpgradeData.new()
	sturdy.kind = UpgradeData.Kind.STURDY_CART
	sturdy.value = 10.0
	state.apply_upgrade(sturdy)
	_check(is_equal_approx(state.maximum_durability, 110.0), "最大耐久提高")
	_check(is_equal_approx(state.current_durability, 110.0), "坚固餐车同步提高当前耐久")

	state.take_durability_damage(40.0)
	var repair: UpgradeData = UpgradeData.new()
	repair.kind = UpgradeData.Kind.REPAIR
	repair.value = 0.2
	state.apply_upgrade(repair)
	_check(is_equal_approx(state.current_durability, 92.0), "维修按最大耐久比例恢复")
	_check(repair.effect_text(state.maximum_durability) == "修复 +22点", "维修门显示简洁实际点数")
	var previous_gate_count: int = state.gate_choices
	state.apply_upgrade(sugar, false)
	_check(state.gate_choices == previous_gate_count, "食客奖励门不计入普通双选门")
	_check(state.dropped_upgrades == 1, "食客奖励门单独计数")
	state.add_pierce_bonus()
	_check(state.effective_pierce_count(potato) == 2, "酱油让土豆额外命中一个目标")

	var distance_state: RunState = RunState.new()
	var wine: UpgradeData = UpgradeData.new()
	wine.kind = UpgradeData.Kind.WINE
	wine.value = 0.25
	distance_state.apply_upgrade(wine)
	var starch: UpgradeData = UpgradeData.new()
	starch.kind = UpgradeData.Kind.STARCH
	starch.value = 0.5
	distance_state.apply_upgrade(starch)
	_check(
		is_equal_approx(
			distance_state.effective_projectile_distance(potato),
			potato.projectile_speed * 1.25 * potato.base_lifetime * 1.5
		),
		"弹速与持续时间共同决定投射距离"
	)


func _test_weapon_fires_without_target() -> void:
	var run: RunController = RunController.new()
	var state: RunState = RunState.new()
	var field: Playfield = Playfield.new()
	var cart: Cart = Cart.new()
	var projectiles: Node2D = Node2D.new()
	var gates: Node2D = Node2D.new()
	var drops: Node2D = Node2D.new()
	var weapon: WeaponController = WeaponController.new()
	run.state = state
	run.playfield = field
	run.cart = cart
	run.projectiles = projectiles
	run.gates = gates
	run.drops = drops
	run.add_child(field)
	run.add_child(cart)
	run.add_child(projectiles)
	run.add_child(gates)
	run.add_child(drops)
	run.add_child(weapon)
	cart.configure(state, field)
	weapon.configure(run, cart, state)
	var potato: FoodData = load("res://data/foods/potato.tres") as FoodData
	weapon.add_food(potato)
	weapon._tick_food(weapon.foods[0], 0.0)
	_check(projectiles.get_child_count() == 1, "没有目标时食材仍按冷却朝前发射")
	run.free()


func _test_upgrade_gate() -> void:
	var left: UpgradeData = UpgradeData.new()
	left.kind = UpgradeData.Kind.SUGAR
	left.configure_value_range(0.05, 0.45, 0.34)
	var right: UpgradeData = UpgradeData.new()
	right.kind = UpgradeData.Kind.WINE
	right.configure_value_range(0.10, 0.50, 0.80)
	var gate: UpgradeGate = UpgradeGate.new()
	gate.configure(null, left, right, false, 100.0, 1)
	_check(is_equal_approx(gate.left_base_health, 134.0), "左门基础血量按1加百分位乘基准胃口")
	_check(is_equal_approx(gate.right_base_health, 180.0), "稀有门拥有更高基础血量与撞门风险")
	_check(is_equal_approx(gate.left_upgrade_health, 66.0), "34%门的隐藏升值血量为基准胃口的66%")
	_check(is_equal_approx(gate.right_upgrade_health, 20.0), "左右门使用各自抽取百分位计算隐藏血量")
	gate.receive_damage(true, 134.0)
	_check(is_zero_approx(gate.left_base_health), "攻击先击破门的公开基础血量")
	_check(is_equal_approx(left.value_ratio, 0.34), "击破基础层的攻击不会溢出到隐藏升值层")
	gate.receive_damage(true, 33.0)
	_check(is_equal_approx(left.value_ratio, 0.67), "打掉一半隐藏升值血量后百分位由34%提升到67%")
	_check(is_equal_approx(left.value, lerpf(0.05, 0.45, 0.67)), "门奖励随受击百分位实时映射")
	_check(is_equal_approx(gate.right_base_health, 180.0), "攻击左门不会改变右门基础血量")
	_check(is_equal_approx(gate.right_upgrade_health, 20.0), "攻击左门不会改变右门隐藏血量")
	gate.receive_damage(true, 100.0)
	_check(left.is_at_maximum() and not gate.side_is_attackable(true), "门打空后达到区间上限并停止锁定")
	_check(gate.selected_upgrade_for_x(359.9) == left, "中心线左侧只选择左门")
	_check(gate.selected_upgrade_for_x(360.0) == right, "中心点固定只选择右门")
	_check(gate.selected_base_health_for_x(360.0) == gate.right_base_health, "中心点只结算右门碰撞损伤")
	gate.free()

	var start_gate: UpgradeGate = UpgradeGate.new()
	start_gate.configure(null, left, right, true, 100.0, 2)
	_check(not start_gate.side_is_attackable(true), "开局食材门不可攻击")
	_check(start_gate.target_for_cart_x(200.0) == null, "开局食材门不进入自动目标池")
	start_gate.free()


func _test_customer_reward_gate() -> void:
	var reward: UpgradeData = UpgradeData.new()
	reward.kind = UpgradeData.Kind.SUGAR
	reward.configure_value_range(0.05, 0.45, 0.34)
	var basic: CustomerData = load("res://data/customers/basic_guest.tres") as CustomerData
	var elite: CustomerData = load("res://data/customers/elite_guest.tres") as CustomerData
	_check(is_equal_approx(basic.appetite_at(100.0, 0.34), 134.0), "普通食客胃口按奖励百分位提高")
	_check(is_equal_approx(elite.appetite_at(32.0), 180.0), "精英不参与随机稀有度")
	var reward_gate: UpgradeDrop = UpgradeDrop.new()
	reward_gate.configure(null, reward, Vector2(160.0, 400.0), 100.0, 2, 3)
	_check(is_equal_approx(reward_gate.upgrade_health, 66.0), "食客奖励门没有基础层并按百分位建立升值血量")
	_check(reward_gate.contains_cart_x(160.0), "餐车经过食客原占地区域可以领取奖励门")
	_check(not reward_gate.contains_cart_x(360.0), "餐车绕开奖励门时不能领取")
	reward_gate.receive_damage(33.0)
	_check(is_equal_approx(reward.value_ratio, 0.67), "攻击奖励门继续提高同一份奖励")
	reward_gate.free()


func _test_reward_gate_spacing() -> void:
	var run: RunController = RunController.new()
	var field: Playfield = Playfield.new()
	var gates: Node2D = Node2D.new()
	var drops: Node2D = Node2D.new()
	run.playfield = field
	run.gates = gates
	run.drops = drops
	run.add_child(field)
	run.add_child(gates)
	run.add_child(drops)
	var gate: UpgradeGate = UpgradeGate.new()
	gate.position.y = 400.0
	gates.add_child(gate)
	var existing_drop: UpgradeDrop = UpgradeDrop.new()
	existing_drop.position.y = 650.0
	drops.add_child(existing_drop)
	var safe_y: float = run._find_reward_gate_spawn_y(500.0)
	_check(
		field.forward_paths_are_separated(safe_y, 250.0, gate.position.y, gate.travel_speed()),
		"新奖励门不会与原普通门重叠或追尾"
	)
	_check(
		field.forward_paths_are_separated(safe_y, 250.0, existing_drop.position.y, existing_drop.travel_speed()),
		"食客奖励门之间不会重叠或追尾"
	)
	run.free()


func _test_customer_reward_randomness() -> void:
	var run: RunController = RunController.new()
	run._build_drop_upgrades()
	var first_kinds: Dictionary = {}
	for seed_value: int in range(1, 17):
		run._upgrade_rng.seed = seed_value
		var reward: UpgradeData = run._roll_customer_reward()
		first_kinds[reward.kind] = true
	_check(first_kinds.size() > 1, "首个食客奖励类型由随机数抽取而非固定为糖")
	run.state = RunState.new()
	run._upgrade_rng.seed = 1701
	var special_choices: Array[StringName] = run._roll_special_choices()
	_check(special_choices.size() == 3, "特殊奖励池每次提供三个不同候选")
	_check(run._special_choice_pool.has(&"soy_sauce"), "酱油已进入特殊奖励候选池")
	run.free()


func _test_timeline() -> void:
	var fallback: EncounterTimeline = load("res://data/timelines/vertical_slice.tres") as EncounterTimeline
	var load_result: TimelineExcelLoader.LoadResult = TimelineExcelLoader.load_from_excel(
		"res://balance_tables/时间轴.xlsx",
		fallback
	)
	_check(load_result.loaded_from_excel, "时间轴直接读取 Excel 数值主表")
	var timeline: EncounterTimeline = load_result.timeline
	_check(timeline != null and timeline.is_valid(), "时间轴事件数量一致")
	if timeline == null:
		return
	_check(
		is_equal_approx(timeline.baseline_appetite_at(0.0), roundf(timeline.baseline_appetite_start)),
		"基准胃口曲线使用 Excel 起点"
	)
	_check(
		is_equal_approx(
			timeline.baseline_appetite_at(timeline.baseline_appetite_end_time),
			roundf(timeline.baseline_appetite_end)
		),
		"基准胃口曲线使用 Excel 终点和结束时间"
	)
	var midpoint_time: float = timeline.baseline_appetite_end_time * 0.5
	var expected_midpoint: float = roundf(lerpf(
		timeline.baseline_appetite_start,
		timeline.baseline_appetite_end,
		pow(0.5, timeline.baseline_appetite_exponent)
	))
	_check(
		is_equal_approx(timeline.baseline_appetite_at(midpoint_time), expected_midpoint),
		"基准胃口曲线使用 Excel 增长指数"
	)
	var gate_count: int = 0
	for event_text: String in timeline.event_ids:
		if event_text.begins_with("gate_"):
			gate_count += 1
	_check(gate_count == 12, "竖切片包含12道普通强化门")
	_check(timeline.event_ids.has("elite"), "时间轴包含精英")
	_check(timeline.event_ids.has("boss"), "时间轴包含Boss")
	var post_elite_gate_index: int = timeline.event_ids.find("gate_6")
	var elite_index: int = timeline.event_ids.find("elite")
	_check(
		post_elite_gate_index > elite_index
		and timeline.event_times[post_elite_gate_index] >= timeline.event_times[elite_index],
		"精英后首门保持在精英事件之后"
	)
	var missing_result: TimelineExcelLoader.LoadResult = TimelineExcelLoader.load_from_excel(
		"res://balance_tables/__missing__.xlsx",
		fallback
	)
	_check(missing_result.used_fallback and missing_result.timeline == fallback, "Excel 缺失时使用 .tres 回退")


func _test_resources() -> void:
	var potato: FoodData = load("res://data/foods/potato.tres") as FoodData
	var baguette: FoodData = load("res://data/foods/baguette.tres") as FoodData
	var elite: CustomerData = load("res://data/customers/elite_guest.tres") as CustomerData
	var boss: BossPatternData = load("res://data/bosses/prototype_boss.tres") as BossPatternData
	_check(potato != null and is_equal_approx(potato.base_satisfaction, 10.0), "土豆基线")
	_check(potato.initial_aim_mode == FoodData.AimMode.FIXED_FORWARD, "土豆初始固定竖直发射")
	_check(potato.initial_tracking_mode == FoodData.TrackingMode.NONE, "土豆初始为直线非追踪弹道")
	_check(baguette != null and baguette.pierce_count == 3, "法棍穿透数")
	_check(baguette.initial_tracking_mode == FoodData.TrackingMode.NONE, "法棍初始不追踪")
	_check(is_equal_approx(potato.projectile_speed * potato.base_lifetime / 1280.0, 0.8), "土豆基础持续约0.8屏")
	_check(is_equal_approx(baguette.projectile_speed * baguette.base_lifetime / 1280.0, 0.6), "法棍基础持续约0.6屏")
	_check(elite != null and elite.occupied_regions == 6, "精英横跨六区")
	_check(elite != null and is_equal_approx(elite.appetite_multiplier, 1.5), "精英默认使用1.5倍基准胃口")
	_check(boss != null and is_equal_approx(boss.appetite_at(100.0), 300.0), "Boss默认使用3倍基准胃口")
	var state: RunState = RunState.new()
	_check(not state.is_food_target_aimed(&"potato"), "特殊强化前土豆不跟随目标角度")
	state.enable_target_aim(&"potato")
	_check(state.is_food_target_aimed(&"potato"), "特殊强化可以开启发射角度瞄准")
	_check(not state.is_food_homing(&"potato"), "特殊强化前土豆不追踪")
	state.enable_homing(&"potato")
	_check(state.is_food_homing(&"potato"), "特殊强化可以为指定食材开启追踪")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("TEST FAILED: %s" % message)
