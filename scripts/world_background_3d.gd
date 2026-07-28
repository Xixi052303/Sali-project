class_name WorldBackground3D
extends Node3D

const ROAD_TILE_LENGTH: float = 12.8
const ROAD_FIRST_CENTER_Z: float = -44.8
# 街景沿六段道路的完整编辑器范围回卷，避免运行首帧改变手动摆位。
const STREET_WRAP_BACK_Z: float = ROAD_FIRST_CENTER_Z - ROAD_TILE_LENGTH * 0.5
const STREET_WRAP_LENGTH: float = ROAD_TILE_LENGTH * 6.0
const STREET_WRAP_EDGE_Z: float = STREET_WRAP_BACK_Z + STREET_WRAP_LENGTH
const DESIGN_ASPECT: float = 720.0 / 1280.0
const MINIMUM_SHAKE_DURATION: float = 0.01

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
# 由主流程注入实际餐车，供窄屏相机补偿跟随场景初始位置。
var _cart: Cart3D
var _camera_base_position: Vector3 = Vector3.ZERO
var _camera_shake_remaining: float = 0.0
var _camera_shake_duration: float = 0.0
var _camera_shake_strength: float = 0.0
var _camera_initialized: bool = false


func _ready() -> void:
	_resolve_camera()
	_collect_street_props(_street_props_root)
	get_viewport().size_changed.connect(_apply_camera_aspect_compensation)
	_apply_camera_aspect_compensation()


# 递归收集 StreetProps 下的面片，使分类容器内的道路装饰也参与滚动。
func _collect_street_props(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is Sprite3D:
			_street_props.append(child as Sprite3D)
		_collect_street_props(child)


func _process(delta: float) -> void:
	if scrolling:
		_scroll_offset = fposmod(_scroll_offset + scroll_speed * delta, ROAD_TILE_LENGTH)
		for index: int in range(_road_segments.size()):
			_road_segments[index].position.z = ROAD_FIRST_CENTER_Z + float(index) * ROAD_TILE_LENGTH + _scroll_offset
		for prop: Sprite3D in _street_props:
			prop.position.z += scroll_speed * delta
			if prop.position.z > STREET_WRAP_EDGE_Z:
				prop.position.z -= STREET_WRAP_LENGTH
	_process_camera_shake(delta)


# 所有轻量震屏统一通过背景相机调用，连续触发时保留更强且更长的一次。
func shake_camera(strength: float = 0.055, duration: float = 0.14) -> void:
	_resolve_camera()
	_camera_shake_strength = maxf(_camera_shake_strength, maxf(0.0, strength))
	_camera_shake_duration = maxf(_camera_shake_duration, maxf(MINIMUM_SHAKE_DURATION, duration))
	_camera_shake_remaining = maxf(_camera_shake_remaining, maxf(MINIMUM_SHAKE_DURATION, duration))


func _process_camera_shake(delta: float) -> void:
	if not _resolve_camera():
		return
	if _camera_shake_remaining <= 0.0:
		_camera.position = _camera_base_position
		_camera_shake_strength = 0.0
		_camera_shake_duration = 0.0
		return
	_camera_shake_remaining = maxf(0.0, _camera_shake_remaining - delta)
	var fade: float = _camera_shake_remaining / maxf(MINIMUM_SHAKE_DURATION, _camera_shake_duration)
	var offset: Vector2 = Vector2(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	).normalized() * _camera_shake_strength * fade
	_camera.position = _camera_base_position + Vector3(offset.x, offset.y, 0.0)


func _resolve_camera() -> bool:
	if _camera == null:
		_camera = get_node_or_null("PaperCamera") as Camera3D
	if _camera == null:
		return false
	if _camera_initialized:
		return true
	_camera_base_position = _camera.position
	_camera_initialized = true
	return true


func set_cart(source_cart: Cart3D) -> void:
	_cart = source_cart
	_apply_camera_aspect_compensation()


# 长竖屏把新增纵向视野放到道路远端，保持餐车与横向玩法区域的屏幕尺度。
func _apply_camera_aspect_compensation() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var aspect: float = viewport_size.x / viewport_size.y
	if aspect >= DESIGN_ASPECT:
		_camera.v_offset = 0.0
		return
	var cart_world_position: Vector3 = (
		_cart.global_position
		if is_instance_valid(_cart)
		else Vector3(Playfield.ROAD_LEFT + Playfield.ROAD_WIDTH * 0.5, 0.0, Playfield.CART_Z)
	)
	var camera_to_cart: Vector3 = cart_world_position - _camera.global_position
	var cart_depth: float = camera_to_cart.dot(-_camera.global_basis.z)
	var horizontal_half_extent: float = cart_depth * tan(deg_to_rad(_camera.fov) * 0.5)
	_camera.v_offset = horizontal_half_extent * (1.0 / aspect - 1.0 / DESIGN_ASPECT)
