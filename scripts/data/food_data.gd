class_name FoodData
extends Resource

enum AttackKind {
	PROJECTILE,
	PIERCING_PROJECTILE,
	ORBITING_MUSHROOM,
}

enum TrackingMode {
	NONE,
	HOMING,
}

enum AimMode {
	FIXED_FORWARD,
	TARGET_SNAPSHOT,
}

@export var id: StringName = &"potato"
@export var display_name: String = "土豆"
@export var attack_kind: AttackKind = AttackKind.PROJECTILE
@export var initial_aim_mode: AimMode = AimMode.FIXED_FORWARD
@export var initial_tracking_mode: TrackingMode = TrackingMode.NONE
@export var homing_turn_speed: float = 4.5
@export var base_satisfaction: float = 10.0
@export var base_interval: float = 0.8
@export var projectile_speed: float = 760.0
@export var projectile_radius: float = 16.0
@export var base_lifetime: float = 1.6
@export var pierce_count: int = 1
@export var visual_color: Color = Color("#e2b650")
@export_group("Orbiting attack")
@export var orbit_radius: float = 120.0
@export var orbit_angular_speed: float = 3.2
@export var breathing_period: float = 1.2
@export var breathing_outer_multiplier: float = 2.0


func _init() -> void:
	pass
