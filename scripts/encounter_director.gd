class_name EncounterDirector
extends Node

signal event_triggered(event_id: StringName)

@export var timeline: EncounterTimeline

var _triggered_events: PackedByteArray = PackedByteArray()


func reset() -> void:
	_triggered_events = PackedByteArray()


func advance(elapsed_seconds: float, event_lead_seconds: Callable = Callable()) -> void:
	if timeline == null or not timeline.is_valid():
		return
	if _triggered_events.size() != timeline.event_times.size():
		_triggered_events.resize(timeline.event_times.size())
		_triggered_events.fill(0)
	for event_index: int in range(timeline.event_times.size()):
		if _triggered_events[event_index] == 1:
			continue
		var event_id: StringName = StringName(timeline.event_ids[event_index])
		var lead_seconds: float = 0.0
		if event_lead_seconds.is_valid():
			lead_seconds = maxf(0.0, float(event_lead_seconds.call(event_id)))
		if elapsed_seconds < timeline.event_times[event_index] - lead_seconds:
			continue
		_triggered_events[event_index] = 1
		event_triggered.emit(event_id)
