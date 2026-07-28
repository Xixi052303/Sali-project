class_name Customer3D
extends Node3D

signal satisfied(customer: Customer3D)
signal collided_with_cart(customer: Customer3D)
signal escaped(customer: Customer3D)
signal ranged_attack(customer: Customer3D, amount: float)

const CUSTOMER_MODEL_HEIGHT: float = 1.6

var data: CustomerData
var run: RunController3D
var remaining_appetite: float = 0.0
var spawn_index: int = 0
# 普通食客生成时锁定奖励及其基准胃口，满足后原样交给奖励门。
var reward_upgrade: UpgradeData
var reward_baseline_appetite: float = 1.0
var active: bool = false
var _attack_remaining: float = 0.0
var _hit_feedback_remaining: float = 0.0
# 运行时模型只属于当前食客实例，重新配置时立即替换。
var _customer_model: Node3D
@onready var _visual_root: Node3D = %PaperCustomerVisual
@onready var _model_root: Node3D = %ModelRoot
@onready var _body_mesh: MeshInstance3D = %Body
@onready var _head_mesh: MeshInstance3D = %Head
@onready var _shadow_mesh: MeshInstance3D = %ContactShadow
@onready var _appetite_label: Label3D = %AppetiteLabel


func configure(
	source_data: CustomerData,
	run_controller: RunController3D,
	index: int,
	spawn_appetite: float,
	spawn_reward_upgrade: UpgradeData = null,
	baseline_appetite: float = 1.0
) -> void:
	_resolve_visual_nodes()
	data = source_data
	run = run_controller
	spawn_index = index
	remaining_appetite = maxf(1.0, spawn_appetite)
	reward_upgrade = spawn_reward_upgrade
	reward_baseline_appetite = maxf(1.0, baseline_appetite)
	_attack_remaining = data.attack_interval
	active = true
	_configure_visual()
	_refresh_label()


func _process(delta: float) -> void:
	if not active or data == null or run == null:
		return
	if _hit_feedback_remaining > 0.0:
		_hit_feedback_remaining = maxf(0.0, _hit_feedback_remaining - delta)
		var pulse: float = _hit_feedback_remaining / 0.12
		_visual_root.scale = Vector3.ONE * (1.0 + pulse * 0.05)
	else:
		_visual_root.scale = Vector3.ONE
	if run.is_world_scrolling():
		position.z += travel_speed() * delta
	if data.behavior == CustomerData.Behavior.RANGED and position.z > 1.8 and position.z < 8.2:
		_attack_remaining -= delta
		if _attack_remaining <= 0.0:
			_attack_remaining = data.attack_interval
			ranged_attack.emit(self, remaining_appetite * data.attack_ratio)
	if run.customer_collides_with_cart(self):
		active = false
		collided_with_cart.emit(self)
	elif position.z >= run.cart_destination_z() + (Playfield.CUSTOMER_DESPAWN_Z - Playfield.CART_Z):
		active = false
		escaped.emit(self)


func receive_satisfaction(amount: float) -> void:
	if not active or amount <= 0.0:
		return
	remaining_appetite = maxf(0.0, remaining_appetite - amount)
	_hit_feedback_remaining = 0.12
	_refresh_label()
	if remaining_appetite <= 0.0:
		active = false
		satisfied.emit(self)


func hit_radius() -> float:
	if data == null:
		return 0.4
	return maxf(0.44, float(data.occupied_regions) * Playfield.REGION_WIDTH * 0.42)


func collision_rect_xz() -> Rect2:
	var width: float = _body_width()
	return Rect2(Vector2(position.x - width * 0.5, position.z - 0.42), Vector2(width, 0.84))


func travel_speed() -> float:
	if data == null or run == null:
		return 0.0
	return run.world_scroll_speed + Playfield.design_to_world(data.move_speed)


func _body_width() -> float:
	if data == null:
		return 0.82
	return maxf(0.82, float(data.occupied_regions) * Playfield.REGION_WIDTH - 0.18)


