class_name GameplayExcelLoader
extends RefCounted

const CONFIG_SHEET: String = "配置"
const EXPECTED_SCHEMA_VERSION: int = 1
const REQUIRED_CUSTOMER_IDS: Array[StringName] = [
	&"basic_guest",
	&"fast_guest",
	&"ranged_guest",
	&"elite_guest",
]
# 场景保存完整可预览视觉，Excel只选择既有模板，不在运行时拼装模型。
const CUSTOMER_SCENES: Dictionary[StringName, PackedScene] = {
	&"basic_guest": preload("res://scenes/characters/customers/mouse_customer_3d.tscn"),
	&"fast_guest": preload("res://scenes/characters/customers/fox_customer_3d.tscn"),
	&"ranged_guest": preload("res://scenes/characters/customers/frog_customer_3d.tscn"),
	&"elite_guest": preload("res://scenes/characters/customers/elite_customer_3d.tscn"),
}


class WeaponLoadResult:
	extends RefCounted

	var foods: Array[FoodData] = []
	var loaded_from_excel: bool = false
	var error_message: String = ""
	var source_path: String = ""


class CustomerLoadResult:
	extends RefCounted

	var customers: Array[CustomerData] = []
	var loaded_from_excel: bool = false
	var error_message: String = ""
	var source_path: String = ""


class NormalUpgradeLoadResult:
	extends RefCounted

	var upgrades: Array[UpgradeData] = []
	var loaded_from_excel: bool = false
	var error_message: String = ""
	var source_path: String = ""


class SpecialUpgradeLoadResult:
	extends RefCounted

	var upgrades: Array[SpecialUpgradeData] = []
	var food_max_level: int = RunState.FOOD_MAX_LEVEL
	var food_level_satisfaction_multiplier: float = RunState.FOOD_LEVEL_SATISFACTION_MULTIPLIER
	var baguette_giant_interval_seconds: float = RunState.BAGUETTE_GIANT_INTERVAL_SECONDS
	var baguette_giant_width_regions: float = RunState.BAGUETTE_GIANT_WIDTH_REGIONS
	var baguette_giant_pierce_count: int = RunState.BAGUETTE_GIANT_PIERCE_COUNT
	var baguette_giant_duration_multiplier: float = RunState.BAGUETTE_GIANT_DURATION_MULTIPLIER
	var baguette_giant_satisfaction_multiplier: float = RunState.BAGUETTE_GIANT_SATISFACTION_MULTIPLIER
	var loaded_from_excel: bool = false
	var error_message: String = ""
	var source_path: String = ""


class WorkbookReadResult:
	extends RefCounted

	var workbook: ExcelReader47.ExcelWorkbook
	var error_message: String = ""


# 读取食客主表并生成本局独立的 CustomerData；任一必需行非法时整表失败。
static func load_customers(path: String) -> CustomerLoadResult:
	var result: CustomerLoadResult = CustomerLoadResult.new()
	result.source_path = path
	var read_result: WorkbookReadResult = _read_valid_workbook(path, "xiaochuxi.customers")
	if read_result.workbook == null:
		result.error_message = read_result.error_message
		return result
	var sheet: ExcelReader47.ExcelSheet = read_result.workbook.get_sheet_by_name("食客")
	if sheet == null:
		return _customer_failure(result, "食客 Excel 必须包含“食客”工作表")
	return _parse_customer_records(sheet.to_records(), result)


