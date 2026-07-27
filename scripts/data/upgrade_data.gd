class_name UpgradeData
extends Resource

enum Kind {
	SUGAR,
	QUICK_PREP,
	WINE,
	SCALLION,
	STARCH,
	LIGHT_CART,
	STURDY_CART,
	REPAIR,
}

@export var id: StringName = &"sugar"
@export var display_name: String = "糖"
@export var kind: Kind = Kind.SUGAR
@export var value: float = 0.15
@export var value_suffix: String = "%"
@export var minimum_value: float = 0.0
@export var maximum_value: float = 0.0
@export_range(0.0, 1.0, 0.001) var value_ratio: float = 0.0
@export var uses_value_range: bool = false
@export var rarity_name: String = "寻常"
@export var rarity_color: Color = Color("#d7c59a")


func _init() -> void:
	pass


# 配置门选项的完整数值区间，并按归一化百分位生成当前奖励。
func configure_value_range(lower: float, upper: float, ratio: float = 0.0) -> void:
	minimum_value = minf(lower, upper)
	maximum_value = maxf(lower, upper)
	uses_value_range = true
	set_value_ratio(ratio)


# 门受击时只推进百分位，实际数值和稀有度始终由同一百分位派生。
func set_value_ratio(ratio: float) -> void:
	value_ratio = clampf(ratio, 0.0, 1.0)
	if uses_value_range:
		value = lerpf(minimum_value, maximum_value, value_ratio)
	_update_rarity()


func is_at_maximum() -> bool:
	return uses_value_range and value_ratio >= 1.0 - 0.0001


func formatted_value() -> String:
	if value_suffix == "%":
		return "%+.0f%%" % (value * 100.0)
	if value_suffix == "点":
		return "%+.0f点" % value
	return "%+.0f%s" % [value, value_suffix]


func effect_text(maximum_durability: float = 100.0) -> String:
	match kind:
		Kind.SUGAR:
			return "满足 %s" % formatted_value()
		Kind.QUICK_PREP:
			return "攻速 %s" % formatted_value()
		Kind.WINE:
			return "弹速 %s" % formatted_value()
		Kind.SCALLION:
			return "范围 %s" % formatted_value()
		Kind.STARCH:
			return "持续 %s" % formatted_value()
		Kind.LIGHT_CART:
			return "移速 %s" % formatted_value()
		Kind.STURDY_CART:
			return "耐久 %s" % formatted_value()
		Kind.REPAIR:
			return "恢复/护盾 +%.0f点" % (maximum_durability * value)
	return formatted_value()


func _update_rarity() -> void:
	if value_ratio < 0.25:
		rarity_name = "寻常"
		rarity_color = Color("#d7c59a")
	elif value_ratio < 0.5:
		rarity_name = "精良"
		rarity_color = Color("#73b8a6")
	elif value_ratio < 0.75:
		rarity_name = "稀罕"
		rarity_color = Color("#c88ad4")
	else:
		rarity_name = "珍奇"
		rarity_color = Color("#f0c45f")
