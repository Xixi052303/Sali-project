class_name FoodProjectile3D
extends Node3D

var run: RunController3D
var velocity: Vector3 = Vector3.ZERO
var satisfaction: float = 0.0
var radius: float = 0.16
var remaining_hits: int = 1
var food_id: StringName = &"potato"
var visual_color: Color = Color("#e2b650")
var tracking_target: Node3D
var homing_enabled: bool = false
var homing_turn_speed: float = 0.0
var _movement_speed: float = 0.0
var _lifetime_remaining: float = 1.6
var _hit_instances: Dictionary = {}
@onready var _potato_visual: MeshInstance3D = %PotatoVisual
@onready var _baguette_visual: MeshInstance3D = %BaguetteVisual
@onready var _baguette_box: BoxMesh = _baguette_visual.mesh as BoxMesh


func configure(
	run_controller: RunController3D,
	start_position: Vector3,
	direction: Vector3,
	food: FoodData,
	amount: float,
	speed: float,
	hit_radius_value: float,
	lifetime: float,
	hit_count: int,
	target: Node3D,
	should_home: bool
) -> void:
	_resolve_visual_nodes()
	run = run_controller
	position = start_position
	velocity = direction.normalized() * speed
	_movement_speed = speed
	satisfaction = amount
	radius = hit_radius_value
	_lifetime_remaining = lifetime
	remaining_hits = maxi(1, hit_count)
	food_id = food.id
	visual_color = food.visual_color
	tracking_target = target if should_home else null
	homing_enabled = should_home
	homing_turn_speed = food.homing_turn_speed
	_configure_visual()


func _process(delta: float) -> void:
	if run == null:
		queue_free()
		return
	_lifetime_remaining -= delta
	if _lifetime_remaining <= 0.0:
		queue_free()
		return
	if homing_enabled and is_instance_valid(tracking_target) and not tracking_target.is_queued_for_deletion():
		var desired: Vector3 = run.logic_position(tracking_target) - run.logic_position(self)
		desired.y = 0.0
		var current_angle: float = atan2(velocity.x, -velocity.z)
		var desired_angle: float = atan2(desired.x, -desired.z)
		var next_angle: float = rotate_toward(current_angle, desired_angle, homing_turn_speed * delta)
		velocity = Vector3(sin(next_angle), 0.0, -cos(next_angle)) * _movement_speed
	position += velocity * delta
	rotation.y = atan2(velocity.x, -velocity.z)
	run.resolve_projectile_hits(self)
	if position.z < Playfield.PROJECTILE_FORWARD_BOUNDARY_Z or position.z > 14.5 or position.x < -1.2 or position.x > 8.4:
		queue_free()


func can_hit(target: Node3D) -> bool:
	return not _hit_instances.has(target.get_instance_id())


func register_hit(target: Node3D) -> bool:
	_hit_instances[target.get_instance_id()] = true
	remaining_hits -= 1
	if remaining_hits <= 0:
		queue_free()
		return true
	return false


func planar_position() -> Vector2:
	return Vector2(position.x, position.z)


func _resolve_visual_nodes() -> void:
	if _potato_visual != null:
		return
	_potato_visual = get_node("PotatoVisual") as MeshInstance3D
	_baguette_visual = get_node("BaguetteVisual") as MeshInstance3D
	_baguette_box = _baguette_visual.mesh as BoxMesh


func _configure_visual() -> void:
	_potato_visual.visible = food_id != &"baguette"
	_baguette_visual.visible = food_id == &"baguette"
	if food_id == &"baguette":
		_baguette_box.size = Vector3(maxf(0.2, radius * 1.5), 0.18, 0.8)
		var baguette_material: StandardMaterial3D = _baguette_visual.material_override as StandardMaterial3D
		baguette_material.albedo_color = visual_color
	else:
		var diameter: float = maxf(0.1, radius * 2.0)
		_potato_visual.scale = Vector3.ONE * diameter
		var potato_material: StandardMaterial3D = _potato_visual.material_override as StandardMaterial3D
		potato_material.albedo_color = visual_color
