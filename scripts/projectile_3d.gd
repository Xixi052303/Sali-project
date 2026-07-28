class_name FoodProjectile3D
extends Node3D

const MISS_DISAPPEAR_DURATION: float = 0.2
const POTATO_MODEL_SCENE: PackedScene = preload("res://assets/models/投射物模型/土豆.glb")
const BAGUETTE_MODEL_SCENE: PackedScene = preload("res://assets/models/投射物模型/法棍.glb")
const MUSHROOM_MODEL_SCENE: PackedScene = preload("res://assets/models/投射物模型/蘑菇.glb")
const VISUAL_CENTER_Y: float = 0.82
const POTATO_MODEL_SIZE: Vector3 = Vector3(0.849609375, 0.716796875, 0.998046875)
const BAGUETTE_MODEL_SIZE: Vector3 = Vector3(0.400390625, 0.330078125, 0.998046875)
const MUSHROOM_MODEL_SIZE: Vector3 = Vector3(0.986328125, 0.998046875, 0.912109375)

var run: RunController3D
var velocity: Vector3 = Vector3.ZERO
var satisfaction: float = 0.0
var radius: float = 0.16
var remaining_hits: int = 1
var food_id: StringName = &"potato"
var attack_kind: FoodData.AttackKind = FoodData.AttackKind.PROJECTILE
var visual_color: Color = Color("#e2b650")
var tracking_target: Node3D
var homing_enabled: bool = false
var homing_turn_speed: float = 0.0
var _movement_speed: float = 0.0
var _lifetime_remaining: float = 1.6
var _initial_lifetime: float = 1.6
var _previous_position: Vector3 = Vector3.ZERO
var _hit_instances: Dictionary = {}
var _miss_disappearing: bool = false
var _orbit_angle: float = 0.0
var _orbit_angular_speed: float = 3.2
# 蘑菇用累计转角驱动“驻留一圈、扩张一圈”的半径阶段，不直接读取速度或持续倍率。
var _orbit_travel_angle: float = 0.0
var _orbit_base_radius: float = 1.2
var _breathing_enabled: bool = false
var _breathing_period: float = 1.2
var _breathing_outer_multiplier: float = 2.0
var _sweep_enabled: bool = false
var _sweep_half_length: float = 2.4
@onready var _visual_root: Node3D = %VisualRoot
# 每枚投射物只实例化自身食材模型，避免同时携带三份隐藏网格。
var _food_visual: Node3D


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
	should_home: bool,
	orbit_phase: float,
	sweep_enabled: bool,
	breathing_enabled: bool
) -> void:
	_resolve_visual_nodes()
	run = run_controller
	position = start_position
	_previous_position = start_position
	velocity = direction.normalized() * speed
	_movement_speed = speed
	satisfaction = amount
	radius = hit_radius_value
	attack_kind = food.attack_kind
	_lifetime_remaining = lifetime
	_initial_lifetime = lifetime
	remaining_hits = maxi(1, hit_count)
	food_id = food.id
	visual_color = food.visual_color
	tracking_target = target if should_home else null
	homing_enabled = should_home
	homing_turn_speed = food.homing_turn_speed
	_orbit_angle = orbit_phase
	_orbit_angular_speed = speed
	_orbit_travel_angle = 0.0
	_orbit_base_radius = Playfield.design_to_world(food.orbit_radius)
	_breathing_enabled = breathing_enabled
	_breathing_period = maxf(0.1, food.breathing_period)
	_breathing_outer_multiplier = maxf(1.0, food.breathing_outer_multiplier)
	_sweep_enabled = sweep_enabled
	_configure_visual()


