class_name FoodProjectile3D
extends Node3D

const MISS_DISAPPEAR_DURATION: float = 0.2
const VISUAL_CENTER_Y: float = 0.82
const CARROT_SWEEP_PIVOT_Z_OFFSET: float = -1.35
const GIANT_BAGUETTE_ROLL_SPEED: float = 6.0
const MAXIMUM_VISUAL_RANGE_SCALE: float = 1.5
const RANGE_OUTLINE_WIDTH: float = 0.035
const ORBIT_SIMULATION_STEP_SECONDS: float = 1.0 / 120.0
const ORBIT_RADIUS_STEP_MULTIPLIER: float = 0.5
# 各模型尺寸来自对应 GLB 的本地 AABB，只用于把美术模型映射到既有表现尺度。
const POTATO_MODEL_SIZE: Vector3 = Vector3(0.849609375, 0.716796875, 0.998046875)
const BAGUETTE_MODEL_SIZE: Vector3 = Vector3(0.400390625, 0.330078125, 0.998046875)
const MUSHROOM_MODEL_SIZE: Vector3 = Vector3(0.986328125, 0.998046875, 0.912109375)
const EGG_MODEL_SIZE: Vector3 = Vector3(0.376953125, 0.998046875, 0.806640625)

var run: RunController3D
var velocity: Vector3 = Vector3.ZERO
var satisfaction: float = 0.0
var radius: float = 0.16
var remaining_hits: int = 1
var food_id: StringName = &"potato"
var attack_kind: FoodData.AttackKind = FoodData.AttackKind.PROJECTILE
var tracking_target: Node3D
var homing_enabled: bool = false
var homing_turn_speed: float = 0.0
var _movement_speed: float = 0.0
# 阶段风势只影响直线位移；瞄准与追踪仍由食材自身方向规则负责。
var _environment_velocity: Vector3 = Vector3.ZERO
var _lifetime_remaining: float = 1.6
var _initial_lifetime: float = 1.6
var _previous_position: Vector3 = Vector3.ZERO
var _hit_instances: Dictionary = {}
var _miss_disappearing: bool = false
var _orbit_angle: float = 0.0
# 配置值表示1倍半径处的角速度；运行时据此锁定切向线速度。
var _orbit_angular_speed: float = 3.2
# 配置完成后缓存，分段外扩与呼吸只改变角速度，不再改变此值。
var _orbit_linear_speed: float = 0.0
# 蘑菇用累计转角驱动翻倍驻留圈数和单圈扩张，不直接读取持续强化倍率。
var _orbit_travel_angle: float = 0.0
var _orbit_base_radius: float = 1.2
var _breathing_enabled: bool = false
var _breathing_period: float = 1.2
var _breathing_outer_multiplier: float = 2.0
var _giant_baguette: bool = false
var _giant_half_width: float = 0.0
var _giant_roll_angle: float = 0.0
var _range_scale: float = 1.0
var _sweep_radius: float = 0.0
var _sweep_half_angle: float = 0.0
var _sweep_angle: float = 0.0
var _sweep_direction: float = 1.0
var _sweep_linear_speed: float = 0.0
# 基础胡萝卜到端点后只自转；取得特殊进化后才恢复端点反向。
var _carrot_bounce_enabled: bool = false
var _carrot_sweep_finished: bool = false
# 端点后的剩余持续时间只累计模型绕自身长轴的自转角度。
var _carrot_spin_angle: float = 0.0
# 食材包装场景的编辑器变换作为基准，运行时只叠加战斗范围带来的动态尺寸。
var _visual_nodes_resolved: bool = false
var _potato_visual_base_scale: Vector3 = Vector3.ONE
var _baguette_visual_base_scale: Vector3 = Vector3.ONE
var _mushroom_visual_base_scale: Vector3 = Vector3.ONE
var _egg_visual_base_scale: Vector3 = Vector3.ONE
var _carrot_visual_base_scale: Vector3 = Vector3.ONE
var _potato_visual_base_position: Vector3 = Vector3.ZERO
var _baguette_visual_base_position: Vector3 = Vector3.ZERO
var _mushroom_visual_base_position: Vector3 = Vector3.ZERO
var _egg_visual_base_position: Vector3 = Vector3.ZERO
var _carrot_visual_base_position: Vector3 = Vector3.ZERO
# 胡萝卜包装根节点的可编辑旋转，以及模型基础缩放；根节点本身就是扫掠轴心。
var _carrot_visual_base_rotation: Vector3 = Vector3.ZERO
# 胡萝卜模型单独缓存编辑器变换，端点后仅绕其本地长轴自转。
var _carrot_model: Node3D
var _carrot_model_base_transform: Transform3D = Transform3D.IDENTITY
# 胡萝卜模型在包装根节点局部空间中的最低点，用于把场景模型自动贴到道路平面。
var _carrot_visual_base_bottom_y: float = 0.0
# 胡萝卜场景中的盒形伤害轮廓；运行时只读取其编辑器变换，不连接物理系统。
var _carrot_damage_hitbox: CollisionShape3D
@onready var _potato_visual: Node3D = %PotatoVisual
@onready var _baguette_visual: Node3D = %BaguetteVisual
@onready var _giant_baguette_visual: GiantBaguette3D = %GiantBaguetteVisual
@onready var _mushroom_visual: Node3D = %MushroomVisual
@onready var _egg_visual: Node3D = %EggVisual
@onready var _carrot_visual: Node3D = %CarrotVisual
@onready var _range_circle_outline: MeshInstance3D = %RangeCircleOutline
@onready var _range_box_outline: Node3D = %RangeBoxOutline
@onready var _range_box_top: MeshInstance3D = %RangeBoxTop
@onready var _range_box_bottom: MeshInstance3D = %RangeBoxBottom
@onready var _range_box_left: MeshInstance3D = %RangeBoxLeft
@onready var _range_box_right: MeshInstance3D = %RangeBoxRight


