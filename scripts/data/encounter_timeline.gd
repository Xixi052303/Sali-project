class_name EncounterTimeline
extends Resource

@export var event_progresses: PackedFloat32Array = PackedFloat32Array([
	0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0,
])
@export var event_ids: PackedStringArray = PackedStringArray([
	"start_gate", "elite", "elite", "elite", "boss",
	"elite", "elite", "elite", "boss",
])
@export var baseline_appetite_start: float = 15.0
# 三段时间、终点胃口和指数一一对应；选择暂停不计入有效游戏时间。
@export var appetite_segment_end_times: PackedFloat32Array = PackedFloat32Array([
	135.0, 300.0, 480.0,
])
@export var appetite_segment_maximums: PackedFloat32Array = PackedFloat32Array([
	350.0, 2825.0, 12000.0,
])
@export var appetite_segment_exponents: PackedFloat32Array = PackedFloat32Array([
	2.1, 2.1, 2.1,
])
# 总路程独立于策划目标时长，避免调整Boss参考耗时改变事件触发位置。
@export var course_distance: float = 1310.763
@export var normal_gate_count: int = 50
@export var normal_wave_count: int = 250
# 普通波次以平均路程间隔为基准做种子随机，数值表示单个间隔允许的正负比例。
@export_range(0.0, 0.45, 0.01) var normal_wave_interval_jitter_ratio: float = 0.2
@export var pressure_progresses: PackedFloat32Array = PackedFloat32Array([
	0.0, 0.1875, 0.3125, 0.5, 0.6875, 0.8125,
])
@export var forward_speed_multipliers: PackedFloat32Array = PackedFloat32Array([
	1.0, 1.1, 1.3, 1.7, 2.3, 3.0,
])
@export var headwind_factor: float = 1.25
@export var max_crosswind_speed: float = 60.0
@export_range(0.0, 1.0, 0.001) var minimum_cart_base_speed_factor: float = 0.8


func _init() -> void:
	pass


func is_valid() -> bool:
	if (
		event_progresses.size() != event_ids.size()
		or event_progresses.is_empty()
		or pressure_progresses.size() != forward_speed_multipliers.size()
		or pressure_progresses.is_empty()
		or baseline_appetite_start <= 0.0
		or appetite_segment_end_times.size() != 3
		or appetite_segment_maximums.size() != 3
		or appetite_segment_exponents.size() != 3
		or course_distance <= 0.0
		or normal_gate_count < 1
		or normal_wave_count < 1
		or normal_wave_interval_jitter_ratio < 0.0
		or normal_wave_interval_jitter_ratio > 0.45
		or headwind_factor < 0.0
		or max_crosswind_speed < 0.0
		or minimum_cart_base_speed_factor <= 0.0
		or minimum_cart_base_speed_factor > 1.0
	):
		return false
	var previous_time: float = 0.0
	var previous_appetite: float = baseline_appetite_start
	for index: int in range(appetite_segment_end_times.size()):
		var end_time: float = appetite_segment_end_times[index]
		var maximum: float = appetite_segment_maximums[index]
		var exponent: float = appetite_segment_exponents[index]
		if end_time <= previous_time or maximum < previous_appetite or exponent <= 0.0:
			return false
		previous_time = end_time
		previous_appetite = maximum
	var previous_progress: float = -INF
	for progress: float in event_progresses:
		if progress < previous_progress or progress < 0.0 or progress > 1.0:
			return false
		previous_progress = progress
	previous_progress = -INF
	for index: int in range(pressure_progresses.size()):
		var progress: float = pressure_progresses[index]
		var multiplier: float = forward_speed_multipliers[index]
		if progress < previous_progress or progress < 0.0 or progress > 1.0:
			return false
		if multiplier <= 0.0:
			return false
		previous_progress = progress
	return is_zero_approx(pressure_progresses[0])


# 三段曲线按有效游戏时间独立归一化，超过末段后固定在最终最大胃口。
func baseline_appetite_at_elapsed_seconds(elapsed_seconds: float) -> float:
	var clamped_time: float = maxf(0.0, elapsed_seconds)
	var segment_start_time: float = 0.0
	var segment_start_appetite: float = baseline_appetite_start
	for index: int in range(appetite_segment_end_times.size()):
		var segment_end_time: float = appetite_segment_end_times[index]
		var segment_maximum: float = appetite_segment_maximums[index]
		if clamped_time <= segment_end_time:
			var segment_ratio: float = clampf(
				(clamped_time - segment_start_time)
				/ maxf(0.001, segment_end_time - segment_start_time),
				0.0,
				1.0
			)
			return roundf(lerpf(
				segment_start_appetite,
				segment_maximum,
				pow(segment_ratio, appetite_segment_exponents[index])
			))
		segment_start_time = segment_end_time
		segment_start_appetite = segment_maximum
	return roundf(appetite_segment_maximums[-1])


func speed_tier_at_progress(progress: float) -> int:
	var tier: int = 0
	for index: int in range(pressure_progresses.size()):
		if progress + 0.000001 < pressure_progresses[index]:
			break
		tier = index
	return tier


func speed_multiplier_at_progress(progress: float) -> float:
	return forward_speed_multipliers[speed_tier_at_progress(progress)]


# 风偏、疲劳和颠簸共享0～1压力进度，但速度倍率仍保留前缓后陡的离散档位。
func pressure_ratio_at_progress(progress: float) -> float:
	var multiplier: float = speed_multiplier_at_progress(progress)
	var maximum_multiplier: float = maxf(1.0, forward_speed_multipliers[-1])
	return clampf((multiplier - 1.0) / maxf(0.001, maximum_multiplier - 1.0), 0.0, 1.0)


func expected_normal_customer_count() -> int:
	return normal_wave_count + floori(float(normal_wave_count) / 4.0)
