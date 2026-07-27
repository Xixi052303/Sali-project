class_name UpgradeGate3D
extends Node3D

const LEFT_PANEL: Rect2 = Rect2(66.0, -72.0, 288.0, 144.0)
const RIGHT_PANEL: Rect2 = Rect2(366.0, -72.0, 288.0, 144.0)
const SIDE_DIVIDER_X: float = 360.0

var run: RunController3D
var left_upgrade: UpgradeData
var right_upgrade: UpgradeData
var start_food_gate: bool = false
var resolved: bool = false
# 远景门需要在既有时间轴窗口内抵达，速度高于普通道路滚动但不改变横向选择规则。
var move_speed: float = 500.0
var spawn_index: int = 0
var baseline_appetite: float = 1.0
# 基础胃口负责撞门损伤并公开显示；隐藏胃口只负责基础层击破后的奖励升值。
var left_base_health: float = 0.0
var right_base_health: float = 0.0
var left_upgrade_health: float = 0.0
var right_upgrade_health: float = 0.0

@onready var _left_target: Node3D = %LeftTarget
@onready var _right_target: Node3D = %RightTarget
var _left_hit_feedback: float = 0.0
var _right_hit_feedback: float = 0.0
@onready var _left_label: Label3D = %LeftLabel
@onready var _right_label: Label3D = %RightLabel
@onready var _left_health_label: Label3D = %LeftHealthLabel
@onready var _right_health_label: Label3D = %RightHealthLabel
@onready var _left_mesh: MeshInstance3D = %LeftPanel
@onready var _right_mesh: MeshInstance3D = %RightPanel


# 生成时锁定门的基准胃口，并分别建立公开基础层和隐藏升值层。
func configure(
	run_controller: RunController3D,
	left: UpgradeData,
	right: UpgradeData,
	is_start_gate: bool = false,
	gate_baseline_appetite: float = 1.0,
	index: int = 0
) -> void:
	_resolve_visual_nodes()
	run = run_controller
	left_upgrade = left
	right_upgrade = right
	start_food_gate = is_start_gate
	baseline_appetite = maxf(1.0, gate_baseline_appetite)
	spawn_index = index
	position = Vector3.ZERO if start_food_gate else Vector3(0.0, 0.0, Playfield.FORWARD_SPAWN_Z)
	if not start_food_gate:
		left_base_health = baseline_appetite * (1.0 + left_upgrade.value_ratio)
		right_base_health = baseline_appetite * (1.0 + right_upgrade.value_ratio)
		left_upgrade_health = baseline_appetite * (1.0 - left_upgrade.value_ratio)
		right_upgrade_health = baseline_appetite * (1.0 - right_upgrade.value_ratio)
	_refresh_labels()


func _process(delta: float) -> void:
	if run == null or resolved:
		return
	if _left_hit_feedback > 0.0 or _right_hit_feedback > 0.0:
		_left_hit_feedback = maxf(0.0, _left_hit_feedback - delta)
		_right_hit_feedback = maxf(0.0, _right_hit_feedback - delta)
		_refresh_feedback()
	if run.is_world_scrolling():
		position.z += move_speed * delta
	if position.z >= Playfield.CART_Z:
		resolved = true
		var cart_x: float = run.cart.position.x
		run.on_gate_selected(selected_upgrade_for_x(cart_x), start_food_gate, selected_base_health_for_x(cart_x))
		queue_free()


func target_for_cart_x(cart_x: float) -> Node3D:
	if start_food_gate or resolved:
		return null
	var use_left: bool = cart_x < SIDE_DIVIDER_X
	if not side_is_attackable(use_left):
		return null
	return _left_target if use_left else _right_target


func selected_upgrade_for_x(cart_x: float) -> UpgradeData:
	return left_upgrade if cart_x < SIDE_DIVIDER_X else right_upgrade


func selected_base_health_for_x(cart_x: float) -> float:
	return left_base_health if cart_x < SIDE_DIVIDER_X else right_base_health


func try_receive_projectile(projectile: FoodProjectile3D) -> bool:
	if start_food_gate or resolved or projectile == null:
		return false
	var local_position_3d: Vector3 = to_local(projectile.global_position)
	var local_position_xz: Vector2 = Vector2(local_position_3d.x, local_position_3d.z)
	var hit_left: bool = local_position_xz.x < SIDE_DIVIDER_X
	var panel: Rect2 = LEFT_PANEL if hit_left else RIGHT_PANEL
	if not panel.grow(projectile.radius).has_point(local_position_xz):
		return false
	if not side_is_attackable(hit_left):
		return false
	var target: Node3D = _left_target if hit_left else _right_target
	if not projectile.can_hit(target):
		return false
	receive_damage(hit_left, projectile.satisfaction)
	return projectile.register_hit(target)


