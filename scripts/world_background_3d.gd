class_name WorldBackground3D
extends Node3D

const ROAD_TILE_LENGTH: float = 1280.0
const ROAD_FIRST_CENTER_Z: float = -4480.0
const STREET_WRAP_LENGTH: float = 5120.0
const STREET_WRAP_EDGE_Z: float = 1760.0

@export_group("滚动")
@export var scrolling: bool = true
@export_range(0.0, 600.0, 1.0, "or_greater") var scroll_speed: float = 205.0

@onready var _road_tiles: Array[MeshInstance3D] = [
	%RoadTile0,
	%RoadTile1,
	%RoadTile2,
	%RoadTile3,
	%RoadTile4,
	%RoadTile5,
]
@onready var _street_props_root: Node3D = %StreetProps

var _scroll_offset: float = 0.0
var _street_props: Array[Sprite3D] = []


func _ready() -> void:
	# 手动复制到 StreetProps 下的新面片会自动加入滚动，无需再改脚本名单。
	for child: Node in _street_props_root.get_children():
		if child is Sprite3D:
			_street_props.append(child as Sprite3D)


func _process(delta: float) -> void:
	if not scrolling:
		return
	_scroll_offset = fposmod(_scroll_offset + scroll_speed * delta, ROAD_TILE_LENGTH)
	for index: int in range(_road_tiles.size()):
		_road_tiles[index].position.z = ROAD_FIRST_CENTER_Z + float(index) * ROAD_TILE_LENGTH + _scroll_offset
	for prop: Sprite3D in _street_props:
		prop.position.z += scroll_speed * delta
		if prop.position.z > STREET_WRAP_EDGE_Z:
			prop.position.z -= STREET_WRAP_LENGTH
