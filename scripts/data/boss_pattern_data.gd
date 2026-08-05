class_name BossPatternData
extends Resource

const DEFAULT_APPETITE_MULTIPLIER: float = 3.0

@export var display_name: String = "临时主厨"
# Boss 胃口在登场时按当前普通食客基准乘算，默认承担三倍火力检查。
@export var appetite_multiplier: float = DEFAULT_APPETITE_MULTIPLIER
@export var move_speed: float = 110.0
@export var telegraph_duration: float = 1.15
@export var recovery_duration: float = 1.0
@export var line_attack_ratio: float = 0.025
@export var area_attack_ratio: float = 0.036
@export var body_color: Color = Color("#873f36")


func _init() -> void:
	pass


func appetite_at(baseline_appetite: float) -> float:
	return roundf(maxf(1.0, baseline_appetite) * maxf(0.0, appetite_multiplier))
