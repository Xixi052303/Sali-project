class_name UpgradeGate3D
extends Node3D

const LEFT_PANEL: Rect2 = Rect2(0.66, -0.72, 2.88, 1.44)
const RIGHT_PANEL: Rect2 = Rect2(3.66, -0.72, 2.88, 1.44)
const SIDE_DIVIDER_X: float = 3.6
# 结算后沿用食客离屏线继续前进，避免门在餐车旁瞬间消失。
const POST_CART_DESPAWN_OFFSET_Z: float = Playfield.CUSTOMER_DESPAWN_Z - Playfield.CART_Z

var run: RunController3D
var left_upgrade: UpgradeData
var right_upgrade: UpgradeData
var start_food_gate: bool = false
var start_options_by_slot: Dictionary[int, Array] = {}
var resolved: bool = false
# 道路延长只让门提前出现，接近速度继续保持原竖切片节奏。
var move_speed: float = 2.5
var spawn_index: int = 0
var baseline_appetite: float = 1.0
# 基础胃口负责撞门损伤并公开显示；隐藏胃口只负责基础层击破后的奖励升值。
var left_base_health: float = 0.0
var right_base_health: float = 0.0
var left_upgrade_health: float = 0.0
var right_upgrade_health: float = 0.0
var _player_resolved: Dictionary[int, bool] = {}

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
# 门节点在编辑器脚本测试中也会被单独解析，因此通过根节点访问网络会话。
@onready var _network_session: Variant = get_node_or_null("/root/NetworkSession")


# 生成时锁定门的基准胃口，并分别建立公开基础层和隐藏升值层。
func configure(
	run_controller: RunController3D,
	left: UpgradeData,
	right: UpgradeData,
	is_start_gate: bool = false,
	gate_baseline_appetite: float = 1.0,
	index: int = 0,
	per_player_start_options: Dictionary[int, Array] = {}
) -> void:
	_resolve_visual_nodes()
	run = run_controller
	left_upgrade = left
	right_upgrade = right
	start_food_gate = is_start_gate
	start_options_by_slot = per_player_start_options.duplicate(true)
	resolved = false
	if start_options_by_slot.is_empty() and left != null and right != null:
		start_options_by_slot[1] = [left, right]
	baseline_appetite = maxf(1.0, gate_baseline_appetite)
	spawn_index = index
	_player_resolved.clear()
	# 开局门也从远端屏外进入，避免开始出餐后在道路中段突然出现。
	position = Vector3(0.0, 0.0, Playfield.FORWARD_SPAWN_Z)
	if not start_food_gate:
		left_base_health = baseline_appetite * (1.0 + left_upgrade.value_ratio)
		right_base_health = baseline_appetite * (1.0 + right_upgrade.value_ratio)
		left_upgrade_health = baseline_appetite * (1.0 - left_upgrade.value_ratio)
		right_upgrade_health = baseline_appetite * (1.0 - right_upgrade.value_ratio)
	_refresh_labels()


func _process(delta: float) -> void:
	if run == null:
		return
	var network_client: bool = (
		_network_session != null
		and _network_session.is_networked()
		and not _network_session.is_host()
	)
	if resolved:
		if network_client:
			return
		if not run.is_world_scrolling():
			queue_free()
			return
		position.z += travel_speed() * delta
		if position.z >= run.cart_destination_z() + POST_CART_DESPAWN_OFFSET_Z:
			queue_free()
		return
	if _left_hit_feedback > 0.0 or _right_hit_feedback > 0.0:
		_left_hit_feedback = maxf(0.0, _left_hit_feedback - delta)
		_right_hit_feedback = maxf(0.0, _right_hit_feedback - delta)
		_refresh_feedback()
	if run.is_world_scrolling():
		position.z += travel_speed() * delta
	if _network_session != null and _network_session.is_networked() and not _network_session.is_host():
		return
	var contexts: Array[PlayerRunContext] = run.get_player_contexts()
	if contexts.is_empty():
		return
	for context: PlayerRunContext in contexts:
		if _player_resolved.get(context.slot, false):
			continue
		var cart: Cart3D = context.cart
		if cart == null:
			continue
		var overlap_side: int = _cart_overlap_side(cart)
		if overlap_side >= 0:
			var use_left: bool = overlap_side == 0
			var base_health: float = left_base_health if use_left else right_base_health
			if context.is_ghost() and not start_food_gate and not MultiplayerRules.ghost_can_claim_normal_gate(base_health):
				continue
			_player_resolved[context.slot] = true
			var selected_upgrade: UpgradeData = (
				selected_upgrade_for_x(cart.position.x, context.slot)
				if start_food_gate
				else (left_upgrade if use_left else right_upgrade)
			)
			run.on_gate_selected_for_player(
				context.slot,
				selected_upgrade,
				start_food_gate,
				base_health
			)
		elif start_food_gate and position.z >= cart.position.z:
			_player_resolved[context.slot] = true
			run.on_gate_selected_for_player(
				context.slot,
				selected_upgrade_for_x(cart.position.x, context.slot),
				true,
				0.0
			)
		elif _has_passed_cart(cart):
			_player_resolved[context.slot] = true
	if _all_players_resolved(contexts):
		resolved = true
		queue_free()