func _process(delta: float) -> void:
	if run == null:
		queue_free()
		return
	_lifetime_remaining -= delta
	if _lifetime_remaining <= 0.0:
		_begin_miss_disappear()
		return
	if attack_kind == FoodData.AttackKind.ORBITING_MUSHROOM:
		_process_orbit(delta)
	else:
		_process_forward_motion(delta)
	run.resolve_projectile_hits(self)
	if is_queued_for_deletion():
		return
	if (
		attack_kind != FoodData.AttackKind.ORBITING_MUSHROOM
		and (
			position.z < Playfield.PROJECTILE_FORWARD_BOUNDARY_Z
			or position.z > 14.5
			or position.x < -1.2
			or position.x > 8.4
		)
	):
		_begin_miss_disappear()


func _process_forward_motion(delta: float) -> void:
	if homing_enabled and is_instance_valid(tracking_target) and not tracking_target.is_queued_for_deletion():
		var desired: Vector3 = run.logic_position(tracking_target) - run.logic_position(self)
		desired.y = 0.0
		var current_angle: float = atan2(velocity.x, -velocity.z)
		var desired_angle: float = atan2(desired.x, -desired.z)
		var next_angle: float = rotate_toward(current_angle, desired_angle, homing_turn_speed * delta)
		velocity = Vector3(sin(next_angle), 0.0, -cos(next_angle)) * _movement_speed
	_previous_position = position
	position += velocity * delta
	var base_rotation: float = atan2(velocity.x, -velocity.z)
	if _sweep_enabled:
		var progress: float = 1.0 - _lifetime_remaining / maxf(0.001, _initial_lifetime)
		rotation.y = base_rotation + lerpf(-PI * 0.5, PI * 0.5, progress)
	else:
		rotation.y = base_rotation


func _process_orbit(delta: float) -> void:
	var angle_step: float = _orbit_angular_speed * delta
	_orbit_angle += angle_step
	_orbit_travel_angle += absf(angle_step)
	var elapsed: float = _initial_lifetime - _lifetime_remaining
	var radius_multiplier: float = 1.0
	if _breathing_enabled:
		var breath_progress: float = 0.5 - 0.5 * cos(TAU * elapsed / _breathing_period)
		radius_multiplier = lerpf(1.0, _breathing_outer_multiplier, breath_progress)
	var center: Vector3 = run.logic_position(run.cart)
	var current_radius: float = _current_orbit_radius() * radius_multiplier
	position = center + Vector3(
		sin(_orbit_angle) * current_radius,
		0.0,
		-cos(_orbit_angle) * current_radius
	)
	rotation.y = -_orbit_angle


# 每档先驻留一圈，再用一圈平滑扩到当前半径的1.5倍。
func _current_orbit_radius() -> float:
	var completed_phase_pairs: int = floori(_orbit_travel_angle / (TAU * 2.0))
	var phase_turns: float = fmod(_orbit_travel_angle / TAU, 2.0)
	var stage_radius: float = _orbit_base_radius * pow(1.5, completed_phase_pairs)
	if phase_turns <= 1.0:
		return stage_radius
	return lerpf(stage_radius, stage_radius * 1.5, phase_turns - 1.0)


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


func overlaps_target(target_position: Vector3, target_radius: float) -> bool:
	var projectile_position: Vector3 = run.logic_position(self)
	if attack_kind == FoodData.AttackKind.ORBITING_MUSHROOM:
		return projectile_position.distance_to(target_position) <= radius + target_radius
	var movement_overlaps: bool = _segment_overlaps_target(
		Vector2(_previous_position.x, _previous_position.z),
		Vector2(projectile_position.x, projectile_position.z),
		Vector2(target_position.x, target_position.z),
		radius + target_radius
	)
	if not _sweep_enabled:
		return movement_overlaps
	var axis: Vector2 = Vector2(sin(rotation.y), -cos(rotation.y))
	var center: Vector2 = Vector2(projectile_position.x, projectile_position.z)
	var target: Vector2 = Vector2(target_position.x, target_position.z)
	var start: Vector2 = center - axis * _sweep_half_length
	var end: Vector2 = center + axis * _sweep_half_length
	return (
		movement_overlaps
		or _segment_overlaps_target(start, end, target, radius + target_radius)
	)


