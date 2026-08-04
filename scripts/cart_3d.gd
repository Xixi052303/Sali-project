class_name Cart3D
extends Node3D

signal damaged(amount: float)
signal destroyed

const BASE_MOVE_SPEED: float = 9.0
const BASE_MOVE_SPEED_DESIGN: float = BASE_MOVE_SPEED / Playfield.WORLD_UNITS_PER_PIXEL
# 无场景节点的规则测试仍使用这份几何回退；实机场景以 CollisionHitbox 为准。
const COLLISION_RECT: Rect2 = Rect2(-0.96, -1.5, 1.92, 2.17)
const MAXIMUM_FEEDBACK_DURATION: float = 1.2
const DEFAULT_INVINCIBILITY_DURATION_SECONDS: float = 0.5
const SHIELD_COLOR: Color = Color("#78d8ff")

var state: RunState
var playfield: Playfield
var target_x: float = 3.6
var target_z: float = Playfield.CART_Z
# Boss 战期间保留开战站位作为后方边界，结束后也据此恢复普通横移状态。
var _default_z: float = Playfield.CART_Z
var _boss_movement_active: bool = false
var _boss_target: PrototypeBoss3D
var _primary_touch_active: bool = false
var _mouse_drag_active: bool = false
# 每次实际受击后使用本局载入的无敌时长，避免运行中热改造成前后不一致。
var _invincibility_duration_seconds: float = DEFAULT_INVINCIBILITY_DURATION_SECONDS
var _invincible_remaining: float = 0.0
var _upgrade_feedback_remaining: float = 0.0
var _maximum_feedback_remaining: float = 0.0
var _last_maximum_durability: float = 0.0
var _upgrade_tween: Tween
# 保存编辑器配置的基础尺寸，碰撞与反馈动画都以它为准。
var _base_scale: Vector3 = Vector3.ONE
# 从场景缓存可编辑的餐车碰撞节点；没有完整场景时允许为空并走默认几何。
var _collision_shape: CollisionShape3D
@onready var _visual_root: Node3D = %PaperCartVisual
@onready var _durability_label: Label3D = %DurabilityLabel
@onready var _maximum_durability_label: Label3D = %DurabilityLabel2
@onready var _effective_durability_label: Label3D = %ShieldDurabilityLabel
@onready var _maximum_feedback_label: Label3D = %MaximumFeedbackLabel


func configure(
	run_state: RunState,
	field: Playfield,
	invincibility_duration_seconds: float = DEFAULT_INVINCIBILITY_DURATION_SECONDS
) -> void:
	state = run_state
	playfield = field
	_invincibility_duration_seconds = maxf(0.0, invincibility_duration_seconds)
	_base_scale = scale
	target_x = position.x
	target_z = position.z
	_default_z = position.z
	set_durability_display(
		state.current_durability,
		state.maximum_durability,
		state.temporary_shield
	)


func _physics_process(delta: float) -> void:
	if state == null or playfield == null:
		return
	if _invincible_remaining > 0.0:
		_invincible_remaining = maxf(0.0, _invincible_remaining - delta)
		_visual_root.visible = int(_invincible_remaining * 12.0) % 2 != 0
	else:
		_visual_root.visible = true
	if _upgrade_feedback_remaining > 0.0:
		_upgrade_feedback_remaining = maxf(0.0, _upgrade_feedback_remaining - delta)
	if _maximum_feedback_remaining > 0.0:
		_maximum_feedback_remaining = maxf(0.0, _maximum_feedback_remaining - delta)
		_maximum_feedback_label.visible = _maximum_feedback_remaining > 0.0
	var speed: float = (
		BASE_MOVE_SPEED * clampf(state.cart_base_speed_factor, 0.0, 1.0)
		+ Playfield.design_to_world(state.effective_cart_speed_bonus(BASE_MOVE_SPEED_DESIGN))
	)
	var current_position: Vector2 = Vector2(position.x, position.z)
	var movement_target: Vector2 = Vector2(target_x, target_z if _boss_movement_active else position.z)
	var next_position: Vector2 = current_position.move_toward(movement_target, speed * delta)
	next_position.x = playfield.clamp_cart_x(next_position.x)
	if _boss_movement_active:
		next_position.y = clampf(next_position.y, boss_minimum_z(), _default_z)
	position.x = next_position.x
	position.z = next_position.y


func _unhandled_input(event: InputEvent) -> void:
	if playfield == null:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.index == 0:
			_primary_touch_active = touch.pressed
			if touch.pressed:
				_set_pointer_target(touch.position)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == 0 and _primary_touch_active:
			_set_pointer_target(drag.position)
	elif event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_mouse_drag_active = mouse_button.pressed
			if mouse_button.pressed:
				_set_pointer_target(mouse_button.position)
	elif event is InputEventMouseMotion and _mouse_drag_active:
		var mouse_motion: InputEventMouseMotion = event
		_set_pointer_target(mouse_motion.position)


# 普通阶段沿用设计像素横移；Boss 阶段把指针投影到道路平面以同时取得 X/Z 目标。
func _set_pointer_target(screen_position: Vector2) -> void:
	if not _boss_movement_active:
		target_x = playfield.clamp_cart_x(Playfield.design_to_world(screen_position.x))
		return
	var ground_position: Vector3 = _screen_to_ground(screen_position)
	target_x = playfield.clamp_cart_x(ground_position.x)
	target_z = clampf(ground_position.z, boss_minimum_z(), _default_z)