func configure(
	run_controller: RunController3D,
	start_position: Vector3,
	direction: Vector3,
	food: FoodData,
	amount: float,
	speed: float,
	environment_velocity: Vector3,
	hit_radius_value: float,
	lifetime: float,
	hit_count: int,
	target: Node3D,
	should_home: bool,
	orbit_phase: float,
	giant_baguette: bool,
	giant_width: float,
	breathing_enabled: bool
) -> void:
	_resolve_visual_nodes()
	run = run_controller
	position = start_position
	_previous_position = start_position
	_environment_velocity = environment_velocity
	velocity = direction.normalized() * speed + _environment_velocity
	_movement_speed = speed
	satisfaction = amount
	radius = hit_radius_value
	_range_scale = radius / maxf(0.001, Playfield.design_to_world(food.projectile_radius))
	attack_kind = food.attack_kind
	_lifetime_remaining = lifetime
	_initial_lifetime = lifetime
	remaining_hits = maxi(1, hit_count)
	food_id = food.id
	_carrot_bounce_enabled = (
		food.id == &"carrot"
		and run.state != null
		and run.state.has_food_evolution(&"carrot_bounce")
	)
	_carrot_sweep_finished = false
	_carrot_spin_angle = 0.0
	tracking_target = target if should_home else null
	homing_enabled = should_home
	homing_turn_speed = food.homing_turn_speed
	_orbit_angle = orbit_phase
	_orbit_angular_speed = speed
	_orbit_travel_angle = 0.0
	_orbit_base_radius = Playfield.design_to_world(food.orbit_radius)
	_orbit_linear_speed = absf(_orbit_angular_speed) * _orbit_base_radius
	_breathing_enabled = breathing_enabled
	_breathing_period = maxf(0.1, food.breathing_period)
	_breathing_outer_multiplier = maxf(1.0, food.breathing_outer_multiplier)
	_giant_baguette = giant_baguette
	_giant_half_width = maxf(0.0, giant_width * 0.5)
	_giant_roll_angle = 0.0
	_sweep_radius = Playfield.design_to_world(food.sweep_radius)
	_sweep_half_angle = deg_to_rad(food.sweep_angle_degrees * 0.5)
	_sweep_linear_speed = maxf(0.001, speed)
	if attack_kind == FoodData.AttackKind.CARROT_SWEEP:
		_configure_sweep_phase(orbit_phase)
	_configure_visual()
	if attack_kind == FoodData.AttackKind.CARROT_SWEEP:
		_set_sweep_position()


