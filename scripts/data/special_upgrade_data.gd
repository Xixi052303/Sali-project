class_name SpecialUpgradeData
extends Resource

enum EffectKind {
	FOOD_CARD,
	SERVING,
	TARGET_AIM,
	EVOLUTION,
	PIERCE,
}

@export var id: StringName = &"serving"
@export var display_name: String = "全局加量"
@export var effect_kind: EffectKind = EffectKind.SERVING
@export var target_id: StringName = &""
@export var effect_value: float = 1.0
@export var repeatable: bool = false
@export var description: String = ""
@export var upgrade_description: String = ""


func _init() -> void:
	pass