func target_for_cart_x(cart_x: float) -> Node3D:
	if start_food_gate or resolved:
		return null
	var use_left: bool = cart_x < SIDE_DIVIDER_X
	if not side_is_attackable(use_left):
		return null
	return _left_target if use_left else _right_target


func selected_upgrade_for_x(cart_x: float, player_slot: int = 1) -> UpgradeData:
	var options: Array = start_options_by_slot.get(player_slot, [left_upgrade, right_upgrade])
	if options.size() < 2:
		return left_upgrade if cart_x < SIDE_DIVIDER_X else right_upgrade
	return options[0] if cart_x < SIDE_DIVIDER_X else options[1]


func selected_base_health_for_x(cart_x: float) -> float:
	return left_base_health if cart_x < SIDE_DIVIDER_X else right_base_health


func _all_players_resolved(contexts: Array[PlayerRunContext]) -> bool:
	for context: PlayerRunContext in contexts:
		if not _player_resolved.get(context.slot, false):
			return false
	return true


func network_snapshot() -> Dictionary:
	var resolved_slots: Array[int] = []
	for slot: int in _player_resolved:
		if _player_resolved[slot]:
			resolved_slots.append(slot)
	return {
		"spawn_index": spawn_index,
		"x": position.x,
		"z": position.z,
		"left_base": left_base_health,
		"right_base": right_base_health,
		"left_upgrade": left_upgrade_health,
		"right_upgrade": right_upgrade_health,
		"resolved": resolved,
		"resolved_slots": resolved_slots,
	}


func apply_network_snapshot(snapshot: Dictionary) -> void:
	position.x = float(snapshot.get("x", position.x))
	position.z = float(snapshot.get("z", position.z))
	left_base_health = float(snapshot.get("left_base", left_base_health))
	right_base_health = float(snapshot.get("right_base", right_base_health))
	left_upgrade_health = float(snapshot.get("left_upgrade", left_upgrade_health))
	right_upgrade_health = float(snapshot.get("right_upgrade", right_upgrade_health))
	resolved = bool(snapshot.get("resolved", resolved))
	_player_resolved.clear()
	for slot: int in snapshot.get("resolved_slots", []):
		_player_resolved[slot] = true
	_refresh_labels()


# 把左右门板的逻辑范围转换为餐车所在的 X/Z 世界平面。
func _panel_rect_xz(left_side: bool) -> Rect2:
	var panel: Rect2 = LEFT_PANEL if left_side else RIGHT_PANEL
	var gate_scale: Vector2 = Vector2(absf(scale.x), absf(scale.z))
	var panel_position: Vector2 = Vector2(
		panel.position.x * gate_scale.x,
		panel.position.y * gate_scale.y
	)
	return Rect2(
		Vector2(position.x, position.z) + panel_position,
		panel.size * gate_scale
	)


# 返回与餐车碰撞箱重叠的门板，左右都重叠时沿用餐车中心线选择规则。
func _cart_overlap_side(cart: Cart3D) -> int:
	if cart == null:
		return -1
	var cart_rect: Rect2 = cart.collision_rect_xz()
	var left_overlaps: bool = _panel_rect_xz(true).intersects(cart_rect)
	var right_overlaps: bool = _panel_rect_xz(false).intersects(cart_rect)
	if left_overlaps and right_overlaps:
		return 0 if cart.position.x < SIDE_DIVIDER_X else 1
	if left_overlaps:
		return 0
	if right_overlaps:
		return 1
	return -1


# 横向错开的普通门在两块门板都完全越过餐车碰撞箱后结束拾取窗口。
func _has_passed_cart(cart: Cart3D) -> bool:
	if cart == null:
		return false
	var cart_rect: Rect2 = cart.collision_rect_xz()
	var left_rect: Rect2 = _panel_rect_xz(true)
	return left_rect.position.y >= cart_rect.position.y + cart_rect.size.y


func try_receive_projectile(projectile: FoodProjectile3D) -> bool:
	if start_food_gate or resolved or projectile == null:
		return false
	var local_position_3d: Vector3 = to_local(projectile.global_position)
	var local_position_xz: Vector2 = Vector2(local_position_3d.x, local_position_3d.z)
	var hit_left: bool = local_position_xz.x < SIDE_DIVIDER_X
	var panel: Rect2 = LEFT_PANEL if hit_left else RIGHT_PANEL
	var panel_overlaps: bool = (
		projectile.overlaps_target_rect(self, panel)
		if projectile.attack_kind == FoodData.AttackKind.CARROT_SWEEP
		else panel.grow(projectile.radius).has_point(local_position_xz)
	)
	if not panel_overlaps:
		return false
	if not side_is_attackable(hit_left):
		return false
	var target: Node3D = _left_target if hit_left else _right_target
	if not projectile.can_hit(target):
		return false
	if run != null:
		run.resolve_gate_projectile_hit(self, hit_left, target, projectile)
	else:
		receive_damage(hit_left, projectile.satisfaction)
	return projectile.register_hit(target)