# 斜俯相机下用地面射线恢复真实道路坐标；无活动相机时维持现有横向映射。
func _screen_to_ground(screen_position: Vector2) -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return Vector3(Playfield.design_to_world(screen_position.x), 0.0, target_z)
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	if is_zero_approx(ray_direction.y):
		return Vector3(Playfield.design_to_world(screen_position.x), 0.0, target_z)
	var ray_distance: float = -ray_origin.y / ray_direction.y
	if ray_distance < 0.0:
		return Vector3(Playfield.design_to_world(screen_position.x), 0.0, target_z)
	return ray_origin + ray_direction * ray_distance


# Boss 模式只扩展纵向自由度，二维合速度继续复用现有横移速度。
func begin_boss_movement(active_boss: PrototypeBoss3D) -> void:
	_boss_target = active_boss
	_boss_movement_active = is_instance_valid(_boss_target)
	_default_z = position.z
	target_z = position.z


func end_boss_movement() -> void:
	_boss_movement_active = false
	_boss_target = null
	position.z = _default_z
	target_z = _default_z


# 前边界包含 Boss 命中半径与餐车前缘，避免视觉主体相交后才被判定为越过。
func boss_minimum_z() -> float:
	if not _boss_movement_active or not is_instance_valid(_boss_target):
		return _default_z
	var local_collision_rect: Rect2 = _collision_rect_local()
	var cart_forward_extent: float = maxf(
		0.0,
		-local_collision_rect.position.y * absf(_base_scale.z)
	)
	return minf(
		_default_z,
		_boss_target.position.z + _boss_target.hit_radius() + cart_forward_extent
	)


func take_damage(amount: float) -> bool:
	if state == null or _invincible_remaining > 0.0 or amount <= 0.0:
		return false
	var applied: float = state.take_durability_damage(amount)
	if applied <= 0.0:
		return false
	_invincible_remaining = _invincibility_duration_seconds
	damaged.emit(applied)
	if state.current_durability <= 0.0:
		destroyed.emit()
	return true


func cancel_pointer_input() -> void:
	_primary_touch_active = false
	_mouse_drag_active = false


func collision_rect_xz() -> Rect2:
	var local_collision_rect: Rect2 = _collision_rect_local()
	var collision_scale: Vector2 = Vector2(absf(_base_scale.x), absf(_base_scale.z))
	return Rect2(
		Vector2(position.x, position.z) + local_collision_rect.position * collision_scale,
		local_collision_rect.size * collision_scale
	)


# 从编辑器中的盒形碰撞节点恢复玩法所需的 X/Z 矩形，保持现有平面碰撞判定。
func _collision_rect_local() -> Rect2:
	if _collision_shape == null:
		_collision_shape = get_node_or_null("CollisionHitbox") as CollisionShape3D
	if _collision_shape == null:
		return COLLISION_RECT
	var box_shape: BoxShape3D = _collision_shape.shape as BoxShape3D
	if box_shape == null:
		return COLLISION_RECT
	var shape_size: Vector2 = Vector2(
		box_shape.size.x * absf(_collision_shape.scale.x),
		box_shape.size.z * absf(_collision_shape.scale.z)
	)
	var shape_center: Vector2 = Vector2(
		_collision_shape.position.x,
		_collision_shape.position.z
	)
	return Rect2(shape_center - shape_size * 0.5, shape_size)


func play_upgrade_feedback(_color: Color) -> void:
	if _upgrade_tween != null and _upgrade_tween.is_valid():
		_upgrade_tween.kill()
	scale = _base_scale
	_upgrade_feedback_remaining = 0.5
	_upgrade_tween = create_tween()
	_upgrade_tween.tween_property(self, "scale", _base_scale * 1.16, 0.12)
	_upgrade_tween.tween_property(self, "scale", _base_scale, 0.22)


# 头顶纸条把实际耐久与上限分层显示；有护盾时只覆盖当前值，保留白色上限作为阅读锚点。
func set_durability_display(current: float, maximum: float, temporary_shield: float) -> void:
	var safe_maximum: float = maxf(1.0, maximum)
	var safe_current: float = maxf(0.0, current)
	var safe_shield: float = maxf(0.0, temporary_shield)
	var has_shield: bool = safe_shield > 0.0001
	var effective_current: float = safe_current + safe_shield
	# 白色底值与蓝色护盾层始终显示同一有效值，蓝色只负责表达护盾状态。
	_durability_label.text = "%.0f" % effective_current
	_durability_label.modulate = Color.WHITE
	_maximum_durability_label.text = "/ %.0f" % safe_maximum
	_maximum_durability_label.modulate = Color.WHITE
	_effective_durability_label.text = "%.0f" % effective_current
	_effective_durability_label.modulate = SHIELD_COLOR
	_effective_durability_label.visible = has_shield
	if _last_maximum_durability > 0.0 and maximum > _last_maximum_durability + 0.0001:
		_maximum_feedback_label.text = "上限 +%.0f" % (maximum - _last_maximum_durability)
		_maximum_feedback_label.visible = true
		_maximum_feedback_remaining = MAXIMUM_FEEDBACK_DURATION
	_last_maximum_durability = maximum
