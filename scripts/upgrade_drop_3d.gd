class_name UpgradeDrop3D
extends Node3D

const PANEL_HEIGHT: float = 1.44
# 结算后沿用食客离屏线继续前进，避免未拾取的奖励门贴着餐车消失。
const POST_CART_DESPAWN_OFFSET_Z: float = Playfield.CUSTOMER_DESPAWN_Z - Playfield.CART_Z

var run: RunController3D
var upgrade: UpgradeData
var baseline_appetite: float = 1.0
var occupied_regions: int = 2
var spawn_index: int = 0
var upgrade_health: float = 0.0
var move_speed: float = 2.5
var resolved: bool = false
@onready var _target: Node3D = %RewardTarget
var _hit_feedback_remaining: float = 0.0
@onready var _panel_mesh: MeshInstance3D = %Panel
@onready var _panel_box: BoxMesh = _panel_mesh.mesh as BoxMesh
@onready var _label: Label3D = %DropLabel
@onready var _health_label: Label3D = %HealthLabel


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
	upgrade_health = (
		baseline_appetite
		* (1.0 - upgrade.value_ratio)
		* maxf(0.0, upgrade.source_scale)
	)
	position = start_position
	_configure_visual()
	_refresh_label()


func _process(delta: float) -> void:
	if run == null:
		return
	if resolved:
		if not run.is_world_scrolling():
			queue_free()
			return
		position.z += travel_speed() * delta
		if position.z >= run.cart_destination_z() + POST_CART_DESPAWN_OFFSET_Z:
			queue_free()
		return
	if upgrade == null:
		return
	if _hit_feedback_remaining > 0.0:
		_hit_feedback_remaining = maxf(0.0, _hit_feedback_remaining - delta)
		_refresh_feedback()
	if run.is_world_scrolling():
		position.z += travel_speed() * delta
	var cart: Cart3D = run.cart
	if cart == null:
		return
	if overlaps_cart(cart):
		resolved = true
		run.on_customer_reward_gate_collected(upgrade)
		queue_free()
	elif has_passed_cart(cart):
		resolved = true


func target_for_cart_x(cart_x: float) -> Node3D:
	if resolved or upgrade_health <= 0.0001 or not contains_cart_x(cart_x):
		return null
	return _target


func contains_cart_x(cart_x: float) -> bool:
	var half_width: float = _panel_width() * 0.5
	return cart_x >= position.x - half_width and cart_x < position.x + half_width


# 奖励门使用自身占用矩形与餐车可编辑碰撞矩形做 X/Z 平面重叠判定。
func collision_rect_xz() -> Rect2:
	var gate_scale: Vector2 = Vector2(absf(scale.x), absf(scale.z))
	var gate_size: Vector2 = Vector2(_panel_width(), PANEL_HEIGHT) * gate_scale
	return Rect2(Vector2(position.x, position.z) - gate_size * 0.5, gate_size)


# 只有横向和纵向都重叠时才视为奖励门被餐车拾取。
func overlaps_cart(cart: Cart3D) -> bool:
	if cart == null:
		return false
	return collision_rect_xz().intersects(cart.collision_rect_xz())


# 横向错开的奖励门在完整越过餐车碰撞箱后结束本次拾取窗口。
func has_passed_cart(cart: Cart3D) -> bool:
	if cart == null:
		return false
	var gate_rect: Rect2 = collision_rect_xz()
	var cart_rect: Rect2 = cart.collision_rect_xz()
	return gate_rect.position.y >= cart_rect.position.y + cart_rect.size.y


func try_receive_projectile(projectile: FoodProjectile3D) -> bool:
	if resolved or projectile == null or upgrade_health <= 0.0001:
		return false
	var local_position_3d: Vector3 = to_local(projectile.global_position)
	var panel: Rect2 = Rect2(-_panel_width() * 0.5, -PANEL_HEIGHT * 0.5, _panel_width(), PANEL_HEIGHT)
	var panel_overlaps: bool = (
		projectile.overlaps_target_rect(self, panel)
		if projectile.attack_kind == FoodData.AttackKind.CARROT_SWEEP
		else panel.grow(projectile.radius).has_point(Vector2(local_position_3d.x, local_position_3d.z))
	)
	if not panel_overlaps:
		return false
	if not projectile.can_hit(_target):
		return false
	if run != null:
		run.resolve_reward_projectile_hit(self, _target, projectile)
	else:
		receive_damage(projectile.satisfaction)
	return projectile.register_hit(_target)


func try_receive_puddle(puddle: FoodPuddle3D) -> void:
	if resolved or puddle == null or upgrade_health <= 0.0001:
		return
	var local_position_3d: Vector3 = to_local(puddle.global_position)
	var panel: Rect2 = Rect2(-_panel_width() * 0.5, -PANEL_HEIGHT * 0.5, _panel_width(), PANEL_HEIGHT)
	if not panel.grow(puddle.radius).has_point(Vector2(local_position_3d.x, local_position_3d.z)):
		return
	if puddle.observe_target(_target):
		receive_puddle_damage(_target, puddle.satisfaction)


func receive_damage(amount: float) -> void:
	if resolved or amount <= 0.0 or upgrade_health <= 0.0001:
		return
	upgrade_health = maxf(0.0, upgrade_health - amount)
	var scaled_health_pool: float = baseline_appetite * maxf(0.001, upgrade.source_scale)
	upgrade.set_value_ratio(1.0 - upgrade_health / scaled_health_pool)
	_hit_feedback_remaining = 0.12
	_refresh_label()
	_refresh_feedback()


func receive_puddle_damage(target: Node3D, amount: float) -> void:
	if target == _target:
		receive_damage(amount)


func travel_speed() -> float:
	return move_speed * (run.forward_speed_multiplier() if run != null else 1.0)


func _panel_width() -> float:
	return maxf(0.82, float(occupied_regions) * Playfield.REGION_WIDTH - 0.18)


func _resolve_visual_nodes() -> void:
	if _panel_mesh != null:
		return
	_target = get_node("RewardTarget") as Node3D
	_panel_mesh = get_node("Panel") as MeshInstance3D
	_panel_box = _panel_mesh.mesh as BoxMesh
	_label = get_node("DropLabel") as Label3D
	_health_label = get_node("HealthLabel") as Label3D


func _configure_visual() -> void:
	var width: float = _panel_width()
	_panel_box.size.x = width
	_label.width = maxf(180.0, Playfield.world_to_design(width) * 2.0)


func _refresh_label() -> void:
	if _label == null or upgrade == null:
		return
	var maximum_durability: float = 100.0 if run == null else run.state.maximum_durability
	_label.text = "%s%s\n%s\n%s" % [
		"小份 " if not upgrade.source_label.is_empty() else "",
		upgrade.display_name,
		upgrade.effect_text(maximum_durability),
		upgrade.rarity_name,
	]
	_label.modulate = Color.WHITE
	_health_label.text = str(ceili(upgrade_health))
	var panel_material: StandardMaterial3D = _panel_mesh.material_override as StandardMaterial3D
	panel_material.albedo_color = upgrade.rarity_color.darkened(0.22)


func _refresh_feedback() -> void:
	var material: StandardMaterial3D = _panel_mesh.material_override as StandardMaterial3D
	var enabled: bool = _hit_feedback_remaining > 0.0
	material.emission_enabled = enabled
	material.emission = Color.WHITE if enabled else Color.BLACK
	material.emission_energy_multiplier = 0.75 if enabled else 0.0
