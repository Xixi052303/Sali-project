class_name UpgradeGate
extends Node2D

const INK: Color = Color("#241f1a")

var run: RunController
var left_upgrade: UpgradeData
var right_upgrade: UpgradeData
var start_food_gate: bool = false
var resolved: bool = false
var move_speed: float = 250.0


func configure(
	run_controller: RunController,
	left: UpgradeData,
	right: UpgradeData,
	is_start_gate: bool = false
) -> void:
	run = run_controller
	left_upgrade = left
	right_upgrade = right
	start_food_gate = is_start_gate
	position = Vector2.ZERO
	queue_redraw()


func _process(delta: float) -> void:
	if run == null or resolved:
		return
	if run.is_world_scrolling():
		position.y += move_speed * delta
	if position.y >= Playfield.CART_Y:
		resolved = true
		var chose_left: bool = run.cart.position.x < 360.0
		run.on_gate_selected(left_upgrade if chose_left else right_upgrade, start_food_gate)
		queue_free()


func _draw() -> void:
	_draw_panel(Rect2(66.0, -66.0, 288.0, 132.0), left_upgrade, Color("#3d513d"))
	_draw_panel(Rect2(366.0, -66.0, 288.0, 132.0), right_upgrade, Color("#694035"))
	draw_line(Vector2(360.0, -76.0), Vector2(360.0, 76.0), Color("#efbd4b"), 7.0)


func _draw_panel(rect: Rect2, upgrade: UpgradeData, color: Color) -> void:
	if upgrade == null:
		return
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = upgrade.rarity_color
	style.set_border_width_all(5)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	draw_style_box(style, rect)
	var font: Font = ThemeDB.fallback_font
	var title: String = "土豆 Lv.1" if start_food_gate else upgrade.display_name
	var maximum_durability: float = 100.0 if run == null else run.state.maximum_durability
	var value_text: String = "选择开局食材" if start_food_gate else upgrade.effect_text(maximum_durability)
	draw_string(font, rect.position + Vector2(22.0, 48.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 27, Color.WHITE)
	draw_string(font, rect.position + Vector2(22.0, 91.0), value_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 44.0, 18, Color("#f0dfb6"))
