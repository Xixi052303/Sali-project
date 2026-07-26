class_name CustomerData
extends Resource

enum Kind {
	BASIC,
	FAST,
	RANGED,
	ELITE,
}

@export var id: StringName = &"basic_guest"
@export var display_name: String = "饿肚食客"
@export var kind: Kind = Kind.BASIC
@export var appetite: float = 35.0
@export var move_speed: float = 65.0
@export_range(1, 6, 1) var occupied_regions: int = 2
@export var body_color: Color = Color("#6f7650")
@export var attack_ratio: float = 0.0
@export var attack_interval: float = 3.0


func _init() -> void:
	pass
