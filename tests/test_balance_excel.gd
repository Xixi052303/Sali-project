extends SceneTree

var _failures: int = 0


func _init() -> void:
	_test_timeline_workbook()
	_test_combat_rules_workbook()
	_test_customer_workbook()
	_test_weapon_workbook()
	_test_normal_upgrade_workbook()
	_test_special_upgrade_workbook()
	_test_invalid_customer_records()
	_test_missing_workbook_fallback_signal()
	if _failures == 0:
		print("BALANCE_EXCEL_TEST_OK")
		quit(0)
	else:
		push_error("BALANCE_EXCEL_TEST_FAILED count=%d" % _failures)
		quit(1)


func _test_timeline_workbook() -> void:
	var fallback: EncounterTimeline = load(
		"res://data/timelines/vertical_slice.tres"
	) as EncounterTimeline
	var result: TimelineExcelLoader.LoadResult = TimelineExcelLoader.load_from_excel(
		"res://balance_tables/时间轴.xlsx",
		fallback
	)
	_check(result.loaded_from_excel, "三段胃口时间轴 Schema 4 可读取")
	if result.timeline == null:
		return
	var timeline: EncounterTimeline = result.timeline
	_check(
		is_equal_approx(timeline.baseline_appetite_at_elapsed_seconds(0.0), 15.0)
		and is_equal_approx(timeline.baseline_appetite_at_elapsed_seconds(135.0), 350.0)
		and is_equal_approx(timeline.baseline_appetite_at_elapsed_seconds(300.0), 2825.0)
		and is_equal_approx(timeline.baseline_appetite_at_elapsed_seconds(480.0), 12000.0),
		"胃口按有效时间读取三段终点15、350、2825、12000"
	)
	_check(
		timeline.event_ids.count("elite") == 6
		and timeline.event_ids.count("boss") == 2
		and timeline.normal_gate_count == 50
		and timeline.normal_wave_count == 250
		and timeline.expected_normal_customer_count() == 312,
		"时间轴读取六精英、两Boss、50门、250波与312只普通食客"
	)
	var start_gate_index: int = timeline.event_ids.find("start_gate")
	_check(
		start_gate_index >= 0
		and is_equal_approx(timeline.event_progresses[start_gate_index], 0.01),
		"开局食材门从时间轴表读取总路程1%进度"
	)
	_check(
		is_equal_approx(timeline.course_distance, 1310.763)
		and timeline.forward_speed_multipliers == PackedFloat32Array([1.0, 1.1, 1.3, 1.7, 2.3, 3.0])
		and is_equal_approx(timeline.normal_wave_interval_jitter_ratio, 0.2)
		and is_equal_approx(timeline.max_crosswind_speed, 60.0)
		and is_equal_approx(timeline.minimum_cart_base_speed_factor, 0.8),
		"独立总路程、波次波动、六档压力、侧漂和疲劳参数由表读取"
	)
	var old_schema: TimelineExcelLoader.LoadResult = TimelineExcelLoader.load_from_excel(
		"res://tests/fixtures/timeline_schema_v1.xlsx",
		fallback
	)
	_check(
		old_schema.used_fallback
		and old_schema.timeline == fallback
		and old_schema.error_message.contains("schema_version"),
		"旧时间轴 Schema 整表回退"
	)


func _test_combat_rules_workbook() -> void:
	var result: GameplayExcelLoader.CombatRulesLoadResult = (
		GameplayExcelLoader.load_combat_rules("res://balance_tables/战斗规则.xlsx")
	)
	_check(result.loaded_from_excel, "战斗规则 Excel 可读取")
	_check(
		is_equal_approx(result.cart_invincibility_duration_seconds, 0.5),
		"餐车受击无敌时间由战斗规则表读取为0.5秒"
	)
	var invalid_result: GameplayExcelLoader.CombatRulesLoadResult = (
		GameplayExcelLoader._parse_combat_rule_values(
			{"cart_invincibility_duration_seconds": 0.0}
		)
	)
	_check(not invalid_result.loaded_from_excel, "非正无敌时间触发战斗规则回退")
	_check(
		is_equal_approx(
			invalid_result.cart_invincibility_duration_seconds,
			Cart3D.DEFAULT_INVINCIBILITY_DURATION_SECONDS
		),
		"战斗规则回退保持0.5秒安全值"
	)