# 独立解析记录，便于对全行校验与整体回退规则做无文件单元测试。
static func _parse_customer_records(
	records: Array[Dictionary],
	result: CustomerLoadResult = null
) -> CustomerLoadResult:
	if result == null:
		result = CustomerLoadResult.new()
	var errors: PackedStringArray = []
	var seen_ids: Dictionary[StringName, bool] = {}
	var row_number: int = 1
	for record: Dictionary in records:
		row_number += 1
		if not _as_bool(record.get("启用", true)):
			continue
		var customer_id: StringName = StringName(str(record.get("食客ID", "")).strip_edges())
		if customer_id.is_empty():
			errors.append("食客表第 %d 行食客ID不能为空" % row_number)
			continue
		if seen_ids.has(customer_id):
			errors.append("食客表第 %d 行食客ID重复: %s" % [row_number, String(customer_id)])
			continue
		seen_ids[customer_id] = true
		var customer: CustomerData = CustomerData.new()
		customer.id = customer_id
		customer.display_name = str(record.get("显示名称", "")).strip_edges()
		customer.customer_scene = CUSTOMER_SCENES.get(customer_id) as PackedScene
		customer.category = _customer_category(record.get("身份层级"), row_number, errors)
		customer.behavior = _customer_behavior(record.get("行为类型"), row_number, errors)
		customer.appetite_multiplier = _required_number(
			record,
			"胃口倍率",
			row_number,
			errors,
			"食客"
		)
		customer.move_speed = _required_number(
			record,
			"移动速度(px/s)",
			row_number,
			errors,
			"食客"
		)
		var occupied_value: float = _required_number(
			record,
			"占据区域数",
			row_number,
			errors,
			"食客"
		)
		customer.occupied_regions = int(occupied_value)
		var color_text: String = str(record.get("颜色HEX", "")).strip_edges()
		if Color.html_is_valid(color_text):
			customer.body_color = Color.from_string(color_text, Color.WHITE)
		else:
			errors.append("食客表第 %d 行颜色HEX无效: %s" % [row_number, color_text])
		if customer.display_name.is_empty():
			errors.append("食客表第 %d 行显示名称不能为空" % row_number)
		if customer.appetite_multiplier <= 0.0:
			errors.append("食客表第 %d 行胃口倍率必须大于0" % row_number)
		if customer.move_speed < 0.0:
			errors.append("食客表第 %d 行移动速度不能为负数" % row_number)
		if (
			occupied_value < 1.0
			or occupied_value > 6.0
			or not is_equal_approx(occupied_value, roundf(occupied_value))
		):
			errors.append("食客表第 %d 行占据区域数必须是1至6的整数" % row_number)
		if customer.behavior == CustomerData.Behavior.RANGED:
			customer.attack_ratio = _required_number(
				record,
				"攻击强度比例",
				row_number,
				errors,
				"食客"
			)
			customer.attack_interval = _required_number(
				record,
				"攻击间隔(s)",
				row_number,
				errors,
				"食客"
			)
			if customer.attack_ratio <= 0.0 or customer.attack_interval <= 0.0:
				errors.append("食客表第 %d 行远程攻击比例和间隔必须大于0" % row_number)
		else:
			if (
				not _is_blank(record.get("攻击强度比例"))
				or not _is_blank(record.get("攻击间隔(s)"))
			):
				errors.append("食客表第 %d 行无行为食客的攻击字段必须留空" % row_number)
			customer.attack_ratio = 0.0
			customer.attack_interval = 3.0
		result.customers.append(customer)
	for required_id: StringName in REQUIRED_CUSTOMER_IDS:
		if not seen_ids.has(required_id):
			errors.append("食客表缺少已启用的必需食客ID: %s" % String(required_id))
	if not errors.is_empty():
		return _customer_failure(result, "；".join(errors))
	result.loaded_from_excel = true
	return result


