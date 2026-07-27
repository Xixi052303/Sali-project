class_name UpgradeDrop3D
extends Node3D

const PANEL_HEIGHT: float = 144.0

var run: RunController3D
var upgrade: UpgradeData
var baseline_appetite: float = 1.0
var occupied_regions: int = 2
var spawn_index: int = 0
var upgrade_health: float = 0.0
var move_speed: float = 250.0
var resolved: bool = false
@onready var _target: Node3D = %RewardTarget
var _hit_feedback_remaining: float = 0.0
@onready var _panel_mesh: MeshInstance3D = %Panel
@onready var _panel_box: BoxMesh = _panel_mesh.mesh as BoxMesh
@onready var _label: Label3D = %DropLabel


func configure(
	run_controller: RunController3D,
	upgrade_data: UpgradeData,
	start_position: Vector3,
	gate_baseline_appetite: float,
	gate_occupied_regions: int,
	index: int
) -> void:
	_resolve_visual_nodes()
	run = run_controller
	upgrade = upgrade_data
	baseline_appetite = maxf(1.0, gate_baseline_appetite)
	occupied_regions = clampi(gate_occupied_regions, 1, Playfield.REGION_COUNT)
	spawn_index = index
	upgrade_health = baseline_appetite * (1.0 - upgrade.value_ratio)
	position = start_position
	_configure_visual()
	_refresh_label()


func _process(delta: float) -> void:
	if resolved or run == null or upgrade == null:
		return
	if _hit_feedback_remaining > 0.0:
		_hit_feedback_remaining = maxf(0.0, _hit_feedback_remaining - delta)
		_refresh_feedback()
	if run.is_world_scrolling():
		position.z += move_speed * delta
	if position.z >= Playfield.CART_Z:
		resolved = true
		if contains_cart_x(run.cart.position.x):
			run.on_customer_reward_gate_collected(upgrade)
		queue_free()


func target_for_cart_x(cart_x: float) -> Node3D:
	if resolved or upgrade_health <= 0.0001 or not contains_cart_x(cart_x):
		return null
	return _target


func contains_cart_x(cart_x: float) -> bool:
	var half_width: float = _panel_width() * 0.5
	return cart_x >= position.x - half_width and cart_x < position.x + half_width


func try_receive_projectile(projectile: FoodProjectile3D) -> bool:
	if resolved or projectile == null or upgrade_health <= 0.0001:
		return false
	var local_position_3d: Vector3 = to_local(projectile.global_position)
	var panel: Rect2 = Rect2(-_panel_width() * 0.5, -PANEL_HEIGHT * 0.5, _panel_width(), PANEL_HEIGHT)
	if not panel.grow(projectile.radius).has_point(Vector2(local_position_3d.x, local_position_3d.z)):
		return false
	if not projectile.can_hit(_target):
		return false
	receive_damage(projectile.satisfaction)
	return projectile.register_hit(_target)


func receive_damage(amount: float) -> void:
	if resolved or amount <= 0.0 or upgrade_health <= 0.0001:
		return
	upgrade_health = maxf(0.0, upgrade_health - amount)
	upgrade.set_value_ratio(1.0 - upgrade_health / baseline_appetite)
	_hit_feedback_remaining = 0.12
	_refresh_label()
	_refresh_feedback()


func travel_speed() -> float:
	return move_speed


func _panel_width() -> float:
	return maxf(82.0, float(occupied_regions) * Playfield.REGION_WIDTH - 18.0)


func _resolve_visual_nodes() -> void:
	if _panel_mesh != null:
		return
	_target = get_node("RewardTarget") as Node3D
	_panel_mesh = get_node("Panel") as MeshInstance3D
	_panel_box = _panel_mesh.mesh as BoxMesh
	_label = get_node("DropLabel") as Label3D


func _configure_visual() -> void:
	var width: float = _panel_width()
	_panel_box.size.x = width
	_label.width = maxf(180.0, width * 2.0)


func _refresh_label() -> void:
	if _label == null or upgrade == null:
		return
	var maximum_durability: float = 100.0 if run == null else run.state.maximum_durability
	_label.text = "%s\n%s\n%s" % [upgrade.display_name, upgrade.effect_text(maximum_durability), upgrade.rarity_name]
	_label.modulate = Color.WHITE
	var panel_material: StandardMaterial3D = _panel_mesh.material_override as StandardMaterial3D
	panel_material.albedo_color = upgrade.rarity_color.darkened(0.22)


func _refresh_feedback() -> void:
	var material: StandardMaterial3D = _panel_mesh.material_override as StandardMaterial3D
	var enabled: bool = _hit_feedback_remaining > 0.0
	material.emission_enabled = enabled
	material.emission = Color.WHITE if enabled else Color.BLACK
	material.emission_energy_multiplier = 0.75 if enabled else 0.0
