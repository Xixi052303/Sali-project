class_name EncounterDirector
extends Node

signal event_triggered(event_id: StringName)

@export var timeline: EncounterTimeline

var _next_event_index: int = 0


func reset() -> void:
	_next_event_index = 0


func advance(elapsed_seconds: float) -> void:
	if timeline == null or not timeline.is_valid():
		return
	while _next_event_index < timeline.event_times.size():
		if elapsed_seconds < timeline.event_times[_next_event_index]:
			break
		var event_id: StringName = StringName(timeline.event_ids[_next_event_index])
		_next_event_index += 1
		event_triggered.emit(event_id)
