extends SceneTree

var _failures: int = 0


func _init() -> void:
	_test_timeline_workbook()
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
	_check(result.loaded_from_excel, "时间轴 Schema 2 可读取")
	if result.timeline == null:
		return
	var timeline: EncounterTimeline = result.timeline
	var checkpoints: Dictionary[float, float] = {
		0.0: 15.0,
		135.0: 350.0,
		180.0: 554.0,
		210.0: 746.0,
		270.0: 1200.0,
		300.0: 1200.0,
	}
	for checkpoint_time: float in checkpoints:
		_check(
			is_equal_approx(
				timeline.baseline_appetite_at(checkpoint_time),
				checkpoints[checkpoint_time]
			),
			"时间轴 %.0fs 基准胃口为 %.0f" % [
				checkpoint_time,
				checkpoints[checkpoint_time],
			]
		)
	_check(
		is_equal_approx(timeline.normal_wave_interval_at(77.999), 3.2)
		and is_equal_approx(timeline.normal_wave_interval_at(78.0), 2.8),
		"78秒边界进入普通波次中段"
	)
	_check(
		is_equal_approx(timeline.normal_wave_interval_at(134.999), 2.8)
		and is_equal_approx(timeline.normal_wave_interval_at(135.0), 3.2),
		"135秒边界进入普通波次晚段"
	)
	_check(
		is_equal_approx(timeline.normal_wave_start_time, 8.0)
		and is_equal_approx(timeline.normal_wave_end_time, 360.0),
		"普通波次起止时间来自时间轴"
	)
	for fixture: Dictionary in [
		{
			"path": "res://tests/fixtures/timeline_schema_v1.xlsx",
			"error": "schema_version",
			"message": "Schema 1 整表回退",
		},
		{
			"path": "res://tests/fixtures/timeline_missing_late.xlsx",
			"error": "baseline_appetite_late_end",
			"message": "缺少晚段字段整表回退",
		},
		{
			"path": "res://tests/fixtures/timeline_invalid_order.xlsx",
			"error": "必须晚于",
			"message": "时间顺序倒置整表回退",
		},
		{
			"path": "res://tests/fixtures/timeline_zero_interval.xlsx",
			"error": "必须大于 0",
			"message": "非正波次间隔整表回退",
		},
	]:
		var fixture_path: String = str(fixture["path"])
		var expected_error: String = str(fixture["error"])
		var fixture_message: String = str(fixture["message"])
		var invalid_result: TimelineExcelLoader.LoadResult = TimelineExcelLoader.load_from_excel(
			fixture_path,
			fallback
		)
		_check(
			invalid_result.used_fallback
			and invalid_result.timeline == fallback
			and invalid_result.error_message.contains(expected_error),
			fixture_message
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
	_check(is_equal_approx(basic.appetite_multiplier, 1.0), "基础食客保持1.0倍胃口")
	_check(is_equal_approx(basic.move_speed, 42.0), "基础食客保持42px/s")
	_check(is_equal_approx(fast.appetite_multiplier, 0.75), "急脚食客保持0.75倍胃口")
	_check(is_equal_approx(fast.move_speed, 96.0), "急脚食客保持96px/s")
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
	_check(is_equal_approx(elite.move_speed, 18.0) and elite.occupied_regions == 6, "精英保持当前速度与六区占位")


func _test_weapon_workbook() -> void:
	var result: GameplayExcelLoader.WeaponLoadResult = GameplayExcelLoader.load_weapons(
		"res://balance_tables/武器.xlsx"
	)
	_check(result.loaded_from_excel, "武器 Excel 可读取")
	_check(result.foods.size() >= 3, "武器 Excel 至少包含当前三件食材")
	var ids: Array[StringName] = []
	for food: FoodData in result.foods:
		ids.append(food.id)
		_check(food.base_satisfaction > 0.0, "武器基础满足为正数")
		_check(food.base_interval > 0.0, "武器基础间隔为正数")
	_check(ids.has(&"potato") and ids.has(&"baguette") and ids.has(&"mushroom"), "当前三件食材ID齐全")


func _test_normal_upgrade_workbook() -> void:
	var result: GameplayExcelLoader.NormalUpgradeLoadResult = (
		GameplayExcelLoader.load_normal_upgrades("res://balance_tables/普通强化.xlsx")
	)
	_check(result.loaded_from_excel, "普通强化 Excel 可读取")
	_check(result.upgrades.size() >= 2, "普通门与食客奖励共用池至少有两个候选")
	for upgrade: UpgradeData in result.upgrades:
		_check(upgrade.uses_value_range, "共用候选使用可成长区间")
		_check(upgrade.maximum_value >= upgrade.minimum_value, "共用候选数值区间有效")
		_check(not upgrade.effect_text_template.is_empty(), "共用候选文案模板由 Excel 提供")
		var rendered_text: String = upgrade.effect_text()
		_check(not rendered_text.is_empty(), "共用候选文案模板可以生成实际门牌文本")
		_check(not rendered_text.contains("{"), "共用候选文案占位符已替换")


func _test_special_upgrade_workbook() -> void:
	var result: GameplayExcelLoader.SpecialUpgradeLoadResult = (
		GameplayExcelLoader.load_special_upgrades("res://balance_tables/特殊强化.xlsx")
	)
	_check(result.loaded_from_excel, "特殊强化 Excel 可读取")
	_check(result.upgrades.size() >= 3, "特殊候选池至少可以组成三选一")
	_check(result.food_max_level >= 1, "食材最高等级有效")
	_check(result.food_level_satisfaction_multiplier > 0.0, "食材等级倍率有效")
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