# 读取武器主表并生成本局独立的 FoodData，避免改写场景共享 Resource。
static func load_weapons(path: String) -> WeaponLoadResult:
	var result: WeaponLoadResult = WeaponLoadResult.new()
	result.source_path = path
	var read_result: WorkbookReadResult = _read_valid_workbook(path, "xiaochuxi.weapons")
	if read_result.workbook == null:
		result.error_message = read_result.error_message
		return result
	var workbook: ExcelReader47.ExcelWorkbook = read_result.workbook
	var sheet: ExcelReader47.ExcelSheet = workbook.get_sheet_by_name("武器")
	if sheet == null:
		return _weapon_failure(result, "武器 Excel 必须包含“武器”工作表")
	var errors: PackedStringArray = []
	var seen_ids: Dictionary[StringName, bool] = {}
	var row_number: int = 1
	for record: Dictionary in sheet.to_records():
		row_number += 1
		var food_id: StringName = StringName(str(record.get("食材ID", "")).strip_edges())
		if food_id.is_empty():
			errors.append("武器表第 %d 行食材ID不能为空" % row_number)
			continue
		if seen_ids.has(food_id):
			errors.append("武器表第 %d 行食材ID重复: %s" % [row_number, String(food_id)])
			continue
		seen_ids[food_id] = true
		var food: FoodData = FoodData.new()
		food.id = food_id
		food.display_name = str(record.get("显示名称", "")).strip_edges()
		food.attack_kind = _attack_kind(record.get("攻击类型"), row_number, errors)
		food.initial_aim_mode = _aim_mode(record.get("初始瞄准"), row_number, errors)
		food.initial_tracking_mode = _tracking_mode(record.get("初始追踪"), row_number, errors)
		food.base_satisfaction = _required_number(record, "基础满足", row_number, errors)
		food.base_interval = _required_number(record, "基础间隔(s)", row_number, errors)
		food.projectile_speed = _required_number(record, "弹速(px/s)", row_number, errors)
		food.projectile_radius = _required_number(record, "碰撞半径(px)", row_number, errors)
		food.base_lifetime = _required_number(record, "持续时间(s)", row_number, errors)
		food.pierce_count = int(_required_number(record, "命中目标数", row_number, errors))
		food.homing_turn_speed = _required_number(record, "追踪转向速度", row_number, errors)
		food.orbit_radius = _required_number(record, "环绕半径(px)", row_number, errors)
		food.orbit_angular_speed = _required_number(record, "环绕角速度(rad/s)", row_number, errors)
		food.breathing_period = _required_number(record, "呼吸周期(s)", row_number, errors)
		food.breathing_outer_multiplier = _required_number(record, "呼吸外圈倍率", row_number, errors)
		food.visual_color = Color.from_string(str(record.get("颜色HEX", "")), Color.WHITE)
		if food.display_name.is_empty():
			errors.append("武器表第 %d 行显示名称不能为空" % row_number)
		if food.base_satisfaction <= 0.0:
			errors.append("武器表第 %d 行基础满足必须大于0" % row_number)
		if food.base_interval <= 0.0:
			errors.append("武器表第 %d 行基础间隔必须大于0" % row_number)
		if food.projectile_radius <= 0.0 or food.base_lifetime <= 0.0:
			errors.append("武器表第 %d 行碰撞半径和持续时间必须大于0" % row_number)
		if food.pierce_count < 1:
			errors.append("武器表第 %d 行命中目标数至少为1" % row_number)
		if food.attack_kind == FoodData.AttackKind.ORBITING_MUSHROOM:
			if food.orbit_radius <= 0.0 or food.orbit_angular_speed <= 0.0:
				errors.append("武器表第 %d 行环绕武器的半径和角速度必须大于0" % row_number)
		result.foods.append(food)
	if result.foods.is_empty():
		errors.append("武器表至少需要一条有效数据")
	if not errors.is_empty():
		return _weapon_failure(result, "；".join(errors))
	result.loaded_from_excel = true
	return result


# 普通门与食客奖励门共用同一候选池，每个实际选项仍由运行时独立抽百分位。
static func load_normal_upgrades(path: String) -> NormalUpgradeLoadResult:
	var result: NormalUpgradeLoadResult = NormalUpgradeLoadResult.new()
	result.source_path = path
	var read_result: WorkbookReadResult = _read_valid_workbook(path, "xiaochuxi.normal_upgrades")
	if read_result.workbook == null:
		result.error_message = read_result.error_message
		return result
	var workbook: ExcelReader47.ExcelWorkbook = read_result.workbook
	var gate_sheet: ExcelReader47.ExcelSheet = workbook.get_sheet_by_name("普通门")
	if gate_sheet == null:
		return _normal_failure(result, "普通强化 Excel 必须包含“普通门”工作表")
	var errors: PackedStringArray = []
	result.upgrades = _parse_upgrade_sheet(gate_sheet, "普通门", errors)
	if result.upgrades.size() < 2:
		errors.append("普通门与食客奖励共用池至少需要启用两项强化")
	if not errors.is_empty():
		return _normal_failure(result, "；".join(errors))
	result.loaded_from_excel = true
	return result