func _resolve_visual_nodes() -> void:
	if _body_mesh != null:
		return
	_visual_root = get_node("PaperCustomerVisual") as Node3D
	_model_root = get_node("PaperCustomerVisual/ModelRoot") as Node3D
	_body_mesh = get_node("PaperCustomerVisual/Body") as MeshInstance3D
	_head_mesh = get_node("PaperCustomerVisual/Head") as MeshInstance3D
	_shadow_mesh = get_node("PaperCustomerVisual/ContactShadow") as MeshInstance3D
	_appetite_label = get_node("PaperCustomerVisual/AppetiteLabel") as Label3D


func _configure_visual() -> void:
	var width: float = _body_width()
	var color: Color = data.body_color
	var body_box: BoxMesh = _body_mesh.mesh as BoxMesh
	body_box.size.x = width
	var body_material: StandardMaterial3D = _body_mesh.material_override as StandardMaterial3D
	body_material.albedo_color = color
	_head_mesh.scale.x = minf(width * 0.52, 0.9)
	var head_material: StandardMaterial3D = _head_mesh.material_override as StandardMaterial3D
	head_material.albedo_color = color.lightened(0.12)
	_shadow_mesh.scale.x = width
	_appetite_label.width = maxf(180.0, Playfield.world_to_design(width) * 1.3)
	_configure_customer_model()


# 将来源尺寸不同的角色模型统一到当前食客纸片高度，并保持脚底落在道路平面。
func _configure_customer_model() -> void:
	if _customer_model != null:
		_customer_model.free()
		_customer_model = null
	var uses_model: bool = data.model_scene != null
	_body_mesh.visible = not uses_model
	_head_mesh.visible = not uses_model
	if not uses_model:
		return
	_customer_model = data.model_scene.instantiate() as Node3D
	if _customer_model == null:
		push_error("食客模型根节点必须继承 Node3D: %s" % String(data.id))
		_body_mesh.visible = true
		_head_mesh.visible = true
		return
	_model_root.add_child(_customer_model)
	var bounds: AABB = _model_bounds(_customer_model)
	if bounds.size.y <= 0.001:
		push_error("食客模型缺少可用网格包围盒: %s" % String(data.id))
		_customer_model.free()
		_customer_model = null
		_body_mesh.visible = true
		_head_mesh.visible = true
		return
	var model_scale: float = CUSTOMER_MODEL_HEIGHT / bounds.size.y
	_customer_model.scale = Vector3.ONE * model_scale
	_customer_model.position = Vector3(
		-bounds.get_center().x * model_scale,
		-bounds.position.y * model_scale,
		-bounds.get_center().z * model_scale
	)


# 导入场景可包含多层节点，包围盒统一转换到模型根节点的局部空间。
func _model_bounds(model_root: Node3D) -> AABB:
	var bounds: AABB = AABB()
	var has_bounds: bool = false
	for child: Node in model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var relative_transform: Transform3D = _transform_relative_to_root(mesh_instance, model_root)
		var mesh_bounds: AABB = relative_transform * mesh_instance.get_aabb()
		bounds = mesh_bounds if not has_bounds else bounds.merge(mesh_bounds)
		has_bounds = true
	return bounds


# 只组合局部变换，使食客在尚未进入SceneTree的测试与预生成阶段也能完成配置。
func _transform_relative_to_root(node: Node3D, model_root: Node3D) -> Transform3D:
	var relative_transform: Transform3D = node.transform
	var current: Node3D = node.get_parent() as Node3D
	while current != null and current != model_root:
		relative_transform = current.transform * relative_transform
		current = current.get_parent() as Node3D
	return relative_transform


func _refresh_label() -> void:
	if _appetite_label == null:
		return
	_appetite_label.text = str(ceili(remaining_appetite))
	_appetite_label.modulate = Color("#fff0c8")