func receive_damage(hit_left: bool, amount: float) -> void:
	if start_food_gate or resolved or amount <= 0.0 or not side_is_attackable(hit_left):
		return
	if hit_left:
		if left_base_health > 0.0001:
			left_base_health = maxf(0.0, left_base_health - amount)
		else:
			left_upgrade_health = maxf(0.0, left_upgrade_health - amount)
			left_upgrade.set_value_ratio(1.0 - left_upgrade_health / baseline_appetite)
		_left_hit_feedback = 0.12
	else:
		if right_base_health > 0.0001:
			right_base_health = maxf(0.0, right_base_health - amount)
		else:
			right_upgrade_health = maxf(0.0, right_upgrade_health - amount)
			right_upgrade.set_value_ratio(1.0 - right_upgrade_health / baseline_appetite)
		_right_hit_feedback = 0.12
	_refresh_labels()
	_refresh_feedback()


func side_is_attackable(left_side: bool) -> bool:
	if start_food_gate:
		return false
	if left_side:
		return left_base_health > 0.0001 or left_upgrade_health > 0.0001
	return right_base_health > 0.0001 or right_upgrade_health > 0.0001


func travel_speed() -> float:
	return move_speed


func _resolve_visual_nodes() -> void:
	if _left_mesh != null:
		return
	_left_target = get_node("LeftTarget") as Node3D
	_right_target = get_node("RightTarget") as Node3D
	_left_mesh = get_node("LeftPanel") as MeshInstance3D
	_right_mesh = get_node("RightPanel") as MeshInstance3D
	_left_label = get_node("LeftLabel") as Label3D
	_right_label = get_node("RightLabel") as Label3D
	_left_health_label = get_node("LeftHealthLabel") as Label3D
	_right_health_label = get_node("RightHealthLabel") as Label3D


func _refresh_labels() -> void:
	if _left_label == null or left_upgrade == null or right_upgrade == null:
		return
	var maximum_durability: float = 100.0 if run == null else run.state.maximum_durability
	_left_label.text = _label_text(left_upgrade, maximum_durability)
	_right_label.text = _label_text(right_upgrade, maximum_durability)
	_left_label.modulate = Color.WHITE
	_right_label.modulate = Color.WHITE
	_left_health_label.visible = not start_food_gate
	_right_health_label.visible = not start_food_gate
	_left_health_label.text = str(ceili(left_base_health))
	_right_health_label.text = str(ceili(right_base_health))
	_left_health_label.modulate = left_upgrade.rarity_color.lightened(0.18)
	_right_health_label.modulate = right_upgrade.rarity_color.lightened(0.18)
	_refresh_rarity_colors()


func _label_text(upgrade: UpgradeData, maximum_durability: float) -> String:
	if start_food_gate:
		return "土豆 Lv.1\n选择开局食材"
	return "%s\n%s\n%s" % [
		upgrade.display_name,
		upgrade.effect_text(maximum_durability),
		upgrade.rarity_name,
	]


# 门板颜色始终来自当前奖励稀有度，隐藏升值层跨档时立即刷新。
func _refresh_rarity_colors() -> void:
	var left_material: StandardMaterial3D = _left_mesh.material_override as StandardMaterial3D
	var right_material: StandardMaterial3D = _right_mesh.material_override as StandardMaterial3D
	if start_food_gate:
		left_material.albedo_color = Color("#3d513d")
		right_material.albedo_color = Color("#694035")
		return
	left_material.albedo_color = left_upgrade.rarity_color.darkened(0.22)
	right_material.albedo_color = right_upgrade.rarity_color.darkened(0.22)


func _refresh_feedback() -> void:
	_set_emission(_left_mesh, _left_hit_feedback > 0.0)
	_set_emission(_right_mesh, _right_hit_feedback > 0.0)


func _set_emission(mesh: MeshInstance3D, enabled: bool) -> void:
	var material: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	material.emission_enabled = enabled
	material.emission = Color.WHITE if enabled else Color.BLACK
	material.emission_energy_multiplier = 0.75 if enabled else 0.0