# 读取特殊候选及全局等级规则；效果类型只允许项目明确支持的固定集合。
static func load_special_upgrades(path: String) -> SpecialUpgradeLoadResult:
	var result: SpecialUpgradeLoadResult = SpecialUpgradeLoadResult.new()
	result.source_path = path
	var read_result: WorkbookReadResult = _read_valid_workbook(
		path,
		"xiaochuxi.special_upgrades",
		"全局规则"
	)
	if read_result.workbook == null:
		result.error_message = read_result.error_message
		return result
	var workbook: ExcelReader47.ExcelWorkbook = read_result.workbook
	var rules_sheet: ExcelReader47.ExcelSheet = workbook.get_sheet_by_name("全局规则")
	var upgrades_sheet: ExcelReader47.ExcelSheet = workbook.get_sheet_by_name("特殊强化")
	if rules_sheet == null or upgrades_sheet == null:
		return _special_failure(result, "特殊强化 Excel 必须包含“全局规则”和“特殊强化”工作表")
	var errors: PackedStringArray = []
	var rules: Dictionary = _records_to_values(rules_sheet)
	result.food_max_level = int(_required_dictionary_number(rules, "food_max_level", errors))
	result.food_level_satisfaction_multiplier = _required_dictionary_number(
		rules,
		"food_level_satisfaction_multiplier",
		errors
	)
	result.baguette_giant_interval_seconds = _required_dictionary_number(
		rules,
		"baguette_giant_interval_seconds",
		errors
	)
	result.baguette_giant_width_regions = _required_dictionary_number(
		rules,
		"baguette_giant_width_regions",
		errors
	)
	var baguette_giant_pierce_value: float = _required_dictionary_number(
		rules,
		"baguette_giant_pierce_count",
		errors
	)
	result.baguette_giant_pierce_count = int(baguette_giant_pierce_value)
	result.baguette_giant_duration_multiplier = _required_dictionary_number(
		rules,
		"baguette_giant_duration_multiplier",
		errors
	)
	result.baguette_giant_satisfaction_multiplier = _required_dictionary_number(
		rules,
		"baguette_giant_satisfaction_multiplier",
		errors
	)
	if result.food_max_level < 1:
		errors.append("food_max_level 必须至少为1")
	if result.food_level_satisfaction_multiplier <= 0.0:
		errors.append("food_level_satisfaction_multiplier 必须大于0")
	if result.baguette_giant_interval_seconds <= 0.0:
		errors.append("baguette_giant_interval_seconds 必须大于0")
	if (
		result.baguette_giant_width_regions <= 0.0
		or result.baguette_giant_width_regions > float(Playfield.REGION_COUNT)
	):
		errors.append("baguette_giant_width_regions 必须大于0且不超过6格")
	if (
		result.baguette_giant_pierce_count < 1
		or not is_equal_approx(baguette_giant_pierce_value, roundf(baguette_giant_pierce_value))
	):
		errors.append("baguette_giant_pierce_count 必须是至少1的整数")
	if result.baguette_giant_duration_multiplier <= 0.0:
		errors.append("baguette_giant_duration_multiplier 必须大于0")
	if result.baguette_giant_satisfaction_multiplier <= 0.0:
		errors.append("baguette_giant_satisfaction_multiplier 必须大于0")
	var seen_ids: Dictionary[StringName, bool] = {}
	var row_number: int = 1
	for record: Dictionary in upgrades_sheet.to_records():
		row_number += 1
		if not _as_bool(record.get("启用", true)):
			continue
		var upgrade_id: StringName = StringName(str(record.get("强化ID", "")).strip_edges())
		if upgrade_id.is_empty():
			errors.append("特殊强化表第 %d 行强化ID不能为空" % row_number)
			continue
		if seen_ids.has(upgrade_id):
			errors.append("特殊强化表第 %d 行强化ID重复: %s" % [row_number, String(upgrade_id)])
			continue
		seen_ids[upgrade_id] = true
		var upgrade: SpecialUpgradeData = SpecialUpgradeData.new()
		upgrade.id = upgrade_id
		upgrade.display_name = str(record.get("显示名称", "")).strip_edges()
		upgrade.effect_kind = _special_effect_kind(record.get("效果类型"), row_number, errors)
		upgrade.target_id = StringName(str(record.get("目标ID", "")).strip_edges())
		upgrade.effect_value = _required_number(record, "效果数值", row_number, errors)
		upgrade.repeatable = _as_bool(record.get("可重复", false))
		upgrade.description = str(record.get("获得说明", "")).strip_edges()
		upgrade.upgrade_description = str(record.get("升级说明", "")).strip_edges()
		if upgrade.display_name.is_empty():
			errors.append("特殊强化表第 %d 行显示名称不能为空" % row_number)
		if upgrade.effect_value < 0.0:
			errors.append("特殊强化表第 %d 行效果数值不能为负数" % row_number)
		if upgrade.effect_kind in [
			SpecialUpgradeData.EffectKind.SERVING,
			SpecialUpgradeData.EffectKind.PIERCE,
		] and (
			upgrade.effect_value < 1.0
			or not is_equal_approx(upgrade.effect_value, roundf(upgrade.effect_value))
		):
			errors.append("特殊强化表第 %d 行加量或穿透的效果数值必须是至少1的整数" % row_number)
		if upgrade.effect_kind in [
			SpecialUpgradeData.EffectKind.FOOD_CARD,
			SpecialUpgradeData.EffectKind.TARGET_AIM,
			SpecialUpgradeData.EffectKind.EVOLUTION,
		] and upgrade.target_id.is_empty():
			errors.append("特殊强化表第 %d 行该效果必须填写目标ID" % row_number)
		result.upgrades.append(upgrade)
	if result.upgrades.size() < 3:
		errors.append("特殊强化至少需要启用三项候选")
	if not errors.is_empty():
		return _special_failure(result, "；".join(errors))
	result.loaded_from_excel = true
	return result


