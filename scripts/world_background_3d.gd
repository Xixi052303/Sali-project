class_name WorldBackground3D
extends Node3D

const ROAD_TILE_LENGTH: float = 12.8
const ROAD_FIRST_CENTER_Z: float = -44.8
const STREET_WRAP_LENGTH: float = 51.2
const STREET_WRAP_EDGE_Z: float = 17.6
const DESIGN_ASPECT: float = 720.0 / 1280.0

@export_group("滚动")
@export var scrolling: bool = true
@export_range(0.0, 6.0, 0.01, "or_greater") var scroll_speed: float = 2.05

@onready var _road_segments: Array[Node3D] = [
	%RoadSegment0,
	%RoadSegment1,
	%RoadSegment2,
	%RoadSegment3,
	%RoadSegment4,
	%RoadSegment5,
]
@onready var _street_props_root: Node3D = %StreetProps
@onready var _camera: Camera3D = $PaperCamera

var _scroll_offset: float = 0.0
var _street_props: Array[Sprite3D] = []


func _ready() -> void:
	# 手动复制到 StreetProps 下的新面片会自动加入滚动，无需再改脚本名单。
	for child: Node in _street_props_root.get_children():
		if child is Sprite3D:
			_street_props.append(child as Sprite3D)
	get_viewport().size_changed.connect(_apply_camera_aspect_compensation)
	_apply_camera_aspect_compensation()


func _process(delta: float) -> void:
	if not scrolling:
		return
	_scroll_offset = fposmod(_scroll_offset + scroll_speed * delta, ROAD_TILE_LENGTH)
	for index: int in range(_road_segments.size()):
		_road_segments[index].position.z = ROAD_FIRST_CENTER_Z + float(index) * ROAD_TILE_LENGTH + _scroll_offset
	for prop: Sprite3D in _street_props:
		prop.position.z += scroll_speed * delta
		if prop.position.z > STREET_WRAP_EDGE_Z:
			prop.position.z -= STREET_WRAP_LENGTH


# 长竖屏把新增纵向视野放到道路远端，保持餐车与横向玩法区域的屏幕尺度。
func _apply_camera_aspect_compensation() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var aspect: float = viewport_size.x / viewport_size.y
	if aspect >= DESIGN_ASPECT:
		_camera.v_offset = 0.0
		return
	var cart_world_position: Vector3 = Vector3(Playfield.ROAD_LEFT + Playfield.ROAD_WIDTH * 0.5, 0.0, Playfield.CART_Z)
	var camera_to_cart: Vector3 = cart_world_position - _camera.global_position
	var cart_depth: float = camera_to_cart.dot(-_camera.global_basis.z)
	var horizontal_half_extent: float = cart_depth * tan(deg_to_rad(_camera.fov) * 0.5)
	_camera.v_offset = horizontal_half_extent * (1.0 / aspect - 1.0 / DESIGN_ASPECT)