func _test_customer_workbook() -> void:
	var result: GameplayExcelLoader.CustomerLoadResult = GameplayExcelLoader.load_customers(
		"res://balance_tables/食客.xlsx"
	)
	_check(result.loaded_from_excel, "食客 Excel 可读取")
	_check(result.customers.size() == 4, "食客 Excel 包含当前四类食客")
	var customers: Dictionary[StringName, CustomerData] = {}
	for customer: CustomerData in result.customers:
		customers[customer.id] = customer
	for required_id: StringName in [
		&"basic_guest",
		&"fast_guest",
		&"ranged_guest",
		&"elite_guest",
	]:
		_check(customers.has(required_id), "食客 Excel 必需ID齐全: %s" % String(required_id))
	if customers.size() != 4:
		return
	var basic: CustomerData = customers[&"basic_guest"]
	var fast: CustomerData = customers[&"fast_guest"]
	var ranged: CustomerData = customers[&"ranged_guest"]
	var elite: CustomerData = customers[&"elite_guest"]
	_check(basic.id == &"basic_guest" and not basic.display_name.is_empty(), "基础食客ID映射且显示名非空")
	_check(
		basic.customer_scene != null
		and basic.customer_scene.resource_path.ends_with("mouse_customer_3d.tscn"),
		"基础食客加载可预览小鼠场景"
	)
	_check(is_equal_approx(basic.appetite_multiplier, 1.0), "基础食客保持1.0倍胃口")
	_check(is_equal_approx(basic.move_speed, 42.0), "基础食客保持42px/s")
	_check(fast.id == &"fast_guest" and not fast.display_name.is_empty(), "快速食客ID映射且显示名非空")
	_check(
		fast.customer_scene != null
		and fast.customer_scene.resource_path.ends_with("fox_customer_3d.tscn"),
		"快速模板加载可预览狐狸场景"
	)
	_check(is_equal_approx(fast.appetite_multiplier, 0.75), "急脚食客保持0.75倍胃口")
	_check(is_equal_approx(fast.move_speed, 96.0), "急脚食客保持96px/s")
	_check(ranged.id == &"ranged_guest" and not ranged.display_name.is_empty(), "远程食客ID映射且显示名非空")
	_check(
		ranged.customer_scene != null
		and ranged.customer_scene.resource_path.ends_with("frog_customer_3d.tscn"),
		"远程模板加载可预览青蛙场景"
	)
	_check(
		ranged.category == CustomerData.Category.NORMAL
		and ranged.behavior == CustomerData.Behavior.RANGED,
		"拍桌食客由普通身份与远程行为组合"
	)
	_check(
		is_equal_approx(ranged.attack_ratio, 0.08)
		and is_equal_approx(ranged.attack_interval, 3.4),
		"拍桌食客保持当前远程攻击参数"
	)
	_check(
		elite.category == CustomerData.Category.ELITE
		and elite.behavior == CustomerData.Behavior.NONE,
		"六席贵客由精英身份与无行为组合"
	)
	_check(
		elite.customer_scene != null
		and elite.customer_scene.resource_path.ends_with("elite_customer_3d.tscn"),
		"六席贵客加载独立可预览场景"
	)
	_check(is_zero_approx(elite.move_speed) and elite.occupied_regions == 6, "精英不主动移动并横跨六区")


