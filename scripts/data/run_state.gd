class_name RunState
extends Resource

signal durability_changed(current: float, maximum: float, temporary_shield: float)
signal inventory_changed

const MINIMUM_INTERVAL: float = 1.0 / 60.0
const FOOD_MAX_LEVEL: int = 3
const FOOD_LEVEL_SATISFACTION_MULTIPLIER: float = 1.5


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
			candidate_texts.append(String(candidate))
		return {
			"source": String(source),
			"elapsed_seconds": elapsed_seconds,
			"candidates": candidate_texts,
			"selected": String(selected),
		}

var maximum_durability: float = 100.0
var current_durability: float = 100.0
# 同类百分比强化在整局内线性加算，后取得的食材直接继承累计结果。
var satisfaction_multiplier: float = 1.0
var attack_speed_bonus: float = 0.0
var projectile_speed_multiplier: float = 1.0
var range_multiplier: float = 1.0
var duration_multiplier: float = 1.0
var cart_speed_bonus: float = 0.0
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
var dropped_upgrades: int = 0
var elapsed_seconds: float = 0.0
var gate_choices: int = 0
var customers_satisfied: int = 0
var normal_defeats: int = 0
var collided_defeats: int = 0
var upgrade_drops_spawned: int = 0
var hits_taken: int = 0
var durability_lost: float = 0.0
var elite_duration: float = 0.0
var elite_durations: Array[float] = []
var boss_duration: float = 0.0
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


func food_level(food_id: StringName) -> int:
	return food_levels.get(food_id, 0)


func can_level_food(food_id: StringName) -> bool:
	return has_food(food_id) and food_level(food_id) < FOOD_MAX_LEVEL


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


func apply_upgrade(upgrade: UpgradeData, count_as_gate: bool = true) -> void:
	if count_as_gate:
		gate_choices += 1
	else:
		dropped_upgrades += 1
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
			maximum_durability += upgrade.value
			current_durability += upgrade.value
			durability_changed.emit(current_durability, maximum_durability, temporary_shield)
		UpgradeData.Kind.REPAIR:
			repair(maximum_durability * upgrade.value)
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


func effective_satisfaction(food: FoodData) -> float:
	var level_multiplier: float = pow(
		FOOD_LEVEL_SATISFACTION_MULTIPLIER,
		maxi(0, food_level(food.id) - 1)
	)
	return food.base_satisfaction * level_multiplier * satisfaction_multiplier


func effective_interval(food: FoodData) -> float:
	return maxf(MINIMUM_INTERVAL, food.base_interval / (1.0 + attack_speed_bonus))


func effective_projectile_speed(food: FoodData) -> float:
	return food.projectile_speed * projectile_speed_multiplier


func effective_orbit_angular_speed(food: FoodData) -> float:
	return food.orbit_angular_speed * projectile_speed_multiplier


func effective_projectile_radius(food: FoodData) -> float:
	return food.projectile_radius * range_multiplier


func effective_duration(food: FoodData) -> float:
	return food.base_lifetime * duration_multiplier


func effective_pierce_count(food: FoodData) -> int:
	return maxi(1, food.pierce_count + pierce_bonus)


# 投射物射程由弹速与持续时间共同决定，两类强化会分别放大同一结果。
func effective_projectile_distance(food: FoodData) -> float:
	return effective_projectile_speed(food) * effective_duration(food)


func record_food_satisfaction(food_id: StringName, amount: float) -> void:
	if amount <= 0.0:
		return
	satisfaction_by_food[food_id] = satisfaction_by_food.get(food_id, 0.0) + amount


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
