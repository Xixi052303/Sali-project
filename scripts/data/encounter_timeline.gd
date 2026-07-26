class_name EncounterTimeline
extends Resource

@export var event_times: PackedFloat32Array = PackedFloat32Array()
@export var event_ids: PackedStringArray = PackedStringArray()
@export var baseline_appetite_start: float = 1.0
@export var baseline_appetite_end: float = 1.0
@export var baseline_appetite_end_time: float = 1.0
@export var baseline_appetite_exponent: float = 1.0


func _init() -> void:
	pass


func is_valid() -> bool:
	return event_times.size() == event_ids.size()


# 返回当前竖切片时刻的食客基准胃口，生成后的单位不会继续随时间变化。
func baseline_appetite_at(elapsed_seconds: float) -> float:
	var safe_duration: float = maxf(0.001, baseline_appetite_end_time)
	var progress: float = clampf(elapsed_seconds / safe_duration, 0.0, 1.0)
	var curved_progress: float = pow(progress, maxf(0.001, baseline_appetite_exponent))
	return roundf(lerpf(baseline_appetite_start, baseline_appetite_end, curved_progress))
