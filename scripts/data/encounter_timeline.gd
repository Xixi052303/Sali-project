class_name EncounterTimeline
extends Resource

@export var event_times: PackedFloat32Array = PackedFloat32Array()
@export var event_ids: PackedStringArray = PackedStringArray()


func _init() -> void:
	pass


func is_valid() -> bool:
	return event_times.size() == event_ids.size()
