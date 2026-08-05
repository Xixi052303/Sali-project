class_name RunState
extends Resource

signal durability_changed(current: float, maximum: float, temporary_shield: float)
signal inventory_changed

const MINIMUM_INTERVAL: float = 1.0 / 60.0
const DEFAULT_RESPAWN_BASE_SECONDS: float = 15.0
const DEFAULT_RESPAWN_INCREMENT_SECONDS: float = 15.0
const DEFAULT_RESPAWN_MAX_SECONDS: float = 180.0
const DEFAULT_GHOST_DAMAGE_MULTIPLIER: float = 0.01
const DEFAULT_RESPAWN_DURABILITY_RATIO: float = 0.5
const DEFAULT_RESPAWN_INVINCIBILITY_SECONDS: float = 2.0
const FOOD_MAX_LEVEL: int = 3
const FOOD_LEVEL_SATISFACTION_MULTIPLIER: float = 2.25
const BAGUETTE_GIANT_INTERVAL_SECONDS: float = 3.0
const BAGUETTE_GIANT_ATTACK_SPEED_SCALE: float = 0.05
const BAGUETTE_GIANT_MINIMUM_INTERVAL_SECONDS: float = 1.0
const BAGUETTE_GIANT_WIDTH_REGIONS: float = 4.0
const BAGUETTE_GIANT_PIERCE_COUNT: int = 999
const BAGUETTE_GIANT_DURATION_MULTIPLIER: float = 1.5
const BAGUETTE_GIANT_SATISFACTION_MULTIPLIER: float = 3.0
const WINE_CURVE_C: float = 1.0
const RANGE_CURVE_C: float = 4.0
const DURATION_CURVE_C: float = 1.0
const CART_SPEED_CURVE_C: float = 0.5
const RANGE_MULTIPLIER_CAP: float = 600.0 / 34.0


class SpecialChoiceRecord:
	extends RefCounted

	var source: StringName
	var elapsed_seconds: float
	var candidates: Array[StringName]
	var selected: StringName = &""

	func _init(
		choice_source: StringName,
		choice_time: float,
		choice_candidates: Array[StringName]
	) -> void:
		source = choice_source
		elapsed_seconds = choice_time
		candidates = choice_candidates.duplicate()

	func to_dictionary() -> Dictionary:
		var candidate_texts: Array[String] = []
		for candidate: StringName in candidates:
			candidate_texts.append(str(candidate))
		return {
			"source": str(source),
			"elapsed_seconds": elapsed_seconds,
			"candidates": candidate_texts,
			"selected": str(selected),
		}

var maximum_durability: float = 100.0
var current_durability: float = 100.0
# 特殊强化表可覆盖等级规则；默认值继续作为工作簿失败时的安全回退。
var food_max_level: int = FOOD_MAX_LEVEL
var food_level_satisfaction_multiplier: float = FOOD_LEVEL_SATISFACTION_MULTIPLIER
# 巨型法棍参数由武器表覆盖，并在表格失败时保留同规则的安全回退。
var baguette_giant_interval_seconds: float = BAGUETTE_GIANT_INTERVAL_SECONDS
var baguette_giant_attack_speed_scale: float = BAGUETTE_GIANT_ATTACK_SPEED_SCALE
var baguette_giant_minimum_interval_seconds: float = BAGUETTE_GIANT_MINIMUM_INTERVAL_SECONDS
var baguette_giant_width_regions: float = BAGUETTE_GIANT_WIDTH_REGIONS
var baguette_giant_pierce_count: int = BAGUETTE_GIANT_PIERCE_COUNT
var baguette_giant_duration_multiplier: float = BAGUETTE_GIANT_DURATION_MULTIPLIER
var baguette_giant_satisfaction_multiplier: float = BAGUETTE_GIANT_SATISFACTION_MULTIPLIER
# 同类百分比强化在整局内线性加算，后取得的食材直接继承累计结果。
var satisfaction_multiplier: float = 1.0
var attack_speed_bonus: float = 0.0
var projectile_speed_multiplier: float = 1.0
var range_multiplier: float = 1.0
var duration_multiplier: float = 1.0
var cart_speed_bonus: float = 0.0
# 当前阶段的疲劳与颠簸只降低基础横移，普通强化形成的加值不受二次削弱。
var cart_base_speed_factor: float = 1.0
# 对数软化参数来自普通强化表；加载失败时使用与正式首轮一致的安全回退。
var wine_curve_c: float = WINE_CURVE_C
var range_curve_c: float = RANGE_CURVE_C
var duration_curve_c: float = DURATION_CURVE_C
var cart_speed_curve_c: float = CART_SPEED_CURVE_C
var range_multiplier_cap: float = RANGE_MULTIPLIER_CAP
# 临时护盾来自溢出维修，仅在本局内保留并优先于餐车耐久承伤。
var temporary_shield: float = 0.0
var servings: int = 1
# 酱油按层提高所有当前与未来食材可命中的目标数量。
var pierce_bonus: int = 0
var foods: Array[StringName] = []
var food_levels: Dictionary[StringName, int] = {}
var specials: Array[StringName] = []
var food_evolutions: Array[StringName] = []
var target_aim_foods: Array[StringName] = []
var homing_foods: Array[StringName] = []
var satisfaction_by_food: Dictionary[StringName, float] = {}
var special_choice_records: Array[SpecialChoiceRecord] = []
# 普通强化统计用于固定种子复盘；数值累计记录实际结算值而非品质百分位。
var normal_upgrade_offer_counts: Dictionary[StringName, int] = {}
var normal_upgrade_choice_counts: Dictionary[StringName, int] = {}
var normal_upgrade_value_totals: Dictionary[StringName, float] = {}
var normal_upgrade_contribution_totals: Dictionary[StringName, float] = {}
var dropped_upgrades: int = 0
var elapsed_seconds: float = 0.0
# 只在前进阶段累计，Boss与选择暂停；时间轴、胃口和压力统一读取该路程。
var forward_distance: float = 0.0
var gate_choices: int = 0
var customers_satisfied: int = 0
var normal_defeats: int = 0
var normal_customers_spawned: int = 0
var collided_defeats: int = 0
var upgrade_drops_spawned: int = 0
var hits_taken: int = 0
var durability_lost: float = 0.0
var elite_duration: float = 0.0
var elite_durations: Array[float] = []
var boss_duration: float = 0.0
var boss_durations: Array[float] = []
var run_seed: int = 0