static func _read_valid_workbook(
	path: String,
	schema_id: String,
	config_sheet_name: String = CONFIG_SHEET
) -> WorkbookReadResult:
	var result: WorkbookReadResult = WorkbookReadResult.new()
	var excel_result: ExcelReader47.ReadResult = ExcelReader47.read(path)
	if not excel_result.is_ok():
		result.error_message = excel_result.error_message
		return result
	var config_sheet: ExcelReader47.ExcelSheet = excel_result.workbook.get_sheet_by_name(
		config_sheet_name
	)
	if config_sheet == null:
		result.error_message = "Excel 必须包含“%s”工作表" % config_sheet_name
		return result
	var config: Dictionary = _records_to_values(config_sheet)
	if str(config.get("schema_id", "")) != schema_id:
		result.error_message = "Excel schema_id 不匹配: %s" % str(config.get("schema_id", ""))
		return result
	var version: Variant = config.get("schema_version")
	if not _is_number(version) or int(version) != EXPECTED_SCHEMA_VERSION:
		result.error_message = "Excel schema_version 必须为 %d" % EXPECTED_SCHEMA_VERSION
		return result
	result.workbook = excel_result.workbook
	return result


static func _records_to_values(sheet: ExcelReader47.ExcelSheet) -> Dictionary:
	var values: Dictionary = {}
	for record: Dictionary in sheet.to_records():
		var parameter_id: String = str(record.get("参数ID", "")).strip_edges()
		if not parameter_id.is_empty():
			values[parameter_id] = record.get("数值")
	return values


