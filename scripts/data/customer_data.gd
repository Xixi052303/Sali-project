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
# 每种食客按生成时基准胃口乘以该倍率，实际胃口随后锁定在实例中。
@export var appetite_multiplier: float = 1.0
@export var move_speed: float = 65.0
@export_range(1, 6, 1) var occupied_regions: int = 2
@export var body_color: Color = Color("#6f7650")
@export var attack_ratio: float = 0.0
@export var attack_interval: float = 3.0


func _init() -> void:
	pass