func _test_weapon_workbook() -> void:
	var result: GameplayExcelLoader.WeaponLoadResult = GameplayExcelLoader.load_weapons(
		"res://balance_tables/武器.xlsx"
	)
	_check(result.loaded_from_excel, "武器 Excel 可读取")
	_check(result.foods.size() >= 5, "武器 Excel 包含当前五件食材")
	_check(
		result.egg_puddle_data != null
		and result.egg_puddle_data.attack_kind == FoodData.AttackKind.EGG_PUDDLE,
		"武器衍生攻击表包含独立蛋液配置"
	)
	var ids: Array[StringName] = []
	var foods: Dictionary[StringName, FoodData] = {}
	for food: FoodData in result.foods:
		ids.append(food.id)
		foods[food.id] = food
		_check(food.base_satisfaction > 0.0, "武器基础满足为正数")
		_check(food.base_interval > 0.0, "武器基础间隔为正数")
		_check(food.attack_speed_upgrade_scale >= 0.0, "食材攻速强化倍率有效")
		_check(food.wine_upgrade_scale >= 0.0, "食材酒强化倍率有效")
		_check(food.range_upgrade_scale >= 0.0, "食材范围强化倍率有效")
		_check(food.duration_upgrade_scale >= 0.0, "食材持续强化倍率有效")
	_check(
		ids.has(&"potato")
		and ids.has(&"baguette")
		and ids.has(&"mushroom")
		and ids.has(&"egg")
		and ids.has(&"carrot"),
		"当前五件食材ID齐全"
	)
	if foods.size() >= 5:
		var potato: FoodData = foods[&"potato"]
		var baguette: FoodData = foods[&"baguette"]
		var mushroom: FoodData = foods[&"mushroom"]
		var egg: FoodData = foods[&"egg"]
		var carrot: FoodData = foods[&"carrot"]
		_check(
			is_equal_approx(potato.base_satisfaction, 10.0)
			and is_equal_approx(potato.base_interval, 0.8)
			and is_equal_approx(potato.projectile_speed, 680.0)
			and is_equal_approx(potato.base_lifetime, 1.3473684),
			"土豆从武器表读取当前基础输出与约0.72屏射程参数"
		)
		_check(
			is_equal_approx(baguette.base_satisfaction, 10.0)
			and is_equal_approx(baguette.base_interval, 1.0)
			and is_equal_approx(baguette.projectile_speed, 2000.0)
			and is_equal_approx(baguette.base_lifetime, 0.5),
			"法棍从武器表读取当前10点DPS与约0.78屏射程参数"
		)
		_check(
			is_equal_approx(potato.wine_upgrade_scale, 0.35)
			and is_equal_approx(potato.range_upgrade_scale, 1.0)
			and is_equal_approx(potato.duration_upgrade_scale, 0.2),
			"土豆按1/0.35/1/0.2转译四项输出强化"
		)
		_check(
			is_equal_approx(baguette.wine_upgrade_scale, 0.35)
			and is_equal_approx(baguette.range_upgrade_scale, 1.0)
			and is_equal_approx(baguette.duration_upgrade_scale, 0.25),
			"法棍按1/0.35/1/0.25转译四项输出强化"
		)
		_check(
			is_equal_approx(baguette.targeting_half_angle_degrees, 30.0),
			"法棍从武器表读取30度寻敌半角"
		)
		_check(
			is_equal_approx(potato.targeting_half_angle_degrees, 90.0)
			and is_equal_approx(mushroom.targeting_half_angle_degrees, 90.0),
			"其他当前食材不额外收窄前方寻敌范围"
		)
		_check(
			is_equal_approx(mushroom.wine_upgrade_scale, 1.0)
			and is_equal_approx(mushroom.range_upgrade_scale, 0.5)
			and is_equal_approx(mushroom.duration_upgrade_scale, 0.15),
			"蘑菇按1/1/0.5/0.15转译四项输出强化"
		)
		_check(is_equal_approx(mushroom.orbit_angular_speed, 4.0), "蘑菇初始一圈按π/2秒读取4rad/s")
		_check(
			egg.attack_kind == FoodData.AttackKind.EGG_PROJECTILE
			and is_equal_approx(egg.base_interval, potato.base_interval)
			and is_equal_approx(egg.projectile_speed, potato.projectile_speed),
			"鸡蛋主行使用土豆基础值"
		)
		_check(
			result.egg_puddle_data != null
			and is_equal_approx(result.egg_puddle_data.base_satisfaction, egg.base_satisfaction)
			and is_equal_approx(result.egg_puddle_data.base_interval, 0.5)
			and is_equal_approx(result.egg_puddle_data.projectile_radius, egg.projectile_radius)
			and is_equal_approx(result.egg_puddle_data.base_lifetime, egg.base_lifetime)
			and is_equal_approx(
				result.egg_puddle_data.attack_speed_upgrade_scale,
				egg.attack_speed_upgrade_scale
			)
			and is_equal_approx(result.egg_puddle_data.wine_upgrade_scale, egg.wine_upgrade_scale)
			and is_equal_approx(result.egg_puddle_data.range_upgrade_scale, egg.range_upgrade_scale)
			and is_equal_approx(
				result.egg_puddle_data.duration_upgrade_scale,
				egg.duration_upgrade_scale
			),
			"蛋液衍生行只覆盖节拍与输出倍率，其余属性和强化倍率继承鸡蛋"
		)
		_check(
			carrot.attack_kind == FoodData.AttackKind.CARROT_SWEEP
			and carrot.pierce_count == 999
			and is_equal_approx(carrot.projectile_speed, 680.0)
			and is_equal_approx(carrot.base_lifetime, 0.5)
			and is_equal_approx(carrot.orbit_angular_speed, 6.2831853, 0.000001)
			and is_equal_approx(carrot.sweep_radius, 458.1053)
			and is_equal_approx(carrot.sweep_angle_degrees, 180.0),
			"胡萝卜从武器表读取环绕角速度、0.5秒持续、999穿透和180度扫掠"
		)
	_check(is_equal_approx(result.baguette_giant_interval_seconds, 3.0), "巨型法棍间隔由武器表读取")
	_check(is_equal_approx(result.baguette_giant_attack_speed_scale, 0.05), "巨型法棍攻速倍率由武器表读取")
	_check(is_equal_approx(result.baguette_giant_minimum_interval_seconds, 1.0), "巨型法棍最小间隔由武器表读取")
	_check(is_equal_approx(result.baguette_giant_width_regions, 4.0), "巨型法棍宽度由武器表读取")
	_check(result.baguette_giant_pierce_count == 999, "巨型法棍穿透由武器表读取")
	_check(is_equal_approx(result.baguette_giant_duration_multiplier, 1.5), "巨型法棍持续倍率由武器表读取")
	_check(is_equal_approx(result.baguette_giant_satisfaction_multiplier, 3.0), "巨型法棍满足倍率由武器表读取")


