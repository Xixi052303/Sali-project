extends SceneTree

var _failures: int = 0


func _init() -> void:
	_test_playfield()
	_test_run_state()
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


func _test_timeline() -> void:
	var timeline: EncounterTimeline = load("res://data/timelines/vertical_slice.tres") as EncounterTimeline
	_check(timeline != null and timeline.is_valid(), "时间轴事件数量一致")
	var gate_count: int = 0
	for event_text: String in timeline.event_ids:
		if event_text.begins_with("gate_"):
			gate_count += 1
	_check(gate_count == 12, "竖切片包含12道普通强化门")
	_check(timeline.event_ids.has("elite"), "时间轴包含精英")
	_check(timeline.event_ids.has("boss"), "时间轴包含Boss")


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
