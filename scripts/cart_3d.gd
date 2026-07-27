class_name Cart3D
extends Node3D

signal damaged(amount: float)
signal destroyed

const BASE_MOVE_SPEED: float = 900.0
const COLLISION_RECT: Rect2 = Rect2(-96.0, -150.0, 192.0, 217.0)

var state: RunState
var playfield: Playfield
var target_x: float = 360.0
var _primary_touch_active: bool = false
var _mouse_drag_active: bool = false
var _invincible_remaining: float = 0.0
var _upgrade_feedback_remaining: float = 0.0
var _upgrade_tween: Tween
@onready var _visual_root: Node3D = %PaperCartVisual


func configure(run_state: RunState, field: Playfield) -> void:
	state = run_state
	playfield = field
	position = Vector3(360.0, 0.0, Playfield.CART_Y)
	target_x = position.x


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
	var speed: float = BASE_MOVE_SPEED + state.cart_speed_bonus
	position.x = move_toward(position.x, target_x, speed * delta)


func _unhandled_input(event: InputEvent) -> void:
	if playfield == null:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.index == 0:
			_primary_touch_active = touch.pressed
			if touch.pressed:
				target_x = playfield.clamp_cart_x(touch.position.x)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == 0 and _primary_touch_active:
			target_x = playfield.clamp_cart_x(drag.position.x)
	elif event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_mouse_drag_active = mouse_button.pressed
			if mouse_button.pressed:
				target_x = playfield.clamp_cart_x(mouse_button.position.x)
	elif event is InputEventMouseMotion and _mouse_drag_active:
		var mouse_motion: InputEventMouseMotion = event
		target_x = playfield.clamp_cart_x(mouse_motion.position.x)


func take_damage(amount: float) -> bool:
	if state == null or _invincible_remaining > 0.0 or amount <= 0.0:
		return false
	var applied: float = state.take_durability_damage(amount)
	if applied <= 0.0:
		return false
	_invincible_remaining = 1.0
	damaged.emit(applied)
	if state.current_durability <= 0.0:
		destroyed.emit()
	return true


func collision_rect_xz() -> Rect2:
	var world_position: Vector3 = global_position if is_inside_tree() else position
	return Rect2(Vector2(world_position.x, world_position.z) + COLLISION_RECT.position, COLLISION_RECT.size)


func play_upgrade_feedback(_color: Color) -> void:
	if _upgrade_tween != null and _upgrade_tween.is_valid():
		_upgrade_tween.kill()
	scale = Vector3.ONE
	_upgrade_feedback_remaining = 0.5
	_upgrade_tween = create_tween()
	_upgrade_tween.tween_property(self, "scale", Vector3.ONE * 1.16, 0.12)
	_upgrade_tween.tween_property(self, "scale", Vector3.ONE, 0.22)
