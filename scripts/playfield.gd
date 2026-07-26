class_name Playfield
extends Node

const DESIGN_SIZE: Vector2 = Vector2(720.0, 1280.0)
const ROAD_LEFT: float = 60.0
const ROAD_RIGHT: float = 660.0
const ROAD_WIDTH: float = 600.0
const REGION_COUNT: int = 6
const REGION_WIDTH: float = ROAD_WIDTH / float(REGION_COUNT)
const CART_Y: float = 1050.0
const CUSTOMER_SPAWN_Y: float = -640.0
const PROJECTILE_TOP_BOUNDARY: float = -720.0
const FORWARD_MIN_CENTER_DISTANCE: float = 180.0
# 生成预测额外预留一帧移动量，保证低帧率下实际距离仍不低于视觉安全线。
const FORWARD_SPAWN_RESERVATION_DISTANCE: float = 220.0


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


# 预测两个匀速前进对象在任一方到达餐车前是否始终保留安全纵向距离。
func forward_paths_are_separated(
	first_y: float,
	first_speed: float,
	second_y: float,
	second_speed: float,
	minimum_distance: float = FORWARD_SPAWN_RESERVATION_DISTANCE
) -> bool:
	var safe_first_speed: float = maxf(0.001, first_speed)
	var safe_second_speed: float = maxf(0.001, second_speed)
	var first_exit_time: float = maxf(0.0, (CART_Y - first_y) / safe_first_speed)
	var second_exit_time: float = maxf(0.0, (CART_Y - second_y) / safe_second_speed)
	var comparison_time: float = minf(first_exit_time, second_exit_time)
	var start_delta: float = first_y - second_y
	var relative_speed: float = safe_first_speed - safe_second_speed
	var closest_time: float = 0.0
	if not is_zero_approx(relative_speed):
		closest_time = clampf(-start_delta / relative_speed, 0.0, comparison_time)
	var closest_distance: float = absf(start_delta + relative_speed * closest_time)
	return closest_distance >= minimum_distance
