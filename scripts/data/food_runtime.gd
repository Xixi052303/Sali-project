class_name FoodRuntime
extends RefCounted

var data: FoodData
var cooldown_remaining: float = 0.0
var ready: bool = true


func _init(source_data: FoodData = null) -> void:
	data = source_data