func _process(delta: float) -> void:
	if run == null:
		queue_free()
		return
	_lifetime_remaining -= delta
	var active_delta: float = delta
	var carrot_expires_after_step: bool = false
	if _lifetime_remaining <= 0.0:
		if attack_kind != FoodData.AttackKind.CARROT_SWEEP:
			_begin_miss_disappear()
			return
		# 胡萝卜到期帧仍先走完剩余弧段，保证基础0.5秒包含完整180度单程。
		active_delta = maxf(0.0, delta + _lifetime_remaining)
		if active_delta <= 0.0:
			_begin_miss_disappear()
			return
		carrot_expires_after_step = true
	if attack_kind == FoodData.AttackKind.ORBITING_MUSHROOM:
		_process_orbit(active_delta)
	elif attack_kind == FoodData.AttackKind.CARROT_SWEEP:
		_process_carrot_sweep(active_delta)
	else:
		_process_forward_motion(active_delta)
	run.resolve_projectile_hits(self)
	if is_queued_for_deletion():
		return
	if carrot_expires_after_step:
		_begin_miss_disappear()
		return
	if (
		attack_kind not in [
			FoodData.AttackKind.ORBITING_MUSHROOM,
			FoodData.AttackKind.CARROT_SWEEP,
		]
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
		velocity = (
			Vector3(sin(next_angle), 0.0, -cos(next_angle)) * _movement_speed
			+ _environment_velocity
		)
	_previous_position = position
	position += velocity * delta
	if _giant_baguette:
		_giant_roll_angle = fmod(_giant_roll_angle + GIANT_BAGUETTE_ROLL_SPEED * delta, TAU)
		_giant_baguette_visual.set_roll_angle(_giant_roll_angle)
		return
	# 模型的前端沿本地-Z；绕Y轴需使用运动方向角的相反数。
	rotation.y = atan2(-velocity.x, -velocity.z)


# 胡萝卜固定跟随餐车，在前方弧线上按切向线速度扫掠；端点回弹由特殊进化开启。
func _process_carrot_sweep(delta: float) -> void:
	_previous_position = position
	var angular_speed: float = _sweep_linear_speed / maxf(0.001, _sweep_radius)
	var remaining_delta: float = maxf(0.0, delta)
	while remaining_delta > 0.000001:
		if _carrot_sweep_finished:
			_spin_carrot_model(remaining_delta, angular_speed)
			remaining_delta = 0.0
			break
		var remaining_angle: float = (
			_sweep_half_angle - _sweep_angle
			if _sweep_direction > 0.0
			else _sweep_angle + _sweep_half_angle
		)
		var angle_step: float = angular_speed * remaining_delta
		if angle_step < remaining_angle - 0.000001:
			_sweep_angle += angle_step * _sweep_direction
			remaining_delta = 0.0
		else:
			_sweep_angle += remaining_angle * _sweep_direction
			remaining_delta = maxf(
				0.0,
				remaining_delta - remaining_angle / maxf(0.001, angular_speed)
			)
			if _carrot_bounce_enabled:
				_sweep_direction *= -1.0
				# 每次到达另一端代表一个新的单程，允许目标在下一程再次受击。
				_hit_instances.clear()
			else:
				_carrot_sweep_finished = true
				_spin_carrot_model(remaining_delta, angular_speed)
				remaining_delta = 0.0
	_set_sweep_position()


func _configure_sweep_phase(phase: float) -> void:
	var normalized_phase: float = fposmod(phase, TAU) / TAU
	if normalized_phase <= 0.5:
		_sweep_angle = lerpf(
			-_sweep_half_angle,
			_sweep_half_angle,
			normalized_phase * 2.0
		)
		_sweep_direction = 1.0
	else:
		_sweep_angle = lerpf(
			_sweep_half_angle,
			-_sweep_half_angle,
			(normalized_phase - 0.5) * 2.0
		)
		_sweep_direction = -1.0


func _set_sweep_position() -> void:
	var center: Vector3 = _carrot_sweep_pivot_position()
	position = center + Vector3(
		sin(_sweep_angle) * _sweep_radius,
		0.0,
		-cos(_sweep_angle) * _sweep_radius
	)
	_update_carrot_visual_transform(center)


# 胡萝卜扫掠轴心位于餐车前方的厨师工作点，模型原点围绕此点旋转。
func _carrot_sweep_pivot_position() -> Vector3:
	return run.logic_position(run.cart) + Vector3(
		0.0,
		0.0,
		CARROT_SWEEP_PIVOT_Z_OFFSET
	)


# 胡萝卜模型作为餐车前方长杆，以扫掠端点方向旋转；实际命中读取场景中的整根盒形轮廓。
func _update_carrot_visual_transform(center: Vector3) -> void:
	var outward: Vector3 = position - center
	var yaw: float = atan2(-outward.x, -outward.z)
	_carrot_visual.rotation = _carrot_visual_base_rotation
	_carrot_visual.rotation.y += yaw
	if _carrot_model != null:
		_carrot_model.transform = _carrot_model_base_transform
		_carrot_model.rotate_object_local(Vector3.FORWARD, _carrot_spin_angle)
	var desired_pivot: Vector3 = center + Vector3(
		0.0,
		_carrot_visual_ground_y(),
		0.0
	)
	# 不补偿Model子节点偏移，保证CarrotVisual根节点的0点就是旋转轴心。
	_carrot_visual.position = (
		desired_pivot
		- position
		+ _carrot_visual_base_position
	)


# 端点后的剩余时间只让胡萝卜绕自身本地-Z长轴旋转，扫掠轴心保持不动。
func _spin_carrot_model(delta: float, angular_speed: float) -> void:
	if _carrot_model == null:
		return
	_carrot_spin_angle = fposmod(
		_carrot_spin_angle + maxf(0.0, delta) * angular_speed,
		TAU
	)


func _carrot_visual_ground_y() -> float:
	return -_carrot_visual_base_bottom_y * absf(_carrot_visual.scale.y)


func _process_orbit(delta: float) -> void:
	var remaining_delta: float = maxf(0.0, delta)
	var elapsed_end: float = maxf(0.0, _initial_lifetime - _lifetime_remaining)
	var elapsed_start: float = maxf(0.0, elapsed_end - remaining_delta)
	var simulated_seconds: float = 0.0
	var angle_direction: float = -1.0 if _orbit_angular_speed < 0.0 else 1.0
	while remaining_delta > 0.000001:
		var step_seconds: float = minf(remaining_delta, ORBIT_SIMULATION_STEP_SECONDS)
		var midpoint_elapsed: float = elapsed_start + simulated_seconds + step_seconds * 0.5
		var actual_radius: float = maxf(
			0.001,
			_current_orbit_radius() * _breathing_multiplier_at_elapsed(midpoint_elapsed)
		)
		var angle_step: float = _orbit_linear_speed / actual_radius * step_seconds
		_orbit_angle += angle_step * angle_direction
		_orbit_travel_angle += angle_step
		simulated_seconds += step_seconds
		remaining_delta = maxf(0.0, remaining_delta - step_seconds)
	var center: Vector3 = run.logic_position(run.cart)
	var current_radius: float = (
		_current_orbit_radius() * _breathing_multiplier_at_elapsed(elapsed_end)
	)
	position = center + Vector3(
		sin(_orbit_angle) * current_radius,
		0.0,
		-cos(_orbit_angle) * current_radius
	)
	rotation.y = -_orbit_angle

# 每档驻留圈数按1、2、4、8翻倍，随后用一圈把半径线性增加0.5倍基础半径。
func _current_orbit_radius() -> float:
	return _orbit_base_radius * orbit_radius_multiplier_at_turns(_orbit_travel_angle / TAU)


# 累计圈数只决定所处驻留或扩张阶段，时间速度由当前半径另行反算。
static func orbit_radius_multiplier_at_turns(travel_turns: float) -> float:
	var remaining_turns: float = maxf(0.0, travel_turns)
	var stage_index: int = 0
	var hold_turns: float = 1.0
	# 128档已远超任何可运行时长，同时避免异常无穷输入形成死循环。
	while stage_index < 128:
		var stage_multiplier: float = 1.0 + float(stage_index) * ORBIT_RADIUS_STEP_MULTIPLIER
		if remaining_turns <= hold_turns:
			return stage_multiplier
		remaining_turns -= hold_turns
		if remaining_turns <= 1.0:
			return lerpf(
				stage_multiplier,
				stage_multiplier + ORBIT_RADIUS_STEP_MULTIPLIER,
				remaining_turns
			)
		remaining_turns -= 1.0
		stage_index += 1
		hold_turns *= 2.0
	return 1.0 + float(stage_index) * ORBIT_RADIUS_STEP_MULTIPLIER


# 呼吸进化改变实际轨道半径，角速度会在同一帧按该半径反向调整。
func _breathing_multiplier_at_elapsed(elapsed: float) -> float:
	if not _breathing_enabled:
		return 1.0
	var breath_progress: float = 0.5 - 0.5 * cos(TAU * elapsed / _breathing_period)
	return lerpf(1.0, _breathing_outer_multiplier, breath_progress)


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
	if attack_kind == FoodData.AttackKind.CARROT_SWEEP:
		return _carrot_hitbox_overlaps_target(target_position, target_radius)
	if attack_kind == FoodData.AttackKind.ORBITING_MUSHROOM:
		return projectile_position.distance_to(target_position) <= radius + target_radius
	var movement_overlaps: bool = _segment_overlaps_target(
		Vector2(_previous_position.x, _previous_position.z),
		Vector2(projectile_position.x, projectile_position.z),
		Vector2(target_position.x, target_position.z),
		radius + target_radius
	)
	if not _giant_baguette:
		return movement_overlaps
	# 巨型法棍横跨道路X轴，并用前后帧包围盒避免高弹速漏判。
	var target: Vector2 = Vector2(target_position.x, target_position.z)
	var min_x: float = minf(_previous_position.x, projectile_position.x) - _giant_half_width
	var max_x: float = maxf(_previous_position.x, projectile_position.x) + _giant_half_width
	var min_z: float = minf(_previous_position.z, projectile_position.z)
	var max_z: float = maxf(_previous_position.z, projectile_position.z)
	var closest: Vector2 = Vector2(
		clampf(target.x, min_x, max_x),
		clampf(target.y, min_z, max_z)
	)
	return closest.distance_to(target) <= radius + target_radius


# 使用胡萝卜场景中的盒形轮廓判断它是否覆盖一个门板矩形。
func overlaps_target_rect(target_space: Node3D, target_rect: Rect2) -> bool:
	if attack_kind != FoodData.AttackKind.CARROT_SWEEP:
		var local_position_3d: Vector3 = target_space.to_local(global_position)
		return target_rect.grow(radius).has_point(
			Vector2(local_position_3d.x, local_position_3d.z)
		)
	var corners: PackedVector2Array = _carrot_hitbox_corners_in_space(target_space)
	if corners.is_empty():
		var fallback_position: Vector3 = target_space.to_local(global_position)
		return target_rect.grow(radius).has_point(
			Vector2(fallback_position.x, fallback_position.z)
		)
	return _oriented_box_overlaps_rect(corners, target_rect.grow(radius))


# 以整根胡萝卜的编辑器盒形轮廓处理食客与Boss目标，并将目标半径换算到轮廓局部坐标。
func _carrot_hitbox_overlaps_target(target_position: Vector3, target_radius: float) -> bool:
	if _carrot_damage_hitbox == null:
		return _segment_overlaps_target(
			Vector2(_previous_position.x, _previous_position.z),
			Vector2(position.x, position.z),
			Vector2(target_position.x, target_position.z),
			radius + target_radius
		)
	var box_shape: BoxShape3D = _carrot_damage_hitbox.shape as BoxShape3D
	if box_shape == null:
		return _segment_overlaps_target(
			Vector2(_previous_position.x, _previous_position.z),
			Vector2(position.x, position.z),
			Vector2(target_position.x, target_position.z),
			radius + target_radius
		)
	var hitbox_to_run: Transform3D = (
		run.global_transform.affine_inverse()
		* _carrot_damage_hitbox.global_transform
	)
	var target_local: Vector3 = hitbox_to_run.affine_inverse() * target_position
	var x_scale: float = maxf(0.001, hitbox_to_run.basis.x.length())
	var z_scale: float = maxf(0.001, hitbox_to_run.basis.z.length())
	var half_size: Vector3 = box_shape.size * 0.5
	return (
		absf(target_local.x) <= half_size.x + target_radius / x_scale
		and absf(target_local.z) <= half_size.z + target_radius / z_scale
	)


# 将场景盒形轮廓的四个地面角点转换到目标节点局部空间，供门板矩形复用。
func _carrot_hitbox_corners_in_space(target_space: Node3D) -> PackedVector2Array:
	if _carrot_damage_hitbox == null:
		return PackedVector2Array()
	var box_shape: BoxShape3D = _carrot_damage_hitbox.shape as BoxShape3D
	if box_shape == null:
		return PackedVector2Array()
	var hitbox_to_space: Transform3D = (
		target_space.global_transform.affine_inverse()
		* _carrot_damage_hitbox.global_transform
	)
	var half_size: Vector3 = box_shape.size * 0.5
	var local_corners: Array[Vector3] = [
		Vector3(-half_size.x, 0.0, -half_size.z),
		Vector3(half_size.x, 0.0, -half_size.z),
		Vector3(half_size.x, 0.0, half_size.z),
		Vector3(-half_size.x, 0.0, half_size.z),
	]
	var corners: PackedVector2Array = PackedVector2Array()
	for local_corner: Vector3 in local_corners:
		var corner: Vector3 = hitbox_to_space * local_corner
		corners.append(Vector2(corner.x, corner.z))
	return corners


# 用分离轴检测旋转盒与门板矩形，确保整根胡萝卜横跨门板时也能命中。
func _oriented_box_overlaps_rect(corners: PackedVector2Array, target_rect: Rect2) -> bool:
	var axes: Array[Vector2] = [Vector2.RIGHT, Vector2.UP]
	for index: int in range(corners.size()):
		var next_index: int = (index + 1) % corners.size()
		var edge: Vector2 = corners[next_index] - corners[index]
		if edge.length_squared() > 0.000001:
			axes.append(Vector2(-edge.y, edge.x).normalized())
	var rect_corners: Array[Vector2] = [
		target_rect.position,
		target_rect.position + Vector2(target_rect.size.x, 0.0),
		target_rect.position + target_rect.size,
		target_rect.position + Vector2(0.0, target_rect.size.y),
	]
	for axis: Vector2 in axes:
		var box_min: float = INF
		var box_max: float = -INF
		for corner: Vector2 in corners:
			var projection: float = corner.dot(axis)
			box_min = minf(box_min, projection)
			box_max = maxf(box_max, projection)
		var rect_min: float = INF
		var rect_max: float = -INF
		for corner: Vector2 in rect_corners:
			var projection: float = corner.dot(axis)
			rect_min = minf(rect_min, projection)
			rect_max = maxf(rect_max, projection)
		if box_max < rect_min or rect_max < box_min:
			return false
	return true


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
	_tween_visual_transparency(tween, _potato_visual)
	_tween_visual_transparency(tween, _baguette_visual)
	_tween_visual_transparency(tween, _giant_baguette_visual)
	_tween_visual_transparency(tween, _mushroom_visual)
	_tween_visual_transparency(tween, _egg_visual)
	_tween_visual_transparency(tween, _carrot_visual)
	_tween_visual_transparency(tween, _range_circle_outline)
	_tween_visual_transparency(tween, _range_box_outline)
	tween.chain().tween_callback(queue_free)


func is_miss_disappearing() -> bool:
	return _miss_disappearing


func _resolve_visual_nodes() -> void:
	if _visual_nodes_resolved:
		return
	_potato_visual = get_node("PotatoVisual") as Node3D
	_baguette_visual = get_node("BaguetteVisual") as Node3D
	_giant_baguette_visual = get_node("GiantBaguetteVisual") as GiantBaguette3D
	_mushroom_visual = get_node("MushroomVisual") as Node3D
	_egg_visual = get_node("EggVisual") as Node3D
	_carrot_visual = get_node("CarrotVisual") as Node3D
	_range_circle_outline = get_node("RangeCircleOutline") as MeshInstance3D
	_range_box_outline = get_node("RangeBoxOutline") as Node3D
	_range_box_top = get_node("RangeBoxOutline/RangeBoxTop") as MeshInstance3D
	_range_box_bottom = get_node("RangeBoxOutline/RangeBoxBottom") as MeshInstance3D
	_range_box_left = get_node("RangeBoxOutline/RangeBoxLeft") as MeshInstance3D
	_range_box_right = get_node("RangeBoxOutline/RangeBoxRight") as MeshInstance3D
	_potato_visual_base_scale = _potato_visual.scale
	_baguette_visual_base_scale = _baguette_visual.scale
	_mushroom_visual_base_scale = _mushroom_visual.scale
	_egg_visual_base_scale = _egg_visual.scale
	_carrot_visual_base_scale = _carrot_visual.scale
	_potato_visual_base_position = _potato_visual.position
	_baguette_visual_base_position = _baguette_visual.position
	_mushroom_visual_base_position = _mushroom_visual.position
	_egg_visual_base_position = _egg_visual.position
	_carrot_visual_base_position = _carrot_visual.position
	_carrot_visual_base_rotation = _carrot_visual.rotation
	_carrot_model = _carrot_visual.get_node_or_null("Model") as Node3D
	if _carrot_model != null:
		_carrot_model_base_transform = _carrot_model.transform
	_cache_carrot_visual_bottom_y()
	_carrot_damage_hitbox = _carrot_visual.get_node_or_null("DamageHitbox") as CollisionShape3D
	_visual_nodes_resolved = true


# 读取包装场景中所有网格的最低点，避免胡萝卜沿用普通投射物高度后悬空。
func _cache_carrot_visual_bottom_y() -> void:
	var bottom_y: float = INF
	var found_geometry: bool = false
	for child: Node in _carrot_visual.find_children("*", "VisualInstance3D", true, false):
		var visual: VisualInstance3D = child as VisualInstance3D
		if visual == null:
			continue
		var visual_to_carrot: Transform3D = (
			_carrot_visual.global_transform.affine_inverse()
			* visual.global_transform
		)
		var local_aabb: AABB = visual.get_aabb()
		for corner_index: int in range(8):
			var local_corner: Vector3 = Vector3(
				local_aabb.position.x + (local_aabb.size.x if (corner_index & 1) != 0 else 0.0),
				local_aabb.position.y + (local_aabb.size.y if (corner_index & 2) != 0 else 0.0),
				local_aabb.position.z + (local_aabb.size.z if (corner_index & 4) != 0 else 0.0)
			)
			var corner_in_carrot: Vector3 = visual_to_carrot * local_corner
			bottom_y = minf(bottom_y, corner_in_carrot.y)
			found_geometry = true
	_carrot_visual_base_bottom_y = bottom_y if found_geometry else 0.0


# 按食材类型装配模型，并把美术尺寸映射到现有表现与判定尺度。
func _configure_visual() -> void:
	_potato_visual.visible = food_id == &"potato"
	_baguette_visual.visible = food_id == &"baguette" and not _giant_baguette
	_giant_baguette_visual.visible = food_id == &"baguette" and _giant_baguette
	_mushroom_visual.visible = food_id == &"mushroom"
	_egg_visual.visible = food_id == &"egg"
	_carrot_visual.visible = food_id == &"carrot"
	_range_circle_outline.visible = false
	_range_box_outline.visible = false
	var visual_range_scale: float = minf(_range_scale, MAXIMUM_VISUAL_RANGE_SCALE)
	if food_id == &"baguette":
		var baguette_length: float = 0.8 * visual_range_scale
		var baguette_width: float = 0.2 * visual_range_scale
		var baguette_height: float = 0.18 * visual_range_scale
		if _giant_baguette:
			var giant_base_width: float = (
				_giant_half_width * 2.0 / maxf(0.001, _range_scale)
			)
			var giant_visual_span: Vector2 = _road_clipped_span(
				giant_base_width * visual_range_scale
			)
			# 以可见长度反推单一模型比例，保证巨型法棍长宽高同步放大。
			var giant_uniform_scale: float = (
				giant_visual_span.y / maxf(0.001, GiantBaguette3D.MODEL_SIZE.z)
			)
			_giant_baguette_visual.configure_uniform_scale(giant_uniform_scale)
			_giant_baguette_visual.position.x = giant_visual_span.x
			_giant_baguette_visual.position.y = VISUAL_CENTER_Y
			if _range_scale > MAXIMUM_VISUAL_RANGE_SCALE:
				var giant_outline_span: Vector2 = _road_clipped_span(
					_giant_half_width * 2.0
				)
				_configure_box_outline(
					giant_outline_span.y,
					0.2 * _range_scale,
					giant_outline_span.x
				)
		else:
			_baguette_visual.scale = _baguette_visual_base_scale * Vector3(
				baguette_width / BAGUETTE_MODEL_SIZE.x,
				baguette_height / BAGUETTE_MODEL_SIZE.y,
				baguette_length / BAGUETTE_MODEL_SIZE.z
			)
			_baguette_visual.position = _baguette_visual_base_position + Vector3(
				0.0,
				VISUAL_CENTER_Y - baguette_height * 0.5,
				0.0
			)
			if _range_scale > MAXIMUM_VISUAL_RANGE_SCALE:
				_configure_box_outline(0.2 * _range_scale, 0.8 * _range_scale)
	elif food_id == &"mushroom":
		var base_radius: float = radius / maxf(0.001, _range_scale)
		var mushroom_diameter: float = maxf(0.18, base_radius * visual_range_scale * 2.0)
		var mushroom_scale: float = mushroom_diameter / maxf(
			MUSHROOM_MODEL_SIZE.x,
			MUSHROOM_MODEL_SIZE.z
		)
		_mushroom_visual.scale = _mushroom_visual_base_scale * Vector3.ONE * mushroom_scale
		_mushroom_visual.position = _mushroom_visual_base_position + Vector3(
			0.0,
			VISUAL_CENTER_Y - MUSHROOM_MODEL_SIZE.y * mushroom_scale * 0.5,
			0.0
		)
		if _range_scale > MAXIMUM_VISUAL_RANGE_SCALE:
			_configure_circle_outline(radius)
	elif food_id == &"egg":
		var base_radius: float = radius / maxf(0.001, _range_scale)
		var diameter: float = maxf(0.1, base_radius * visual_range_scale * 2.0)
		var egg_scale: float = diameter / maxf(EGG_MODEL_SIZE.x, EGG_MODEL_SIZE.z)
		_egg_visual.scale = _egg_visual_base_scale * Vector3.ONE * egg_scale
		_egg_visual.position = _egg_visual_base_position + Vector3(
			0.0,
			VISUAL_CENTER_Y - EGG_MODEL_SIZE.y * egg_scale * 0.5,
			0.0
		)
		if _range_scale > MAXIMUM_VISUAL_RANGE_SCALE:
			_configure_circle_outline(radius)
	elif food_id == &"carrot":
		# 初始尺寸完全来自 carrot_3d.tscn；范围强化只在此基础上等比放大模型与整根判定形状。
		_carrot_visual.scale = _carrot_visual_base_scale * Vector3.ONE * visual_range_scale
		if _range_scale > MAXIMUM_VISUAL_RANGE_SCALE:
			_configure_circle_outline(radius)
	else:
		var base_radius: float = radius / maxf(0.001, _range_scale)
		var diameter: float = maxf(0.1, base_radius * visual_range_scale * 2.0)
		var potato_scale: float = diameter / maxf(POTATO_MODEL_SIZE.x, POTATO_MODEL_SIZE.z)
		_potato_visual.visible = true
		_potato_visual.scale = _potato_visual_base_scale * Vector3.ONE * potato_scale
		_potato_visual.position = _potato_visual_base_position + Vector3(
			0.0,
			VISUAL_CENTER_Y - POTATO_MODEL_SIZE.y * potato_scale * 0.5,
			0.0
		)
		if _range_scale > MAXIMUM_VISUAL_RANGE_SCALE:
			_configure_circle_outline(radius)


func _configure_circle_outline(outline_radius: float) -> void:
	var torus: TorusMesh = _range_circle_outline.mesh as TorusMesh
	var outer_radius: float = maxf(RANGE_OUTLINE_WIDTH * 2.0, outline_radius)
	var inner_radius: float = maxf(RANGE_OUTLINE_WIDTH, outer_radius - RANGE_OUTLINE_WIDTH)
	if outer_radius >= torus.outer_radius:
		torus.outer_radius = outer_radius
		torus.inner_radius = inner_radius
	else:
		torus.inner_radius = inner_radius
		torus.outer_radius = outer_radius
	_range_circle_outline.visible = true


func _road_clipped_span(full_width: float) -> Vector2:
	var half_width: float = maxf(0.0, full_width * 0.5)
	var local_road_left: float = Playfield.ROAD_LEFT - position.x
	var local_road_right: float = Playfield.ROAD_LEFT + Playfield.ROAD_WIDTH - position.x
	var clipped_left: float = maxf(-half_width, local_road_left)
	var clipped_right: float = minf(half_width, local_road_right)
	var clipped_width: float = maxf(0.0, clipped_right - clipped_left)
	return Vector2((clipped_left + clipped_right) * 0.5, clipped_width)


func _configure_box_outline(width: float, depth: float, center_x: float = 0.0) -> void:
	var safe_width: float = maxf(RANGE_OUTLINE_WIDTH * 2.0, width)
	var safe_depth: float = maxf(RANGE_OUTLINE_WIDTH * 2.0, depth)
	_range_box_outline.position.x = center_x
	_range_box_top.position = Vector3(0.0, 0.0, -safe_depth * 0.5)
	_range_box_bottom.position = Vector3(0.0, 0.0, safe_depth * 0.5)
	_range_box_left.position = Vector3(-safe_width * 0.5, 0.0, 0.0)
	_range_box_right.position = Vector3(safe_width * 0.5, 0.0, 0.0)
	_range_box_top.scale = Vector3(safe_width, 0.02, RANGE_OUTLINE_WIDTH)
	_range_box_bottom.scale = Vector3(safe_width, 0.02, RANGE_OUTLINE_WIDTH)
	_range_box_left.scale = Vector3(RANGE_OUTLINE_WIDTH, 0.02, safe_depth)
	_range_box_right.scale = Vector3(RANGE_OUTLINE_WIDTH, 0.02, safe_depth)
	_range_box_outline.visible = true


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
