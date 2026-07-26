class_name UpgradeDrop
extends Node2D

const INK: Color = Color("#241f1a")

var run: RunController
var upgrade: UpgradeData
var _elapsed: float = 0.0
var _collected: bool = false


func configure(run_controller: RunController, upgrade_data: UpgradeData, start_position: Vector2) -> void:
	run = run_controller
	upgrade = upgrade_data
	global_position = start_position
	scale = Vector2(0.45, 0.45)
	queue_redraw()


func _process(delta: float) -> void:
	if _collected or run == null or upgrade == null:
		return
	_elapsed += delta
	rotation += delta * 2.8
	if _elapsed < 0.22:
		position.y -= 150.0 * delta
		scale = scale.move_toward(Vector2.ONE, delta * 3.0)
		return
	var target_position: Vector2 = run.cart.global_position + Vector2(0.0, -68.0)
	global_position = global_position.move_toward(target_position, 920.0 * delta)
	if global_position.distance_to(target_position) <= 36.0:
		_collected = true
		run.on_upgrade_drop_collected(upgrade)
		queue_free()


func _draw() -> void:
	if upgrade == null:
		return
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, -31.0),
		Vector2(31.0, 0.0),
		Vector2(0.0, 31.0),
		Vector2(-31.0, 0.0),
	]), upgrade.rarity_color)
	draw_polyline(PackedVector2Array([
		Vector2(0.0, -31.0),
		Vector2(31.0, 0.0),
		Vector2(0.0, 31.0),
		Vector2(-31.0, 0.0),
		Vector2(0.0, -31.0),
	]), INK, 5.0)
	var font: Font = ThemeDB.fallback_font
	draw_string(
		font,
		Vector2(-24.0, 9.0),
		upgrade.display_name.left(1),
		HORIZONTAL_ALIGNMENT_CENTER,
		48.0,
		22,
		INK
	)
