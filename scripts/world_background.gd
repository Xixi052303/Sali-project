class_name WorldBackground
extends Node2D

@export_group("滚动")
@export var scrolling: bool = true
@export_range(0.0, 600.0, 1.0, "or_greater") var scroll_speed: float = 205.0

@onready var road_tiles: Node2D = %RoadTiles
@onready var road_a: Sprite2D = %RoadA
@onready var road_b: Sprite2D = %RoadB

# 保存编辑器中设定的道路基准位置，运行时只叠加循环滚动偏移。
var _base_position: Vector2
var _tile_height: float = 0.0
var _scroll_offset: float = 0.0


func _ready() -> void:
	_base_position = road_tiles.position
	if road_a.texture == null:
		push_error("WorldBackground 缺少道路纹理")
		set_process(false)
		return
	var source_height: float = float(road_a.texture.get_height())
	_tile_height = source_height * absf(road_tiles.scale.y)
	road_b.position = road_a.position - Vector2(0.0, source_height)
	_apply_scroll_offset()


func _process(delta: float) -> void:
	if not scrolling or _tile_height <= 0.0:
		return
	_scroll_offset = fposmod(_scroll_offset + delta * scroll_speed, _tile_height)
	_apply_scroll_offset()


# 两张共享纹理的道路始终首尾相接，越过整张高度后无缝回绕。
func _apply_scroll_offset() -> void:
	road_tiles.position = _base_position + Vector2(0.0, _scroll_offset)
