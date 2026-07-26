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
@export var rarity_name: String = "寻常"
@export var rarity_color: Color = Color("#d7c59a")


func _init() -> void:
	pass


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
			return "间隔 -%.0f%%" % (value * 100.0)
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
			return "修复 +%.0f点" % (maximum_durability * value)
	return formatted_value()
