class_name Cart3D
extends Node3D

signal damaged(amount: float)
signal destroyed

const BASE_MOVE_SPEED: float = 9.0
const BASE_MOVE_SPEED_DESIGN: float = BASE_MOVE_SPEED / Playfield.WORLD_UNITS_PER_PIXEL
const COLLISION_RECT: Rect2 = Rect2(-0.96, -1.5, 1.92, 2.17)
const DURABILITY_FILL_WIDTH: float = 1.52
const MAXIMUM_FEEDBACK_DURATION: float = 1.2
const DEFAULT_INVINCIBILITY_DURATION_SECONDS: float = 0.5

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
@onready var _visual_root: Node3D = %PaperCartVisual
@onready var _durability_fill: MeshInstance3D = %DurabilityFill
@onready var _shield_outline: MeshInstance3D = %ShieldOutline
@onready var _shield_badge: Label3D = %ShieldBadge
@onready var _maximum_feedback_label: Label3D = %MaximumFeedbackLabel


func configure(
	run_state: RunState,
	field: Playfield,
	invincibility_duration_seconds: float = DEFAULT_INVINCIBILITY_DURATION_SECONDS
) -> void:
	state = run_state
	playfield = field
	_invincibility_duration_seconds = maxf(0.0, invincibility_duration_seconds)
	_resolve_status_nodes()
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
	var cart_forward_extent: float = absf(COLLISION_RECT.position.y * _base_scale.z)
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
	var collision_scale: Vector2 = Vector2(absf(_base_scale.x), absf(_base_scale.z))
	return Rect2(
		Vector2(position.x, position.z) + COLLISION_RECT.position * collision_scale,
		COLLISION_RECT.size * collision_scale
	)


func play_upgrade_feedback(_color: Color) -> void:
	if _upgrade_tween != null and _upgrade_tween.is_valid():
		_upgrade_tween.kill()
	scale = _base_scale
	_upgrade_feedback_remaining = 0.5
	_upgrade_tween = create_tween()
	_upgrade_tween.tween_property(self, "scale", _base_scale * 1.16, 0.12)
	_upgrade_tween.tween_property(self, "scale", _base_scale, 0.22)


# 头顶纸条只呈现同一份RunState耐久，固定宽度避免上限成长扩大遮挡。
func set_durability_display(current: float, maximum: float, temporary_shield: float) -> void:
	_resolve_status_nodes()
	var safe_maximum: float = maxf(1.0, maximum)
	var ratio: float = clampf(current / safe_maximum, 0.0, 1.0)
	_durability_fill.scale.x = ratio
	_durability_fill.position.x = -DURABILITY_FILL_WIDTH * 0.5 * (1.0 - ratio)
	var has_shield: bool = temporary_shield > 0.0001
	_shield_outline.visible = has_shield
	_shield_badge.visible = has_shield
	_shield_badge.text = "+%.0f" % temporary_shield
	if _last_maximum_durability > 0.0 and maximum > _last_maximum_durability + 0.0001:
		_maximum_feedback_label.text = "上限 +%.0f" % (maximum - _last_maximum_durability)
		_maximum_feedback_label.visible = true
		_maximum_feedback_remaining = MAXIMUM_FEEDBACK_DURATION
	_last_maximum_durability = maximum


func _resolve_status_nodes() -> void:
	if _durability_fill != null:
		return
	_durability_fill = get_node("StatusBillboard/DurabilityFill") as MeshInstance3D
	_shield_outline = get_node("StatusBillboard/ShieldOutline") as MeshInstance3D
	_shield_badge = get_node("StatusBillboard/ShieldBadge") as Label3D
	_maximum_feedback_label = get_node("StatusBillboard/MaximumFeedbackLabel") as Label3D
