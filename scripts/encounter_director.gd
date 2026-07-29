class_name EncounterDirector
extends Node

signal event_triggered(event_id: StringName)

@export var timeline: EncounterTimeline

var _triggered_events: PackedByteArray = PackedByteArray()


func reset() -> void:
	_triggered_events = PackedByteArray()


func advance(progress: float) -> void:
	if timeline == null or not timeline.is_valid():
		return
	if _triggered_events.size() != timeline.event_progresses.size():
		_triggered_events.resize(timeline.event_progresses.size())
		_triggered_events.fill(0)
	for event_index: int in range(timeline.event_progresses.size()):
		if _triggered_events[event_index] == 1:
			continue
		if progress + 0.000001 < timeline.event_progresses[event_index]:
			continue
		_triggered_events[event_index] = 1
		event_triggered.emit(StringName(timeline.event_ids[event_index]))
