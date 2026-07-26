class_name Customer
extends Node2D

signal satisfied(customer: Customer)
signal collided_with_cart(customer: Customer)
signal escaped(customer: Customer)
signal ranged_attack(customer: Customer, amount: float)

const INK: Color = Color("#241f1a")

var data: CustomerData
var run: RunController
var remaining_appetite: float = 0.0
var spawn_index: int = 0
# 普通食客生成时锁定奖励及其基准胃口，满足后原样交给奖励门。
var reward_upgrade: UpgradeData
var reward_baseline_appetite: float = 1.0
var active: bool = false
var _attack_remaining: float = 0.0
# 受击反馈只保存短时剩余时长，不改变食客的玩法状态。
var _hit_feedback_remaining: float = 0.0


func configure(
	source_data: CustomerData,
	run_controller: RunController,
	index: int,
	spawn_appetite: float,
	spawn_reward_upgrade: UpgradeData = null,
	baseline_appetite: float = 1.0
) -> void:
	data = source_data
	run = run_controller
	spawn_index = index
	remaining_appetite = maxf(1.0, spawn_appetite)
	reward_upgrade = spawn_reward_upgrade
	reward_baseline_appetite = maxf(1.0, baseline_appetite)
	_attack_remaining = data.attack_interval
	active = true
	queue_redraw()


func _process(delta: float) -> void:
	if not active or data == null or run == null:
		return
	if _hit_feedback_remaining > 0.0:
		_hit_feedback_remaining = maxf(0.0, _hit_feedback_remaining - delta)
		var pulse: float = _hit_feedback_remaining / 0.12
		scale = Vector2.ONE * (1.0 + pulse * 0.05)
		queue_redraw()
	else:
		scale = Vector2.ONE
	if run.is_world_scrolling():
		position.y += travel_speed() * delta
	if data.kind == CustomerData.Kind.RANGED and position.y > 180.0 and position.y < 820.0:
		_attack_remaining -= delta
		if _attack_remaining <= 0.0:
			_attack_remaining = data.attack_interval
			ranged_attack.emit(self, remaining_appetite * data.attack_ratio)
	if run.customer_collides_with_cart(self):
		active = false
		collided_with_cart.emit(self)
	elif position.y >= Playfield.CUSTOMER_DESPAWN_Y:
		active = false
		escaped.emit(self)


func receive_satisfaction(amount: float) -> void:
	if not active or amount <= 0.0:
		return
	remaining_appetite = maxf(0.0, remaining_appetite - amount)
	_hit_feedback_remaining = 0.12
	queue_redraw()
	if remaining_appetite <= 0.0:
		active = false
		satisfied.emit(self)


func hit_radius() -> float:
	if data == null:
		return 40.0
	return maxf(44.0, float(data.occupied_regions) * Playfield.REGION_WIDTH * 0.42)


func collision_rect() -> Rect2:
	var width: float = _body_width()
	return Rect2(global_position + Vector2(-width * 0.5, -42.0), Vector2(width, 84.0))


func travel_speed() -> float:
	if data == null or run == null:
		return 0.0
	return run.world_scroll_speed + data.move_speed


func _draw() -> void:
	if data == null:
		return
	var width: float = _body_width()
	var body_rect: Rect2 = Rect2(-width * 0.5, -42.0, width, 84.0)
	var body_color: Color = data.body_color
	if _hit_feedback_remaining > 0.0:
		body_color = body_color.lightened(0.42)
	draw_style_box(_body_style(body_color), body_rect)
	var eye_y: float = -10.0
	draw_circle(Vector2(-width * 0.18, eye_y), 7.0, INK)
	draw_circle(Vector2(width * 0.18, eye_y), 7.0, INK)
	draw_arc(Vector2.ZERO + Vector2(0.0, 14.0), 18.0, 0.15, 3.0, 18, INK, 5.0)
	if data.kind == CustomerData.Kind.FAST:
		draw_line(Vector2(-width * 0.5 - 22.0, -18.0), Vector2(-width * 0.5 - 58.0, -28.0), INK, 5.0)
		draw_line(Vector2(-width * 0.5 - 18.0, 10.0), Vector2(-width * 0.5 - 48.0, 26.0), INK, 5.0)
	elif data.kind == CustomerData.Kind.RANGED:
		draw_colored_polygon(PackedVector2Array([
			Vector2(-20.0, 31.0),
			Vector2(20.0, 31.0),
			Vector2(28.0, 54.0),
			Vector2(-28.0, 54.0),
		]), Color("#d2b06d"))
	elif data.kind == CustomerData.Kind.ELITE:
		for x: float in range(int(-width * 0.4), int(width * 0.4), 45):
			draw_line(Vector2(x, -37.0), Vector2(x + 24.0, 34.0), Color(0.12, 0.1, 0.09, 0.45), 3.0)
	var font: Font = ThemeDB.fallback_font
	var appetite_text: String = str(ceili(remaining_appetite))
	var text_position: Vector2 = Vector2(-width * 0.5, -62.0)
	for offset: Vector2 in [Vector2(-2.0, 0.0), Vector2(2.0, 0.0), Vector2(0.0, -2.0), Vector2(0.0, 2.0)]:
		draw_string(font, text_position + offset, appetite_text, HORIZONTAL_ALIGNMENT_CENTER, width, 30, INK)
	var appetite_color: Color = Color("#ffe09a") if reward_upgrade == null else reward_upgrade.rarity_color
	draw_string(font, text_position, appetite_text, HORIZONTAL_ALIGNMENT_CENTER, width, 30, appetite_color)


func _body_width() -> float:
	if data == null:
		return 82.0
	return maxf(82.0, float(data.occupied_regions) * Playfield.REGION_WIDTH - 18.0)


func _body_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = INK
	style.set_border_width_all(5)
	style.corner_radius_top_left = 24
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 27
	return style