static func _parse_upgrade_sheet(
	sheet: ExcelReader47.ExcelSheet,
	sheet_name: String,
	errors: PackedStringArray
) -> Array[UpgradeData]:
	var upgrades: Array[UpgradeData] = []
	var seen_ids: Dictionary[StringName, bool] = {}
	var row_number: int = 1
	for record: Dictionary in sheet.to_records():
		row_number += 1
		if not _as_bool(record.get("启用", true)):
			continue
		var upgrade_id: StringName = StringName(str(record.get("强化ID", "")).strip_edges())
		if upgrade_id.is_empty():
			errors.append("%s表第 %d 行强化ID不能为空" % [sheet_name, row_number])
			continue
		if seen_ids.has(upgrade_id):
			errors.append("%s表第 %d 行强化ID重复: %s" % [sheet_name, row_number, String(upgrade_id)])
			continue
		seen_ids[upgrade_id] = true
		var minimum_value: float = _required_number(record, "最小值", row_number, errors, sheet_name)
		var maximum_value: float = _required_number(record, "最大值", row_number, errors, sheet_name)
		var upgrade: UpgradeData = UpgradeData.new()
		upgrade.id = upgrade_id
		upgrade.display_name = str(record.get("显示名称", "")).strip_edges()
		upgrade.kind = _upgrade_kind(record.get("类型"), row_number, errors, sheet_name)
		upgrade.value_suffix = str(record.get("显示后缀", "")).strip_edges()
		upgrade.effect_text_template = str(
			record.get("门牌描述模板", "")
		).strip_edges()
		upgrade.configure_value_range(minimum_value, maximum_value)
		if upgrade.display_name.is_empty():
			errors.append("%s表第 %d 行显示名称不能为空" % [sheet_name, row_number])
		if minimum_value < 0.0 or maximum_value < minimum_value:
			errors.append("%s表第 %d 行数值区间无效" % [sheet_name, row_number])
		upgrades.append(upgrade)
	return upgrades


static func _required_number(
	record: Dictionary,
	column: String,
	row_number: int,
	errors: PackedStringArray,
	sheet_name: String = "武器"
) -> float:
	var value: Variant = record.get(column)
	if not _is_number(value):
		errors.append("%s表第 %d 行“%s”必须是数字" % [sheet_name, row_number, column])
		return 0.0
	return float(value)


static func _required_dictionary_number(values: Dictionary, key: String, errors: PackedStringArray) -> float:
	var value: Variant = values.get(key)
	if not _is_number(value):
		errors.append("全局规则缺少数值参数 %s" % key)
		return 0.0
	return float(value)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _as_bool(value: Variant) -> bool:
	if typeof(value) == TYPE_BOOL:
		return value
	if _is_number(value):
		return float(value) != 0.0
	return str(value).strip_edges().to_lower() in ["true", "yes", "是", "1"]


static func _is_blank(value: Variant) -> bool:
	return value == null or (typeof(value) == TYPE_STRING and str(value).strip_edges().is_empty())


static func _customer_category(
	value: Variant,
	row_number: int,
	errors: PackedStringArray
) -> CustomerData.Category:
	match str(value).strip_edges():
		"普通":
			return CustomerData.Category.NORMAL
		"精英":
			return CustomerData.Category.ELITE
	errors.append("食客表第 %d 行身份层级不受支持: %s" % [row_number, str(value)])
	return CustomerData.Category.NORMAL


static func _customer_behavior(
	value: Variant,
	row_number: int,
	errors: PackedStringArray
) -> CustomerData.Behavior:
	match str(value).strip_edges():
		"无":
			return CustomerData.Behavior.NONE
		"远程":
			return CustomerData.Behavior.RANGED
	errors.append("食客表第 %d 行行为类型不受支持: %s" % [row_number, str(value)])
	return CustomerData.Behavior.NONE