func _init() -> void:
	pass


func add_food(food_id: StringName) -> void:
	if foods.has(food_id):
		return
	foods.append(food_id)
	food_levels[food_id] = 1
	inventory_changed.emit()


func has_food(food_id: StringName) -> bool:
	return foods.has(food_id)


# Debug清空当前持有食材与等级；全局强化和历史满足统计继续保留。
func clear_foods() -> int:
	var removed_count: int = foods.size()
	if removed_count == 0 and food_levels.is_empty():
		return 0
	foods.clear()
	food_levels.clear()
	inventory_changed.emit()
	return removed_count


func food_level(food_id: StringName) -> int:
	return food_levels.get(food_id, 0)


func can_level_food(food_id: StringName) -> bool:
	return has_food(food_id) and food_level(food_id) < food_max_level


func level_food(food_id: StringName) -> int:
	if not can_level_food(food_id):
		return food_level(food_id)
	food_levels[food_id] = food_level(food_id) + 1
	inventory_changed.emit()
	return food_level(food_id)


func add_special(special_id: StringName) -> void:
	specials.append(special_id)
	inventory_changed.emit()


func enable_food_evolution(evolution_id: StringName) -> void:
	if food_evolutions.has(evolution_id):
		return
	food_evolutions.append(evolution_id)
	inventory_changed.emit()


func has_food_evolution(evolution_id: StringName) -> bool:
	return food_evolutions.has(evolution_id)


# 叠加全局穿透层数，并由投射物生成时读取最终命中次数。
func add_pierce_bonus(amount: int = 1) -> void:
	pierce_bonus += maxi(0, amount)
	inventory_changed.emit()


func enable_target_aim(food_id: StringName) -> void:
	if target_aim_foods.has(food_id):
		return
	target_aim_foods.append(food_id)
	inventory_changed.emit()


func is_food_target_aimed(food_id: StringName) -> bool:
	return target_aim_foods.has(food_id)


func enable_homing(food_id: StringName) -> void:
	if homing_foods.has(food_id):
		return
	homing_foods.append(food_id)
	inventory_changed.emit()


func is_food_homing(food_id: StringName) -> bool:
	return homing_foods.has(food_id)


func apply_upgrade(
	upgrade: UpgradeData,
	count_as_gate: bool = true,
	allow_health_effects: bool = true
) -> void:
	if upgrade == null:
		return
	if count_as_gate:
		gate_choices += 1
	else:
		dropped_upgrades += 1
	var contribution: float = upgrade.value
	match upgrade.kind:
		UpgradeData.Kind.SUGAR:
			satisfaction_multiplier += upgrade.value
		UpgradeData.Kind.QUICK_PREP:
			attack_speed_bonus += maxf(0.0, upgrade.value)
		UpgradeData.Kind.WINE:
			projectile_speed_multiplier += upgrade.value
		UpgradeData.Kind.SCALLION:
			range_multiplier += upgrade.value
		UpgradeData.Kind.STARCH:
			duration_multiplier += upgrade.value
		UpgradeData.Kind.LIGHT_CART:
			cart_speed_bonus += upgrade.value
		UpgradeData.Kind.STURDY_CART:
			var durability_gain: float = maximum_durability * maxf(0.0, upgrade.value)
			contribution = durability_gain
			maximum_durability += durability_gain
			if allow_health_effects:
				current_durability += durability_gain
			durability_changed.emit(current_durability, maximum_durability, temporary_shield)
		UpgradeData.Kind.REPAIR:
			contribution = maximum_durability * upgrade.value
			if allow_health_effects:
				repair(contribution)
	_record_normal_upgrade_choice(upgrade, contribution)
	inventory_changed.emit()


