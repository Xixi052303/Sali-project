class_name EncounterTimeline
extends Resource

@export var event_times: PackedFloat32Array = PackedFloat32Array()
@export var event_ids: PackedStringArray = PackedStringArray()
@export var baseline_appetite_start: float = 1.0
@export var baseline_appetite_end: float = 1.0
@export var baseline_appetite_end_time: float = 1.0
@export var baseline_appetite_exponent: float = 1.0
@export var baseline_appetite_late_end: float = 1.0
@export var baseline_appetite_late_end_time: float = 2.0
@export var baseline_appetite_late_exponent: float = 1.0
@export var normal_wave_start_time: float = 8.0
@export var normal_wave_end_time: float = 360.0
@export var normal_wave_early_end_time: float = 78.0
@export var normal_wave_mid_end_time: float = 135.0
@export var normal_wave_interval_early: float = 3.2
@export var normal_wave_interval_mid: float = 2.8
@export var normal_wave_interval_late: float = 3.2


func _init() -> void:
	pass


func is_valid() -> bool:
	return (
		event_times.size() == event_ids.size()
		and baseline_appetite_start > 0.0
		and baseline_appetite_end >= baseline_appetite_start
		and baseline_appetite_end_time > 0.0
		and baseline_appetite_exponent > 0.0
		and baseline_appetite_late_end >= baseline_appetite_end
		and baseline_appetite_late_end_time > baseline_appetite_end_time
		and baseline_appetite_late_exponent > 0.0
		and normal_wave_start_time >= 0.0
		and normal_wave_early_end_time >= normal_wave_start_time
		and normal_wave_mid_end_time >= normal_wave_early_end_time
		and normal_wave_end_time > normal_wave_mid_end_time
		and normal_wave_interval_early > 0.0
		and normal_wave_interval_mid > 0.0
		and normal_wave_interval_late > 0.0
	)


# 返回当前竖切片时刻的食客基准胃口，生成后的单位不会继续随时间变化。
func baseline_appetite_at(elapsed_seconds: float) -> float:
	if elapsed_seconds <= baseline_appetite_end_time:
		var safe_duration: float = maxf(0.001, baseline_appetite_end_time)
		var progress: float = clampf(elapsed_seconds / safe_duration, 0.0, 1.0)
		var curved_progress: float = pow(progress, maxf(0.001, baseline_appetite_exponent))
		return roundf(lerpf(baseline_appetite_start, baseline_appetite_end, curved_progress))
	var late_duration: float = maxf(
		0.001,
		baseline_appetite_late_end_time - baseline_appetite_end_time
	)
	var late_progress: float = clampf(
		(elapsed_seconds - baseline_appetite_end_time) / late_duration,
		0.0,
		1.0
	)
	var late_curved_progress: float = pow(
		late_progress,
		maxf(0.001, baseline_appetite_late_exponent)
	)
	return roundf(lerpf(
		baseline_appetite_end,
		baseline_appetite_late_end,
		late_curved_progress
	))


# 普通波次以原定生成时刻选择阶段，边界时刻进入下一段。
func normal_wave_interval_at(scheduled_time: float) -> float:
	if scheduled_time < normal_wave_early_end_time:
		return normal_wave_interval_early
	if scheduled_time < normal_wave_mid_end_time:
		return normal_wave_interval_mid
	return normal_wave_interval_late
