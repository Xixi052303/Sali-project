class_name WorldBackground3D
extends Node3D

const ROAD_TILE_LENGTH: float = 1280.0

@export_group("滚动")
@export var scrolling: bool = true
@export_range(0.0, 600.0, 1.0, "or_greater") var scroll_speed: float = 205.0

@onready var _road_tiles: Array[MeshInstance3D] = [%RoadTile0, %RoadTile1, %RoadTile2, %RoadTile3]
@onready var _street_props: Array[Sprite3D] = [%PropBench, %PropBin, %PropSign, %PropPlanter, %PropLamp, %PropPlant]

var _scroll_offset: float = 0.0


func _process(delta: float) -> void:
	if not scrolling:
		return
	_scroll_offset = fposmod(_scroll_offset + scroll_speed * delta, ROAD_TILE_LENGTH)
	for index: int in range(_road_tiles.size()):
		_road_tiles[index].position.z = -1920.0 + float(index) * ROAD_TILE_LENGTH + _scroll_offset
	for prop: Sprite3D in _street_props:
		prop.position.z += scroll_speed * delta
		if prop.position.z > 1500.0:
			prop.position.z -= 2600.0
