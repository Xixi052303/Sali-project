extends SceneTree

var _failures: int = 0


func _init() -> void:
	_test_weapon_workbook()
	_test_normal_upgrade_workbook()
	_test_special_upgrade_workbook()
	_test_missing_workbook_fallback_signal()
	if _failures == 0:
		print("BALANCE_EXCEL_TEST_OK")
		quit(0)
	else:
		push_error("BALANCE_EXCEL_TEST_FAILED count=%d" % _failures)
		quit(1)


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
	_check(result.gate_upgrades.size() >= 2, "普通门至少有两个候选")
	_check(not result.reward_upgrades.is_empty(), "食客奖励门至少有一个候选")
	for upgrade: UpgradeData in result.gate_upgrades:
		_check(upgrade.uses_value_range, "普通门候选使用可成长区间")
		_check(upgrade.maximum_value >= upgrade.minimum_value, "普通门数值区间有效")


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


func _test_missing_workbook_fallback_signal() -> void:
	var weapon_result: GameplayExcelLoader.WeaponLoadResult = GameplayExcelLoader.load_weapons(
		"res://balance_tables/__missing__.xlsx"
	)
	_check(not weapon_result.loaded_from_excel and not weapon_result.error_message.is_empty(), "缺失工作簿返回可诊断错误")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("TEST FAILED: %s" % message)
