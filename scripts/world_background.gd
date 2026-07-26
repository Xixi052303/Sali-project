class_name WorldBackground
extends Node2D

const PAPER: Color = Color("#b79a68")
const ROAD: Color = Color("#82745b")
const ROAD_DARK: Color = Color("#403b30")
const MOSS: Color = Color("#394033")
const BRICK: Color = Color("#673f35")
const INK: Color = Color("#241f1a")

var scrolling: bool = true
var scroll_offset: float = 0.0


func _process(delta: float) -> void:
	if scrolling:
		scroll_offset = fmod(scroll_offset + delta * 135.0, 120.0)
		queue_redraw()


func _draw() -> void:
	var size: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	draw_rect(Rect2(0.0, 0.0, 60.0, size.y), MOSS)
	draw_rect(Rect2(660.0, 0.0, 60.0, size.y), MOSS)
	draw_rect(Rect2(60.0, 0.0, 600.0, size.y), ROAD)
	draw_line(Vector2(60.0, 0.0), Vector2(60.0, size.y), INK, 7.0)
	draw_line(Vector2(660.0, 0.0), Vector2(660.0, size.y), INK, 7.0)
	for region: int in range(1, Playfield.REGION_COUNT):
		var x: float = Playfield.ROAD_LEFT + float(region) * Playfield.REGION_WIDTH
		for y: float in range(-120, int(size.y) + 120, 120):
			var shifted_y: float = y + scroll_offset
			draw_line(
				Vector2(x, shifted_y),
				Vector2(x, shifted_y + 38.0),
				Color(0.16, 0.14, 0.12, 0.22),
				3.0
			)
	for y: float in range(-120, int(size.y) + 120, 120):
		var shifted: float = y + scroll_offset
		draw_line(Vector2(82.0, shifted), Vector2(638.0, shifted + 16.0), Color(0.2, 0.17, 0.13, 0.2), 2.0)
		draw_line(Vector2(90.0, shifted + 34.0), Vector2(248.0, shifted + 25.0), Color(0.2, 0.17, 0.13, 0.18), 2.0)
		draw_line(Vector2(480.0, shifted + 68.0), Vector2(632.0, shifted + 55.0), Color(0.2, 0.17, 0.13, 0.18), 2.0)
	_draw_side_stalls(size.y)


func _draw_side_stalls(height: float) -> void:
	for y: float in range(-80, int(height) + 180, 230):
		var shifted_y: float = y + scroll_offset * 0.35
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, shifted_y),
			Vector2(52.0, shifted_y + 12.0),
			Vector2(52.0, shifted_y + 124.0),
			Vector2(0.0, shifted_y + 146.0),
		]), BRICK)
		draw_polyline(PackedVector2Array([
			Vector2(0.0, shifted_y),
			Vector2(52.0, shifted_y + 12.0),
			Vector2(52.0, shifted_y + 124.0),
		]), INK, 5.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(720.0, shifted_y + 84.0),
			Vector2(668.0, shifted_y + 96.0),
			Vector2(668.0, shifted_y + 206.0),
			Vector2(720.0, shifted_y + 228.0),
		]), Color("#4b4938"))
		draw_polyline(PackedVector2Array([
			Vector2(720.0, shifted_y + 84.0),
			Vector2(668.0, shifted_y + 96.0),
			Vector2(668.0, shifted_y + 206.0),
		]), INK, 5.0)
