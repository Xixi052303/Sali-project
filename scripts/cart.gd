class_name Cart
extends Node2D

signal damaged(amount: float)
signal destroyed

const BASE_MOVE_SPEED: float = 900.0
const INK: Color = Color("#241f1a")
const COLLISION_RECT: Rect2 = Rect2(-96.0, -150.0, 192.0, 217.0)

var state: RunState
var playfield: Playfield
var target_x: float = 360.0
var _primary_touch_active: bool = false
var _mouse_drag_active: bool = false
var _invincible_remaining: float = 0.0
var _upgrade_tween: Tween


func configure(run_state: RunState, field: Playfield) -> void:
	state = run_state
	playfield = field
	position = Vector2(360.0, Playfield.CART_Y)
	target_x = position.x
	queue_redraw()


func _physics_process(delta: float) -> void:
	if state == null or playfield == null:
		return
	if _invincible_remaining > 0.0:
		_invincible_remaining = maxf(0.0, _invincible_remaining - delta)
		modulate.a = 0.45 if int(_invincible_remaining * 12.0) % 2 == 0 else 1.0
	else:
		modulate.a = 1.0
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
	queue_redraw()
	if state.current_durability <= 0.0:
		destroyed.emit()
	return true


func collision_rect() -> Rect2:
	return Rect2(global_position + COLLISION_RECT.position, COLLISION_RECT.size)


func play_upgrade_feedback(color: Color) -> void:
	if _upgrade_tween != null and _upgrade_tween.is_valid():
		_upgrade_tween.kill()
	scale = Vector2.ONE
	modulate = color.lightened(0.25)
	_upgrade_tween = create_tween()
	_upgrade_tween.set_parallel(true)
	_upgrade_tween.tween_property(self, "scale", Vector2.ONE * 1.16, 0.12)
	_upgrade_tween.tween_property(self, "modulate", Color.WHITE, 0.34)
	_upgrade_tween.chain().tween_property(self, "scale", Vector2.ONE, 0.18)


func _draw() -> void:
	draw_circle(Vector2(-52.0, 42.0), 25.0, INK)
	draw_circle(Vector2(52.0, 42.0), 25.0, INK)
	draw_circle(Vector2(-52.0, 42.0), 13.0, Color("#bd9c61"))
	draw_circle(Vector2(52.0, 42.0), 13.0, Color("#bd9c61"))
	draw_style_box(_panel_style(Color("#773e32")), Rect2(-86.0, -24.0, 172.0, 66.0))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-96.0, -30.0),
		Vector2(-70.0, -72.0),
		Vector2(72.0, -72.0),
		Vector2(96.0, -30.0),
	]), Color("#bd7b35"))
	draw_polyline(PackedVector2Array([
		Vector2(-96.0, -30.0),
		Vector2(-70.0, -72.0),
		Vector2(72.0, -72.0),
		Vector2(96.0, -30.0),
	]), INK, 6.0)
	draw_circle(Vector2(0.0, -88.0), 31.0, Color("#d8b982"))
	draw_circle(Vector2(0.0, -93.0), 8.0, INK)
	draw_arc(Vector2(0.0, -83.0), 16.0, 0.35, 2.8, 20, INK, 4.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-35.0, -116.0),
		Vector2(-19.0, -150.0),
		Vector2(0.0, -132.0),
		Vector2(20.0, -150.0),
		Vector2(37.0, -116.0),
	]), Color("#e8dcc1"))
	draw_polyline(PackedVector2Array([
		Vector2(-35.0, -116.0),
		Vector2(-19.0, -150.0),
		Vector2(0.0, -132.0),
		Vector2(20.0, -150.0),
		Vector2(37.0, -116.0),
	]), INK, 5.0)


func _panel_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = INK
	style.set_border_width_all(5)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style
