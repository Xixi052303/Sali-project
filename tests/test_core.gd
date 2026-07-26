extends SceneTree

var _failures: int = 0


func _init() -> void:
	_test_playfield()
	_test_run_state()
	_test_upgrade_gate()
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
	_check(state.gate_choices == previous_gate_count, "敌人掉落强化不计入强化门")
	_check(state.dropped_upgrades == 1, "敌人掉落强化单独计数")


func _test_upgrade_gate() -> void:
	var left: UpgradeData = UpgradeData.new()
	left.kind = UpgradeData.Kind.SUGAR
	left.configure_value_range(0.05, 0.45, 0.34)
	var right: UpgradeData = UpgradeData.new()
	right.kind = UpgradeData.Kind.WINE
	right.configure_value_range(0.10, 0.50, 0.80)
	var gate: UpgradeGate = UpgradeGate.new()
	gate.configure(null, left, right, false, 100.0, 1)
	_check(is_equal_approx(gate.left_health, 66.0), "34%门初始耐久为基准胃口的66%")
	_check(is_equal_approx(gate.right_health, 20.0), "左右门使用各自抽取百分位计算耐久")
	gate.receive_damage(true, 33.0)
	_check(is_equal_approx(left.value_ratio, 0.67), "打掉一半门耐久后百分位由34%提升到67%")
	_check(is_equal_approx(left.value, lerpf(0.05, 0.45, 0.67)), "门奖励随受击百分位实时映射")
	_check(is_equal_approx(gate.right_health, 20.0), "攻击左门不会改变右门")
	gate.receive_damage(true, 100.0)
	_check(left.is_at_maximum() and not gate.side_is_attackable(true), "门打空后达到区间上限并停止锁定")
	gate.free()

	var start_gate: UpgradeGate = UpgradeGate.new()
	start_gate.configure(null, left, right, true, 100.0, 2)
	_check(not start_gate.side_is_attackable(true), "开局食材门不可攻击")
	_check(start_gate.target_for_cart_x(200.0) == null, "开局食材门不进入自动目标池")
	start_gate.free()


func _test_timeline() -> void:
	var timeline: EncounterTimeline = load("res://data/timelines/vertical_slice.tres") as EncounterTimeline
	_check(timeline != null and timeline.is_valid(), "时间轴事件数量一致")
	_check(is_equal_approx(timeline.baseline_appetite_at(0.0), 32.0), "基准胃口曲线起点")
	_check(is_equal_approx(timeline.baseline_appetite_at(135.0), 80.0), "基准胃口曲线终点")
	_check(timeline.baseline_appetite_at(67.5) < 56.0, "基准胃口在中段保持加速增长形状")
	var gate_count: int = 0
	for event_text: String in timeline.event_ids:
		if event_text.begins_with("gate_"):
			gate_count += 1
	_check(gate_count == 12, "竖切片包含12道普通强化门")
	_check(timeline.event_ids.has("elite"), "时间轴包含精英")
	_check(timeline.event_ids.has("boss"), "时间轴包含Boss")
	var post_elite_gate_index: int = timeline.event_ids.find("gate_6")
	_check(post_elite_gate_index >= 0 and is_equal_approx(timeline.event_times[post_elite_gate_index], 86.0), "精英后首门提前衔接")


func _test_resources() -> void:
	var potato: FoodData = load("res://data/foods/potato.tres") as FoodData
	var baguette: FoodData = load("res://data/foods/baguette.tres") as FoodData
	var elite: CustomerData = load("res://data/customers/elite_guest.tres") as CustomerData
	_check(potato != null and is_equal_approx(potato.base_satisfaction, 10.0), "土豆基线")
	_check(potato.initial_aim_mode == FoodData.AimMode.FIXED_FORWARD, "土豆初始固定竖直发射")
	_check(potato.initial_tracking_mode == FoodData.TrackingMode.NONE, "土豆初始为直线非追踪弹道")
	_check(baguette != null and baguette.pierce_count == 3, "法棍穿透数")
	_check(baguette.initial_tracking_mode == FoodData.TrackingMode.NONE, "法棍初始不追踪")
	_check(elite != null and elite.occupied_regions == 6, "精英横跨六区")
	_check(elite != null and is_equal_approx(elite.appetite_multiplier, 5.625), "精英按食客基准胃口倍率生成")
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