func _segment_overlaps_target(
	start: Vector2,
	end: Vector2,
	target: Vector2,
	combined_radius: float
) -> bool:
	var segment: Vector2 = end - start
	var segment_length_squared: float = maxf(0.0001, segment.length_squared())
	var projection: float = clampf((target - start).dot(segment) / segment_length_squared, 0.0, 1.0)
	var closest: Vector2 = start + segment * projection
	return closest.distance_to(target) <= combined_radius


# 未命中的食材保留短促退场反馈，命中次数耗尽仍立即回收以保持判定干净。
func _begin_miss_disappear() -> void:
	if _miss_disappearing:
		return
	_resolve_visual_nodes()
	_miss_disappearing = true
	tracking_target = null
	homing_enabled = false
	set_process(false)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, MISS_DISAPPEAR_DURATION)
	if _food_visual != null:
		_tween_visual_transparency(tween, _food_visual)
	tween.chain().tween_callback(queue_free)


func is_miss_disappearing() -> bool:
	return _miss_disappearing


func _resolve_visual_nodes() -> void:
	if _visual_root != null:
		return
	_visual_root = get_node("VisualRoot") as Node3D


# 按食材类型装配模型，并把美术尺寸映射到现有表现与判定尺度。
func _configure_visual() -> void:
	if _food_visual != null:
		_food_visual.free()
	var model_scene: PackedScene = POTATO_MODEL_SCENE
	if food_id == &"baguette":
		model_scene = BAGUETTE_MODEL_SCENE
	elif food_id == &"mushroom":
		model_scene = MUSHROOM_MODEL_SCENE
	_food_visual = model_scene.instantiate() as Node3D
	if _food_visual == null:
		push_error("食材模型根节点必须继承 Node3D: %s" % String(food_id))
		return
	_visual_root.add_child(_food_visual)
	if food_id == &"baguette":
		var baguette_length: float = _sweep_half_length * 2.0 if _sweep_enabled else 0.8
		var baguette_width: float = maxf(0.2, radius * 1.5)
		_food_visual.scale = Vector3(
			baguette_width / BAGUETTE_MODEL_SIZE.x,
			0.18 / BAGUETTE_MODEL_SIZE.y,
			baguette_length / BAGUETTE_MODEL_SIZE.z
		)
		_food_visual.position.y = VISUAL_CENTER_Y - 0.09
	elif food_id == &"mushroom":
		var mushroom_diameter: float = maxf(0.18, radius * 2.0)
		var mushroom_scale: float = mushroom_diameter / maxf(
			MUSHROOM_MODEL_SIZE.x,
			MUSHROOM_MODEL_SIZE.z
		)
		_food_visual.scale = Vector3.ONE * mushroom_scale
		_food_visual.position.y = VISUAL_CENTER_Y - MUSHROOM_MODEL_SIZE.y * mushroom_scale * 0.5
	else:
		var diameter: float = maxf(0.1, radius * 2.0)
		var potato_scale: float = diameter / maxf(POTATO_MODEL_SIZE.x, POTATO_MODEL_SIZE.z)
		_food_visual.scale = Vector3.ONE * potato_scale
		_food_visual.position.y = VISUAL_CENTER_Y - POTATO_MODEL_SIZE.y * potato_scale * 0.5


# 导入模型可能包含多层网格，统一淡出所有可绘制子节点。
func _tween_visual_transparency(tween: Tween, visual: Node3D) -> void:
	if visual is GeometryInstance3D:
		tween.tween_property(
			visual as GeometryInstance3D,
			"transparency",
			1.0,
			MISS_DISAPPEAR_DURATION
		)
	for child: Node in visual.find_children("*", "GeometryInstance3D", true, false):
		var geometry: GeometryInstance3D = child as GeometryInstance3D
		if geometry != null:
			tween.tween_property(
				geometry,
				"transparency",
				1.0,
				MISS_DISAPPEAR_DURATION
			)
