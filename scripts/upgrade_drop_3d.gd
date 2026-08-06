class_name UpgradeDrop3D
extends Node3D

const PANEL_HEIGHT: float = 1.44
# 结算后沿用食客离屏线继续前进，避免未拾取的奖励门贴着餐车消失。
const POST_CART_DESPAWN_OFFSET_Z: float = Playfield.CUSTOMER_DESPAWN_Z - Playfield.CART_Z

var run: RunController3D
var upgrade: UpgradeData
var baseline_appetite: float = 1.0
# 奖励门文案使用房主生成时冻结的耐久基准，避免各客户端按自己的构筑显示不同点数。
var display_maximum_durability: float = 100.0
var occupied_regions: int = 2
var spawn_index: int = 0
var upgrade_health: float = 0.0
var move_speed: float = 2.5
var resolved: bool = false
var _player_resolved: Dictionary[int, bool] = {}
@onready var _target: Node3D = %RewardTarget
var _hit_feedback_remaining: float = 0.0
@onready var _panel_mesh: MeshInstance3D = %Panel
@onready var _panel_box: BoxMesh = _panel_mesh.mesh as BoxMesh
@onready var _label: Label3D = %DropLabel
@onready var _health_label: Label3D = %HealthLabel
# 掉落门同样不直接依赖 Autoload 全局符号，保持单独脚本解析可用。
@onready var _network_session: Variant = get_node_or_null("/root/NetworkSession")


func configure(
	run_controller: RunController3D,
	upgrade_data: UpgradeData,
	start_position: Vector3,
	gate_baseline_appetite: float,
	gate_occupied_regions: int,
	index: int,
	display_durability: float = 100.0
) -> void:
	_resolve_visual_nodes()
	run = run_controller
	upgrade = upgrade_data
	baseline_appetite = maxf(1.0, gate_baseline_appetite)
	display_maximum_durability = maxf(1.0, display_durability)
	occupied_regions = clampi(gate_occupied_regions, 1, Playfield.REGION_COUNT)
	spawn_index = index
	_player_resolved.clear()
	resolved = false
	upgrade_health = (
		baseline_appetite
		* (1.0 - upgrade.value_ratio)
		* maxf(0.0, upgrade.source_scale)
	)
	position = start_position
	_configure_visual()
	_refresh_label()
	_refresh_local_visibility()


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
	if upgrade == null:
		return
	if _hit_feedback_remaining > 0.0:
		_hit_feedback_remaining = maxf(0.0, _hit_feedback_remaining - delta)
		_refresh_feedback()
	if run.is_world_scrolling():
		position.z += travel_speed() * delta
	if _network_session != null and _network_session.is_networked() and not _network_session.is_host():
		return
	var contexts: Array[PlayerRunContext] = run.get_player_contexts()
	for context: PlayerRunContext in contexts:
		if _player_resolved.get(context.slot, false):
			continue
		var cart: Cart3D = context.cart
		if cart == null:
			continue
		if overlaps_cart(cart):
			_player_resolved[context.slot] = true
			run.on_customer_reward_gate_collected_for_player(context.slot, upgrade)
		elif has_passed_cart(cart):
			_player_resolved[context.slot] = true
	_refresh_local_visibility()
	if _all_players_resolved(contexts):
		resolved = true
		queue_free()


func target_for_cart_x(cart_x: float, player_slot: int = 1) -> Node3D:
	if not is_available_for_player(player_slot) or upgrade_health <= 0.0001 or not contains_cart_x(cart_x):
		return null
	return _target


# 奖励门逐玩家结算；一名玩家完成领取或错过后不影响其他玩家的资格。
func is_available_for_player(player_slot: int) -> bool:
	return not resolved and not _player_resolved.get(maxi(1, player_slot), false)


# 可见性只使用本机槽位，不进入 MultiplayerSynchronizer 的共享属性。
func _refresh_local_visibility() -> void:
	var local_slot: int = 1
	if _network_session != null and _network_session.is_networked():
		local_slot = maxi(1, int(_network_session.local_slot))
	visible = is_available_for_player(local_slot)


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
		"health": upgrade_health,
		"display_maximum_durability": display_maximum_durability,
		"resolved": resolved,
		"resolved_slots": resolved_slots,
	}


func apply_network_snapshot(snapshot: Dictionary) -> void:
	position.x = float(snapshot.get("x", position.x))
	position.z = float(snapshot.get("z", position.z))
	upgrade_health = float(snapshot.get("health", upgrade_health))
	display_maximum_durability = maxf(
		1.0,
		float(snapshot.get("display_maximum_durability", display_maximum_durability))
	)
	if upgrade != null:
		var scaled_health_pool: float = (
			baseline_appetite * maxf(0.001, upgrade.source_scale)
		)
		upgrade.set_value_ratio(1.0 - upgrade_health / scaled_health_pool)
	resolved = bool(snapshot.get("resolved", resolved))
	_player_resolved.clear()
	for slot: int in snapshot.get("resolved_slots", []):
		_player_resolved[slot] = true
	_refresh_label()
	_refresh_feedback()
	_refresh_local_visibility()


func try_receive_projectile(projectile: FoodProjectile3D) -> bool:
	if (
		projectile == null
		or not is_available_for_player(projectile.owner_slot)
		or upgrade_health <= 0.0001
	):
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
	if (
		puddle == null
		or not is_available_for_player(puddle.owner_slot)
		or upgrade_health <= 0.0001
	):
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
	_refresh_label()
	play_hit_feedback()


func play_hit_feedback() -> void:
	_hit_feedback_remaining = 0.12
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
	# 来源缩放只影响奖励数值，不在门牌上额外提示“小份”来源。
	_label.text = "%s\n%s\n%s" % [
		upgrade.display_name,
		upgrade.effect_text(display_maximum_durability),
		upgrade.rarity_name,
	]
	_label.modulate = Color.WHITE
	_health_label.text = str(ceili(upgrade_health))
	var panel_material: StandardMaterial3D = _panel_mesh.material_override as StandardMaterial3D
	panel_material.albedo_color = upgrade.rarity_color.darkened(0.22)


func _refresh_feedback() -> void:
	var material: StandardMaterial3D = _panel_mesh.material_override as StandardMaterial3D
	var enabled: bool = _hit_feedback_remaining > 0.0
	# 常驻 emission 材质变体，避免第一次命中掉落门时切换渲染分支。
	material.emission_enabled = true
	# 命中只提高同一稀有度色的亮度，避免房主与客机反馈时差看成品质颜色分叉。
	material.emission = upgrade.rarity_color if enabled and upgrade != null else Color.BLACK
	material.emission_energy_multiplier = 0.75 if enabled else 0.0
