class_name EncounterTimeline
extends Resource

@export var event_progresses: PackedFloat32Array = PackedFloat32Array([
	0.005, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0,
])
@export var event_ids: PackedStringArray = PackedStringArray([
	"start_gate", "elite", "elite", "elite", "boss",
	"elite", "elite", "elite", "boss",
])
@export var baseline_appetite_start: float = 15.0
@export var baseline_appetite_mid: float = 350.0
@export var baseline_appetite_end: float = 12000.0
@export_range(0.0, 1.0, 0.001) var appetite_mid_progress: float = 0.5
@export var baseline_appetite_exponent: float = 2.1
@export var baseline_appetite_late_exponent: float = 2.1
@export var target_active_duration: float = 480.0
@export var target_boss_duration: float = 25.0
@export var normal_gate_count: int = 50
@export var normal_wave_count: int = 235
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
		or baseline_appetite_mid < baseline_appetite_start
		or baseline_appetite_end < baseline_appetite_mid
		or appetite_mid_progress <= 0.0
		or appetite_mid_progress >= 1.0
		or baseline_appetite_exponent <= 0.0
		or baseline_appetite_late_exponent <= 0.0
		or target_active_duration <= target_boss_duration * 2.0
		or normal_gate_count < 1
		or normal_wave_count < 1
		or headwind_factor < 0.0
		or max_crosswind_speed < 0.0
		or minimum_cart_base_speed_factor <= 0.0
		or minimum_cart_base_speed_factor > 1.0
	):
		return false
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


# 胃口随已完成路程推进，Boss和暂停选择不会偷偷提高尚未生成对象的压力。
func baseline_appetite_at_progress(progress: float) -> float:
	var clamped_progress: float = clampf(progress, 0.0, 1.0)
	if clamped_progress <= appetite_mid_progress:
		var early_progress: float = clamped_progress / maxf(0.001, appetite_mid_progress)
		return roundf(lerpf(
			baseline_appetite_start,
			baseline_appetite_mid,
			pow(early_progress, maxf(0.001, baseline_appetite_exponent))
		))
	var late_progress: float = (
		(clamped_progress - appetite_mid_progress)
		/ maxf(0.001, 1.0 - appetite_mid_progress)
	)
	return roundf(lerpf(
		baseline_appetite_mid,
		baseline_appetite_end,
		pow(late_progress, maxf(0.001, baseline_appetite_late_exponent))
	))


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


func forward_duration() -> float:
	return maxf(0.0, target_active_duration - target_boss_duration * 2.0)


# 路程由目标前进时长与分段速度反推，避免在表内维护无法审计的魔法距离。
func course_distance(base_scroll_speed: float) -> float:
	var weighted_inverse_speed: float = 0.0
	for index: int in range(pressure_progresses.size()):
		var start: float = pressure_progresses[index]
		var finish: float = (
			pressure_progresses[index + 1]
			if index + 1 < pressure_progresses.size()
			else 1.0
		)
		weighted_inverse_speed += (
			maxf(0.0, finish - start)
			/ maxf(0.001, forward_speed_multipliers[index])
		)
	return (
		forward_duration()
		* maxf(0.001, base_scroll_speed)
		/ maxf(0.001, weighted_inverse_speed)
	)


func expected_normal_customer_count() -> int:
	return normal_wave_count + floori(float(normal_wave_count) / 4.0)
