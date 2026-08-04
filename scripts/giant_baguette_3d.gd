class_name GiantBaguette3D
extends Node3D

const MODEL_SIZE: Vector3 = Vector3(0.400390625, 0.330078125, 0.998046875)

@onready var _roll_pivot: Node3D = %RollPivot
@onready var _model_scale: Node3D = %ModelScale


# 旋转容器保持单位缩放，巨型法棍模型使用同一比例放大长宽高。
func configure_uniform_scale(scale: float) -> void:
	_resolve_nodes()
	var safe_scale: float = maxf(0.001, scale)
	_model_scale.scale = Vector3.ONE * safe_scale


func set_roll_angle(angle: float) -> void:
	_resolve_nodes()
	_roll_pivot.rotation.z = angle


func model_scale() -> Vector3:
	_resolve_nodes()
	return _model_scale.scale


func _resolve_nodes() -> void:
	if _roll_pivot != null and _model_scale != null:
		return
	_roll_pivot = get_node("RollPivot") as Node3D
	_model_scale = get_node("RollPivot/ModelScale") as Node3D
