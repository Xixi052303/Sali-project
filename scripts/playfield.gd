class_name Playfield
extends Node

const DESIGN_SIZE: Vector2 = Vector2(720.0, 1280.0)
# 数据表和输入继续使用设计像素；进入3D世界时统一按1像素=0.01米换算。
const WORLD_UNITS_PER_PIXEL: float = 0.01
const ROAD_LEFT: float = 0.6
const ROAD_RIGHT: float = 6.6
const ROAD_WIDTH: float = 6.0
const REGION_COUNT: int = 6
const REGION_WIDTH: float = ROAD_WIDTH / float(REGION_COUNT)
const CART_Z: float = 10.5
# 四段前方道路从该位置延伸到餐车附近，远景对象会提前进入固定相机视野。
const FORWARD_SPAWN_Z: float = -32.0
const CUSTOMER_DESPAWN_Z: float = 13.6
const PROJECTILE_FORWARD_BOUNDARY_Z: float = -7.2
const FORWARD_MIN_CENTER_DISTANCE: float = 1.8
# 生成预测额外预留一帧移动量，保证低帧率下实际距离仍不低于视觉安全线。
const FORWARD_SPAWN_RESERVATION_DISTANCE: float = 2.2


static func design_to_world(value: float) -> float:
	return value * WORLD_UNITS_PER_PIXEL


static func world_to_design(value: float) -> float:
	return value / WORLD_UNITS_PER_PIXEL


func clamp_cart_x(value: float) -> float:
	return clampf(value, ROAD_LEFT + 0.48, ROAD_RIGHT - 0.48)


func region_at_x(value: float) -> int:
	var normalized: float = clampf(value - ROAD_LEFT, 0.0, ROAD_WIDTH - 0.00001)
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
	var first_exit_time: float = maxf(0.0, (CART_Z - first_y) / safe_first_speed)
	var second_exit_time: float = maxf(0.0, (CART_Z - second_y) / safe_second_speed)
	var comparison_time: float = minf(first_exit_time, second_exit_time)
	var start_delta: float = first_y - second_y
	var relative_speed: float = safe_first_speed - safe_second_speed
	var closest_time: float = 0.0
	if not is_zero_approx(relative_speed):
		closest_time = clampf(-start_delta / relative_speed, 0.0, comparison_time)
	var closest_distance: float = absf(start_delta + relative_speed * closest_time)
	return closest_distance >= minimum_distance