func _test_normal_upgrade_workbook() -> void:
	var result: GameplayExcelLoader.NormalUpgradeLoadResult = (
		GameplayExcelLoader.load_normal_upgrades("res://balance_tables/普通强化.xlsx")
	)
	_check(result.loaded_from_excel, "普通强化 Excel 可读取")
	_check(result.upgrades.size() == 8, "普通门与食客奖励共用八项候选池")
	_check(
		is_equal_approx(result.reward_effect_scale, 0.4)
		and is_equal_approx(result.wine_curve_c, 1.0)
		and is_equal_approx(result.range_curve_c, 4.0)
		and is_equal_approx(result.duration_curve_c, 1.0)
		and is_equal_approx(result.cart_speed_curve_c, 0.5),
		"小份奖励与四项对数曲线参数由普通强化表读取"
	)
	var expected_ranges: Dictionary[int, Vector2] = {
		UpgradeData.Kind.SUGAR: Vector2(0.05, 0.30),
		UpgradeData.Kind.QUICK_PREP: Vector2(0.05, 0.30),
		UpgradeData.Kind.WINE: Vector2(0.10, 0.50),
		UpgradeData.Kind.SCALLION: Vector2(0.10, 0.60),
		UpgradeData.Kind.STARCH: Vector2(0.15, 0.75),
		UpgradeData.Kind.LIGHT_CART: Vector2(50.0, 300.0),
		UpgradeData.Kind.STURDY_CART: Vector2(0.02, 0.11),
		UpgradeData.Kind.REPAIR: Vector2(0.12, 0.55),
	}
	for upgrade: UpgradeData in result.upgrades:
		_check(upgrade.uses_value_range, "共用候选使用可成长区间")
		_check(upgrade.maximum_value >= upgrade.minimum_value, "共用候选数值区间有效")
		_check(not upgrade.effect_text_template.is_empty(), "共用候选文案模板由 Excel 提供")
		var rendered_text: String = upgrade.effect_text()
		_check(not rendered_text.is_empty(), "共用候选文案模板可以生成实际门牌文本")
		_check(not rendered_text.contains("{"), "共用候选文案占位符已替换")
		var expected_range: Vector2 = expected_ranges[upgrade.kind]
		_check(
			is_equal_approx(upgrade.minimum_value, expected_range.x)
			and is_equal_approx(upgrade.maximum_value, expected_range.y),
			"%s读取正式首轮数值区间" % upgrade.display_name
		)
		if upgrade.kind == UpgradeData.Kind.STURDY_CART:
			_check(rendered_text == "耐久上限 +2点", "餐车改造门牌按当前上限显示实际耐久点数")