static func _attack_kind(value: Variant, row_number: int, errors: PackedStringArray) -> FoodData.AttackKind:
	match str(value).strip_edges().to_lower():
		"projectile":
			return FoodData.AttackKind.PROJECTILE
		"piercing_projectile":
			return FoodData.AttackKind.PIERCING_PROJECTILE
		"orbiting_mushroom":
			return FoodData.AttackKind.ORBITING_MUSHROOM
	errors.append("武器表第 %d 行攻击类型不受支持: %s" % [row_number, str(value)])
	return FoodData.AttackKind.PROJECTILE


static func _aim_mode(value: Variant, row_number: int, errors: PackedStringArray) -> FoodData.AimMode:
	match str(value).strip_edges().to_lower():
		"fixed_forward":
			return FoodData.AimMode.FIXED_FORWARD
		"target_snapshot":
			return FoodData.AimMode.TARGET_SNAPSHOT
	errors.append("武器表第 %d 行初始瞄准不受支持: %s" % [row_number, str(value)])
	return FoodData.AimMode.FIXED_FORWARD


static func _tracking_mode(value: Variant, row_number: int, errors: PackedStringArray) -> FoodData.TrackingMode:
	match str(value).strip_edges().to_lower():
		"none":
			return FoodData.TrackingMode.NONE
		"homing":
			return FoodData.TrackingMode.HOMING
	errors.append("武器表第 %d 行初始追踪不受支持: %s" % [row_number, str(value)])
	return FoodData.TrackingMode.NONE


static func _upgrade_kind(
	value: Variant,
	row_number: int,
	errors: PackedStringArray,
	sheet_name: String
) -> UpgradeData.Kind:
	match str(value).strip_edges().to_lower():
		"sugar":
			return UpgradeData.Kind.SUGAR
		"quick_prep":
			return UpgradeData.Kind.QUICK_PREP
		"wine":
			return UpgradeData.Kind.WINE
		"scallion":
			return UpgradeData.Kind.SCALLION
		"starch":
			return UpgradeData.Kind.STARCH
		"light_cart":
			return UpgradeData.Kind.LIGHT_CART
		"sturdy_cart":
			return UpgradeData.Kind.STURDY_CART
		"repair":
			return UpgradeData.Kind.REPAIR
	errors.append("%s表第 %d 行类型不受支持: %s" % [sheet_name, row_number, str(value)])
	return UpgradeData.Kind.SUGAR


static func _special_effect_kind(
	value: Variant,
	row_number: int,
	errors: PackedStringArray
) -> SpecialUpgradeData.EffectKind:
	match str(value).strip_edges().to_lower():
		"food_card":
			return SpecialUpgradeData.EffectKind.FOOD_CARD
		"serving":
			return SpecialUpgradeData.EffectKind.SERVING
		"target_aim":
			return SpecialUpgradeData.EffectKind.TARGET_AIM
		"evolution":
			return SpecialUpgradeData.EffectKind.EVOLUTION
		"pierce":
			return SpecialUpgradeData.EffectKind.PIERCE
	errors.append("特殊强化表第 %d 行效果类型不受支持: %s" % [row_number, str(value)])
	return SpecialUpgradeData.EffectKind.SERVING


static func _weapon_failure(result: WeaponLoadResult, message: String) -> WeaponLoadResult:
	result.foods.clear()
	result.error_message = message
	return result


static func _customer_failure(
	result: CustomerLoadResult,
	message: String
) -> CustomerLoadResult:
	result.customers.clear()
	result.error_message = message
	return result


static func _normal_failure(result: NormalUpgradeLoadResult, message: String) -> NormalUpgradeLoadResult:
	result.upgrades.clear()
	result.error_message = message
	return result


static func _special_failure(result: SpecialUpgradeLoadResult, message: String) -> SpecialUpgradeLoadResult:
	result.upgrades.clear()
	result.error_message = message
	return result
