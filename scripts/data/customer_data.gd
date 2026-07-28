class_name CustomerData
extends Resource

enum Category {
	NORMAL,
	ELITE,
}

enum Behavior {
	NONE,
	RANGED,
}

@export var id: StringName = &"basic_guest"
@export var display_name: String = "饿肚食客"
@export var category: Category = Category.NORMAL
@export var behavior: Behavior = Behavior.NONE
# 每种食客按生成时基准胃口乘以该倍率，实际胃口随后锁定在实例中。
@export var appetite_multiplier: float = 1.0
@export var move_speed: float = 65.0
@export_range(1, 6, 1) var occupied_regions: int = 2
@export var body_color: Color = Color("#6f7650")
# 每类食客指向已完整装配视觉的场景；空值仅回退到通用纸片场景。
@export var customer_scene: PackedScene
@export var attack_ratio: float = 0.0
@export var attack_interval: float = 3.0


func _init() -> void:
	pass


# 兼容当前四类食客原有横向错位序列；该值不是策划数值，不进入食客表。
func spawn_pattern_offset() -> int:
	match id:
		&"fast_guest":
			return 1
		&"ranged_guest":
			return 2
		&"elite_guest":
			return 3
	return 0


# 普通食客的奖励百分位同时提高其胃口；精英传入零以保持原有倍率。
func appetite_at(baseline_appetite: float, rarity_ratio: float = 0.0) -> float:
	return roundf(
		maxf(1.0, baseline_appetite)
		* appetite_multiplier
		* (1.0 + clampf(rarity_ratio, 0.0, 1.0))
	)