func _test_special_upgrade_workbook() -> void:
	var result: GameplayExcelLoader.SpecialUpgradeLoadResult = (
		GameplayExcelLoader.load_special_upgrades("res://balance_tables/特殊强化.xlsx")
	)
	_check(result.loaded_from_excel, "特殊强化 Excel 可读取")
	_check(result.upgrades.size() >= 3, "特殊候选池至少可以组成三选一")
	_check(result.upgrades.size() == 11, "特殊强化 Excel 当前包含十一项候选")
	_check(result.food_max_level >= 1, "食材最高等级有效")
	_check(is_equal_approx(result.food_level_satisfaction_multiplier, 2.25), "食材等级倍率为2.25")
	var giant_upgrade_found: bool = false
	var egg_card_found: bool = false
	var carrot_card_found: bool = false
	var carrot_bounce_found: bool = false
	for upgrade: SpecialUpgradeData in result.upgrades:
		if upgrade.id == &"baguette_giant":
			giant_upgrade_found = true
		if upgrade.id == &"egg":
			egg_card_found = true
		if upgrade.id == &"carrot":
			carrot_card_found = true
		if upgrade.id == &"carrot_bounce":
			carrot_bounce_found = (
				upgrade.effect_kind == SpecialUpgradeData.EffectKind.EVOLUTION
				and upgrade.target_id == &"carrot"
				and not upgrade.repeatable
			)
	_check(giant_upgrade_found, "特殊候选池包含巨型法棍进化")
	_check(egg_card_found and carrot_card_found, "特殊候选池包含鸡蛋和胡萝卜食材卡")
	_check(carrot_bounce_found, "特殊候选池包含胡萝卜往返扫掠进化")
	var food_result: GameplayExcelLoader.WeaponLoadResult = GameplayExcelLoader.load_weapons(
		"res://balance_tables/武器.xlsx"
	)
	if food_result.foods.is_empty():
		return
	var food: FoodData = food_result.foods[0]
	var state: RunState = RunState.new()
	state.food_max_level = result.food_max_level
	state.food_level_satisfaction_multiplier = result.food_level_satisfaction_multiplier
	state.add_food(food.id)
	var level_one_value: float = state.effective_satisfaction(food)
	state.level_food(food.id)
	_check(
		is_equal_approx(
			state.effective_satisfaction(food),
			level_one_value * result.food_level_satisfaction_multiplier
		),
		"特殊强化表等级倍率进入 RunState 计算"
	)


