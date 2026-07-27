class_name FoodProjectile
extends Node2D

var run: RunController
var velocity: Vector2 = Vector2.ZERO
var satisfaction: float = 0.0
var radius: float = 16.0
var remaining_hits: int = 1
var food_id: StringName = &"potato"
var visual_color: Color = Color("#e2b650")
var tracking_target: Node2D
var homing_enabled: bool = false
var homing_turn_speed: float = 0.0
var _movement_speed: float = 0.0
var _lifetime_remaining: float = 1.6
var _hit_instances: Dictionary = {}


func configure(
	run_controller: RunController,
	start_position: Vector2,
	direction: Vector2,
	food: FoodData,
	amount: float,
	speed: float,
	hit_radius_value: float,
	lifetime: float,
	hit_count: int,
	target: Node2D,
	should_home: bool
) -> void:
	run = run_controller
	global_position = start_position
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
	rotation = direction.angle() + PI * 0.5
	queue_redraw()


func _process(delta: float) -> void:
	if run == null:
		queue_free()
		return
	_lifetime_remaining -= delta
	if _lifetime_remaining <= 0.0:
		queue_free()
		return
	if homing_enabled and is_instance_valid(tracking_target) and not tracking_target.is_queued_for_deletion():
		var desired_angle: float = (tracking_target.global_position - global_position).angle()
		var next_angle: float = rotate_toward(velocity.angle(), desired_angle, homing_turn_speed * delta)
		velocity = Vector2.RIGHT.rotated(next_angle) * _movement_speed
		rotation = next_angle + PI * 0.5
	position += velocity * delta
	run.resolve_projectile_hits(self)
	if position.y < Playfield.PROJECTILE_TOP_BOUNDARY or position.y > 1450.0 or position.x < -120.0 or position.x > 840.0:
		queue_free()


func can_hit(target: Node2D) -> bool:
	return not _hit_instances.has(target.get_instance_id())


func register_hit(target: Node2D) -> bool:
	_hit_instances[target.get_instance_id()] = true
	remaining_hits -= 1
	if remaining_hits <= 0:
		queue_free()
		return true
	return false


func _draw() -> void:
	if food_id == &"baguette":
		var half_width: float = maxf(10.0, radius)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-half_width * 0.78, -34.0),
			Vector2(half_width * 0.78, -34.0),
			Vector2(half_width, 28.0),
			Vector2(0.0, 40.0),
			Vector2(-half_width, 28.0),
		]), visual_color)
		draw_polyline(PackedVector2Array([
			Vector2(-half_width * 0.78, -34.0),
			Vector2(half_width * 0.78, -34.0),
			Vector2(half_width, 28.0),
			Vector2(0.0, 40.0),
			Vector2(-half_width, 28.0),
			Vector2(-half_width * 0.78, -34.0),
		]), Color("#241f1a"), 4.0)
		for y: float in [-16.0, 2.0, 20.0]:
			draw_line(Vector2(-8.0, y), Vector2(8.0, y + 7.0), Color("#6d3c20"), 3.0)
	else:
		draw_circle(Vector2.ZERO, radius, Color("#241f1a"))
		draw_circle(Vector2.ZERO, maxf(3.0, radius - 4.0), visual_color)
		draw_circle(Vector2(-5.0, -4.0), 2.5, Color("#664424"))
		draw_circle(Vector2(6.0, 5.0), 2.0, Color("#664424"))
