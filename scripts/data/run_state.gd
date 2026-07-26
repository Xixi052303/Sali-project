class_name RunState
extends Resource

signal durability_changed(current: float, maximum: float)
signal inventory_changed

const MINIMUM_INTERVAL: float = 1.0 / 60.0

var maximum_durability: float = 100.0
var current_durability: float = 100.0
var satisfaction_bonus: float = 0.0
var interval_reduction: float = 0.0
var projectile_speed_bonus: float = 0.0
var range_bonus: float = 0.0
var duration_bonus: float = 0.0
var cart_speed_bonus: float = 0.0
var servings: int = 1
var foods: Array[StringName] = []
var specials: Array[StringName] = []
var target_aim_foods: Array[StringName] = []
var homing_foods: Array[StringName] = []
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
var boss_duration: float = 0.0


func _init() -> void:
	pass


func add_food(food_id: StringName) -> void:
	if foods.has(food_id):
		return
	foods.append(food_id)
	inventory_changed.emit()


func has_food(food_id: StringName) -> bool:
	return foods.has(food_id)


func add_special(special_id: StringName) -> void:
	specials.append(special_id)
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
			satisfaction_bonus += upgrade.value
		UpgradeData.Kind.QUICK_PREP:
			interval_reduction += upgrade.value
		UpgradeData.Kind.WINE:
			projectile_speed_bonus += upgrade.value
		UpgradeData.Kind.SCALLION:
			range_bonus += upgrade.value
		UpgradeData.Kind.STARCH:
			duration_bonus += upgrade.value
		UpgradeData.Kind.LIGHT_CART:
			cart_speed_bonus += upgrade.value
		UpgradeData.Kind.STURDY_CART:
			maximum_durability += upgrade.value
			current_durability += upgrade.value
			durability_changed.emit(current_durability, maximum_durability)
		UpgradeData.Kind.REPAIR:
			repair(maximum_durability * upgrade.value)
	inventory_changed.emit()


func take_durability_damage(amount: float) -> float:
	var applied: float = minf(maxf(amount, 0.0), current_durability)
	current_durability -= applied
	hits_taken += 1
	durability_lost += applied
	durability_changed.emit(current_durability, maximum_durability)
	return applied


func repair(amount: float) -> void:
	current_durability = minf(maximum_durability, current_durability + maxf(amount, 0.0))
	durability_changed.emit(current_durability, maximum_durability)


func effective_satisfaction(food: FoodData) -> float:
	return food.base_satisfaction * (1.0 + satisfaction_bonus)


func effective_interval(food: FoodData) -> float:
	return maxf(MINIMUM_INTERVAL, food.base_interval * (1.0 - interval_reduction))


func effective_projectile_speed(food: FoodData) -> float:
	return food.projectile_speed * (1.0 + projectile_speed_bonus)


func effective_projectile_radius(food: FoodData) -> float:
	return food.projectile_radius * (1.0 + range_bonus)


func effective_duration(food: FoodData) -> float:
	return food.base_lifetime * (1.0 + duration_bonus)


func cumulative_effect_text(kind: UpgradeData.Kind) -> String:
	match kind:
		UpgradeData.Kind.SUGAR:
			return "累计满足值 +%.0f%%" % (satisfaction_bonus * 100.0)
		UpgradeData.Kind.QUICK_PREP:
			return "累计攻击间隔 -%.0f%%" % (interval_reduction * 100.0)
		UpgradeData.Kind.WINE:
			return "累计投射速度 +%.0f%%" % (projectile_speed_bonus * 100.0)
		UpgradeData.Kind.SCALLION:
			return "累计作用范围 +%.0f%%" % (range_bonus * 100.0)
		UpgradeData.Kind.STARCH:
			return "累计持续时间 +%.0f%%" % (duration_bonus * 100.0)
		UpgradeData.Kind.LIGHT_CART:
			return "累计横移速度 +%.0f" % cart_speed_bonus
		UpgradeData.Kind.STURDY_CART:
			return "最大耐久 %.0f" % maximum_durability
		UpgradeData.Kind.REPAIR:
			return "当前耐久 %.0f / %.0f" % [current_durability, maximum_durability]
	return ""