func _test_invalid_customer_records() -> void:
	var invalid_records: Array[Dictionary] = [
		{
			"启用": true,
			"食客ID": "",
			"显示名称": "空ID",
			"身份层级": "普通",
			"行为类型": "无",
			"胃口倍率": 1.0,
			"移动速度(px/s)": 42,
			"占据区域数": 2,
			"颜色HEX": "#63784F",
		},
		{
			"启用": true,
			"食客ID": "basic_guest",
			"显示名称": "饿肚食客",
			"身份层级": "未知",
			"行为类型": "突进",
			"胃口倍率": 0.0,
			"移动速度(px/s)": -1,
			"占据区域数": 7,
			"攻击强度比例": 0.1,
			"攻击间隔(s)": 1.0,
			"颜色HEX": "坏颜色",
		},
		{
			"启用": true,
			"食客ID": "basic_guest",
			"显示名称": "重复ID",
			"身份层级": "普通",
			"行为类型": "无",
			"胃口倍率": 1.0,
			"移动速度(px/s)": 42,
			"占据区域数": 2,
			"颜色HEX": "#63784F",
		},
	]
	var invalid_result: GameplayExcelLoader.CustomerLoadResult = (
		GameplayExcelLoader._parse_customer_records(invalid_records)
	)
	_check(not invalid_result.loaded_from_excel, "非法食客记录不会部分加载")
	_check(invalid_result.customers.is_empty(), "非法食客记录触发整表清空")
	for expected_message: String in [
		"食客ID不能为空",
		"食客ID重复",
		"身份层级不受支持",
		"行为类型不受支持",
		"胃口倍率必须大于0",
		"移动速度不能为负数",
		"占据区域数必须是1至6的整数",
		"颜色HEX无效",
		"攻击字段必须留空",
		"缺少已启用的必需食客ID",
	]:
		_check(
			invalid_result.error_message.contains(expected_message),
			"食客表错误信息包含: %s" % expected_message
		)
	var wrong_schema: GameplayExcelLoader.CustomerLoadResult = GameplayExcelLoader.load_customers(
		"res://balance_tables/武器.xlsx"
	)
	_check(
		not wrong_schema.loaded_from_excel and wrong_schema.error_message.contains("schema_id"),
		"错误结构标识触发食客表回退"
	)
	var missing_sheet: GameplayExcelLoader.CustomerLoadResult = GameplayExcelLoader.load_customers(
		"res://tests/fixtures/customer_missing_sheet.xlsx"
	)
	_check(
		not missing_sheet.loaded_from_excel
		and missing_sheet.error_message.contains("必须包含“食客”工作表"),
		"缺少食客工作表时触发整体回退"
	)


func _test_missing_workbook_fallback_signal() -> void:
	var combat_result: GameplayExcelLoader.CombatRulesLoadResult = (
		GameplayExcelLoader.load_combat_rules("res://balance_tables/__missing__.xlsx")
	)
	_check(
		not combat_result.loaded_from_excel
		and is_equal_approx(
			combat_result.cart_invincibility_duration_seconds,
			Cart3D.DEFAULT_INVINCIBILITY_DURATION_SECONDS
		)
		and not combat_result.error_message.is_empty(),
		"战斗规则表缺失时返回0.5秒安全回退"
	)
	var weapon_result: GameplayExcelLoader.WeaponLoadResult = GameplayExcelLoader.load_weapons(
		"res://balance_tables/__missing__.xlsx"
	)
	_check(not weapon_result.loaded_from_excel and not weapon_result.error_message.is_empty(), "缺失工作簿返回可诊断错误")
	var customer_result: GameplayExcelLoader.CustomerLoadResult = GameplayExcelLoader.load_customers(
		"res://balance_tables/__missing__.xlsx"
	)
	_check(
		not customer_result.loaded_from_excel
		and customer_result.customers.is_empty()
		and not customer_result.error_message.is_empty(),
		"食客表缺失时返回整体回退信号"
	)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("TEST FAILED: %s" % message)