func try_receive_puddle(puddle: FoodPuddle3D) -> void:
	if start_food_gate or resolved or puddle == null:
		return
	var local_position_3d: Vector3 = to_local(puddle.global_position)
	var local_position_xz: Vector2 = Vector2(local_position_3d.x, local_position_3d.z)
	for hit_left: bool in [true, false]:
		if not side_is_attackable(hit_left):
			continue
		var target: Node3D = _left_target if hit_left else _right_target
		var panel: Rect2 = LEFT_PANEL if hit_left else RIGHT_PANEL
		if not panel.grow(puddle.radius).has_point(local_position_xz):
			continue
		if puddle.observe_target(target):
			receive_puddle_damage(target, puddle.satisfaction)


func receive_damage(hit_left: bool, amount: float) -> void:
	if start_food_gate or resolved or amount <= 0.0 or not side_is_attackable(hit_left):
		return
	if hit_left:
		if left_base_health > 0.0001:
			left_base_health = maxf(0.0, left_base_health - amount)
		else:
			left_upgrade_health = maxf(0.0, left_upgrade_health - amount)
			left_upgrade.set_value_ratio(1.0 - left_upgrade_health / baseline_appetite)
	else:
		if right_base_health > 0.0001:
			right_base_health = maxf(0.0, right_base_health - amount)
		else:
			right_upgrade_health = maxf(0.0, right_upgrade_health - amount)
			right_upgrade.set_value_ratio(1.0 - right_upgrade_health / baseline_appetite)
	_refresh_labels()
	play_hit_feedback(hit_left)


func play_hit_feedback(hit_left: bool) -> void:
	if hit_left:
		_left_hit_feedback = 0.12
	else:
		_right_hit_feedback = 0.12
	_refresh_feedback()


func receive_puddle_damage(target: Node3D, amount: float) -> void:
	if target == _left_target:
		receive_damage(true, amount)
	elif target == _right_target:
		receive_damage(false, amount)


func side_is_attackable(left_side: bool) -> bool:
	if start_food_gate:
		return false
	if left_side:
		return left_base_health > 0.0001 or left_upgrade_health > 0.0001
	return right_base_health > 0.0001 or right_upgrade_health > 0.0001


func travel_speed() -> float:
	return move_speed * (run.forward_speed_multiplier() if run != null else 1.0)


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
	if _network_session == null and is_inside_tree():
		_network_session = get_node_or_null("/root/NetworkSession")
	var networked: bool = _network_session != null and _network_session.is_networked()
	var display_slot: int = _network_session.local_slot if networked else 1
	var display_options: Array = start_options_by_slot.get(display_slot, [left_upgrade, right_upgrade])
	var display_left: UpgradeData = display_options[0] if display_options.size() > 0 else left_upgrade
	var display_right: UpgradeData = display_options[1] if display_options.size() > 1 else right_upgrade
	var maximum_durability: float = 100.0 if run == null else run.state.maximum_durability
	_left_label.text = _label_text(display_left, maximum_durability)
	_right_label.text = _label_text(display_right, maximum_durability)
	_left_label.modulate = Color.WHITE
	_right_label.modulate = Color.WHITE
	_left_health_label.visible = not start_food_gate
	_right_health_label.visible = not start_food_gate
	_left_health_label.text = str(ceili(left_base_health))
	_right_health_label.text = str(ceili(right_base_health))
	_refresh_rarity_colors()


func _label_text(upgrade: UpgradeData, maximum_durability: float) -> String:
	if start_food_gate:
		return "%s Lv.1\n选择开局食材" % upgrade.display_name
	return "%s\n%s\n%s" % [
		upgrade.display_name,
		upgrade.effect_text(maximum_durability),
		upgrade.rarity_name,
	]


# 门板与公开胃口数字共享当前奖励稀有度，隐藏升值层跨档时同步刷新。
func _refresh_rarity_colors() -> void:
	var left_material: StandardMaterial3D = _left_mesh.material_override as StandardMaterial3D
	var right_material: StandardMaterial3D = _right_mesh.material_override as StandardMaterial3D
	if start_food_gate:
		left_material.albedo_color = Color("#3d513d")
		right_material.albedo_color = Color("#694035")
		return
	left_material.albedo_color = left_upgrade.rarity_color.darkened(0.22)
	right_material.albedo_color = right_upgrade.rarity_color.darkened(0.22)
	_left_health_label.modulate = left_upgrade.rarity_color
	_right_health_label.modulate = right_upgrade.rarity_color


func _refresh_feedback() -> void:
	_set_emission(_left_mesh, _left_hit_feedback > 0.0)
	_set_emission(_right_mesh, _right_hit_feedback > 0.0)


func _set_emission(mesh: MeshInstance3D, enabled: bool) -> void:
	var material: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	material.emission_enabled = enabled
	material.emission = Color.WHITE if enabled else Color.BLACK
	material.emission_energy_multiplier = 0.75 if enabled else 0.0
