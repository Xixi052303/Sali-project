class_name Playfield
extends Node

const DESIGN_SIZE: Vector2 = Vector2(720.0, 1280.0)
const ROAD_LEFT: float = 60.0
const ROAD_RIGHT: float = 660.0
const ROAD_WIDTH: float = 600.0
const REGION_COUNT: int = 6
const REGION_WIDTH: float = ROAD_WIDTH / float(REGION_COUNT)
const CART_Y: float = 1050.0


func clamp_cart_x(value: float) -> float:
	return clampf(value, ROAD_LEFT + 48.0, ROAD_RIGHT - 48.0)


func region_at_x(value: float) -> int:
	var normalized: float = clampf(value - ROAD_LEFT, 0.0, ROAD_WIDTH - 0.001)
	return clampi(floori(normalized / REGION_WIDTH), 0, REGION_COUNT - 1)


func region_center(region: int) -> float:
	return ROAD_LEFT + (float(clampi(region, 0, REGION_COUNT - 1)) + 0.5) * REGION_WIDTH


func spawn_x(region: int, occupied_regions: int) -> float:
	var span: int = clampi(occupied_regions, 1, REGION_COUNT)
	var first_region: int = clampi(region, 0, REGION_COUNT - span)
	return ROAD_LEFT + (float(first_region) + float(span) * 0.5) * REGION_WIDTH