# 受击先消耗临时护盾，只有穿透护盾的部分才计入实际耐久损失。
func take_durability_damage(amount: float) -> float:
	var incoming: float = maxf(amount, 0.0)
	var shield_absorbed: float = minf(incoming, temporary_shield)
	temporary_shield -= shield_absorbed
	var durability_damage: float = minf(incoming - shield_absorbed, current_durability)
	current_durability -= durability_damage
	hits_taken += 1
	durability_lost += durability_damage
	durability_changed.emit(current_durability, maximum_durability, temporary_shield)
	return shield_absorbed + durability_damage


# 紧急维修先补满耐久，超过上限的部分完整转化为可叠加的临时护盾。
func repair(amount: float) -> void:
	var repair_amount: float = maxf(amount, 0.0)
	var missing_durability: float = maxf(0.0, maximum_durability - current_durability)
	var restored: float = minf(repair_amount, missing_durability)
	current_durability += restored
	temporary_shield += repair_amount - restored
	durability_changed.emit(current_durability, maximum_durability, temporary_shield)


# Debug与后续奖励统一通过该入口增加护盾，避免外部改写状态后漏发HUD刷新信号。
func add_temporary_shield(amount: float) -> void:
	temporary_shield += maxf(amount, 0.0)
	durability_changed.emit(current_durability, maximum_durability, temporary_shield)


func effective_satisfaction(food: FoodData) -> float:
	var level_multiplier: float = pow(
		food_level_satisfaction_multiplier,
		maxi(0, food_level(food.id) - 1)
	)
	return food.base_satisfaction * level_multiplier * satisfaction_multiplier


# 衍生攻击的满足基数和全局倍率来自来源食材，衍生行只可额外调整满足倍率。
func effective_derived_satisfaction(derived_attack: FoodData, source_food: FoodData) -> float:
	if derived_attack == null:
		return 0.0
	if source_food != null:
		var source_base_satisfaction: float = maxf(0.001, source_food.base_satisfaction)
		var derived_satisfaction_multiplier: float = maxf(
			0.0,
			derived_attack.base_satisfaction / source_base_satisfaction
		)
		return effective_satisfaction(source_food) * derived_satisfaction_multiplier
	return derived_attack.base_satisfaction * satisfaction_multiplier


func effective_interval(food: FoodData) -> float:
	var scaled_bonus: float = attack_speed_bonus * maxf(0.0, food.attack_speed_upgrade_scale)
	return maxf(MINIMUM_INTERVAL, food.base_interval / (1.0 + scaled_bonus))


# 蛋液周期沿用来源鸡蛋的攻速与酒转译倍率，只有基础节拍来自衍生攻击行。
func effective_derived_interval(
	derived_attack: FoodData,
	source_food: FoodData = null
) -> float:
	if derived_attack == null:
		return MINIMUM_INTERVAL
	var inherited_food: FoodData = source_food if source_food != null else derived_attack
	var attack_speed: float = (
		1.0 + attack_speed_bonus * maxf(0.0, inherited_food.attack_speed_upgrade_scale)
	)
	var wine_speed: float = _log_upgrade_multiplier(
		projectile_speed_multiplier - 1.0,
		inherited_food.wine_upgrade_scale,
		wine_curve_c
	)
	return maxf(MINIMUM_INTERVAL, derived_attack.base_interval / attack_speed / wine_speed)


func effective_projectile_speed(food: FoodData) -> float:
	return food.projectile_speed * _log_upgrade_multiplier(
		projectile_speed_multiplier - 1.0,
		food.wine_upgrade_scale,
		wine_curve_c
	)


func effective_orbit_angular_speed(food: FoodData) -> float:
	return food.orbit_angular_speed * _log_upgrade_multiplier(
		projectile_speed_multiplier - 1.0,
		food.wine_upgrade_scale,
		wine_curve_c
	)


func effective_projectile_radius(food: FoodData) -> float:
	var multiplier: float = _log_upgrade_multiplier(
		range_multiplier - 1.0,
		food.range_upgrade_scale,
		range_curve_c
	)
	return food.projectile_radius * minf(multiplier, maxf(1.0, range_multiplier_cap))


func effective_duration(food: FoodData) -> float:
	return food.base_lifetime * _log_upgrade_multiplier(
		duration_multiplier - 1.0,
		food.duration_upgrade_scale,
		duration_curve_c
	)


# 巨型法棍只吸收少量全局攻速，并使用独立下限保护其构筑定位和画面节奏。
func effective_giant_baguette_interval() -> float:
	var scaled_bonus: float = attack_speed_bonus * maxf(0.0, baguette_giant_attack_speed_scale)
	var minimum_interval: float = maxf(MINIMUM_INTERVAL, baguette_giant_minimum_interval_seconds)
	return maxf(minimum_interval, baguette_giant_interval_seconds / (1.0 + scaled_bonus))


func effective_pierce_count(food: FoodData) -> int:
	return maxi(1, food.pierce_count + pierce_bonus)


# 直线投射物射程由弹速与持续时间决定；胡萝卜返回固定扫掠终点。
func effective_projectile_distance(food: FoodData) -> float:
	if food.attack_kind == FoodData.AttackKind.CARROT_SWEEP:
		return food.sweep_radius
	return effective_projectile_speed(food) * effective_duration(food)


# 原始加成保持线性累计，食材转译后再以对数软化高层物理膨胀。
func _log_upgrade_multiplier(raw_bonus: float, scale: float, curve_c: float) -> float:
	var safe_c: float = maxf(0.001, curve_c)
	var translated_bonus: float = maxf(0.0, raw_bonus) * maxf(0.0, scale)
	return 1.0 + safe_c * log(1.0 + translated_bonus / safe_c)


# 轻便餐车以设计像素累计，再按基础速度比例软化；疲劳只作用于基础速度。
func effective_cart_speed_bonus(base_speed_design: float) -> float:
	var safe_base: float = maxf(0.001, base_speed_design)
	var raw_ratio: float = maxf(0.0, cart_speed_bonus) / safe_base
	return safe_base * cart_speed_curve_c * log(
		1.0 + raw_ratio / maxf(0.001, cart_speed_curve_c)
	)


func record_food_satisfaction(food_id: StringName, amount: float) -> void:
	if amount <= 0.0:
		return
	satisfaction_by_food[food_id] = satisfaction_by_food.get(food_id, 0.0) + amount


func record_normal_upgrade_offer(upgrades: Array[UpgradeData]) -> void:
	for upgrade: UpgradeData in upgrades:
		if upgrade == null:
			continue
		normal_upgrade_offer_counts[upgrade.id] = (
			normal_upgrade_offer_counts.get(upgrade.id, 0) + 1
		)


func _record_normal_upgrade_choice(upgrade: UpgradeData, contribution: float) -> void:
	normal_upgrade_choice_counts[upgrade.id] = (
		normal_upgrade_choice_counts.get(upgrade.id, 0) + 1
	)
	normal_upgrade_value_totals[upgrade.id] = (
		normal_upgrade_value_totals.get(upgrade.id, 0.0) + upgrade.value
	)
	normal_upgrade_contribution_totals[upgrade.id] = (
		normal_upgrade_contribution_totals.get(upgrade.id, 0.0) + contribution
	)


func record_special_offer(
	source: StringName,
	candidates: Array[StringName]
) -> void:
	special_choice_records.append(SpecialChoiceRecord.new(source, elapsed_seconds, candidates))


func record_special_choice(choice_id: StringName) -> void:
	if special_choice_records.is_empty():
		return
	special_choice_records.back().selected = choice_id


func special_choice_records_as_array() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for record: SpecialChoiceRecord in special_choice_records:
		records.append(record.to_dictionary())
	return records


func cumulative_effect_text(kind: UpgradeData.Kind) -> String:
	match kind:
		UpgradeData.Kind.SUGAR:
			return "累计满足值 +%.0f%%" % ((satisfaction_multiplier - 1.0) * 100.0)
		UpgradeData.Kind.QUICK_PREP:
			return "累计攻击速度 +%.0f%%" % (attack_speed_bonus * 100.0)
		UpgradeData.Kind.WINE:
			return "累计投射速度 +%.0f%%" % ((projectile_speed_multiplier - 1.0) * 100.0)
		UpgradeData.Kind.SCALLION:
			return "累计作用范围 +%.0f%%" % ((range_multiplier - 1.0) * 100.0)
		UpgradeData.Kind.STARCH:
			return "累计持续时间 +%.0f%%" % ((duration_multiplier - 1.0) * 100.0)
		UpgradeData.Kind.LIGHT_CART:
			return "累计横移速度 +%.0f" % cart_speed_bonus
		UpgradeData.Kind.STURDY_CART:
			return "最大耐久 %.0f" % maximum_durability
		UpgradeData.Kind.REPAIR:
			return "耐久 %.0f / %.0f · 护盾 %.0f" % [
				current_durability,
				maximum_durability,
				temporary_shield,
			]
	return ""
