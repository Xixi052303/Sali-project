extends SceneTree

var _failures: int = 0


func _init() -> void:
	_test_playfield()
	_test_customer_cart_collision()
	_test_3d_plane_rules()
	_test_baguette_targeting()
	_test_3d_background_and_hud()
	_test_projectile_miss_disappear()
	_test_projectile_evolutions()
	_test_run_state()
	_test_weapon_fires_without_target()
	_test_upgrade_gate()
	_test_start_food_selection()
	_test_customer_reward_gate()
	_test_reward_gate_spacing()
	_test_customer_reward_randomness()
	_test_timeline()
	_test_resources()
	if _failures == 0:
		print("CORE_TESTS_OK")
		quit(0)
	else:
		push_error("CORE_TESTS_FAILED count=%d" % _failures)
		quit(1)


func _test_playfield() -> void:
	var field: Playfield = Playfield.new()
	_check(field.region_at_x(0.6) == 0, "左边界属于第0区")
	_check(field.region_at_x(6.599) == 5, "右边界属于第5区")
	_check(is_equal_approx(field.region_center(2), 3.1), "区域中心计算")
	_check(is_equal_approx(field.clamp_cart_x(-1.0), 1.08), "餐车左边界")
	_check(is_equal_approx(field.clamp_cart_x(9.0), 6.12), "餐车右边界")
	_check(is_equal_approx(Playfield.design_to_world(360.0), 3.6), "设计像素只在3D入口换算为米")
	_check(
		field.forward_paths_are_separated(-6.4, 2.5, 0.0, 2.5),
		"同速前进对象保持初始安全距离"
	)
	_check(
		not field.forward_paths_are_separated(-3.0, 3.01, 0.0, 2.5),
		"会在抵达餐车前追尾的对象需要延迟生成"
	)
	field.free()


func _test_customer_cart_collision() -> void:
	var field: Playfield = Playfield.new()
	var state: RunState = RunState.new()
	var cart_scene: PackedScene = load("res://scenes/cart_3d.tscn") as PackedScene
	var customer_scene: PackedScene = load("res://scenes/customer_3d.tscn") as PackedScene
	var cart: Cart3D = cart_scene.instantiate() as Cart3D
	cart.position = Vector3(3.6, 0.0, Playfield.CART_Z)
	cart.scale = Vector3.ONE * 0.5
	cart.configure(state, field)
	var basic_data: CustomerData = load("res://data/customers/basic_guest.tres") as CustomerData
	var customer: Customer3D = customer_scene.instantiate() as Customer3D
	customer.configure(basic_data, null, 1, 32.0)
	var appetite_back: MeshInstance3D = customer.get_node("PaperCustomerVisual/AppetiteBack") as MeshInstance3D
	var appetite_fill: MeshInstance3D = customer.get_node("PaperCustomerVisual/AppetiteFill") as MeshInstance3D
	var appetite_label: Label3D = customer.get_node("PaperCustomerVisual/AppetiteLabel") as Label3D
	_check(not appetite_back.visible and not appetite_fill.visible, "3D食客不显示胃口进度条")
	_check(appetite_label.font_size >= 64, "3D食客使用显眼数字显示胃口")
	var cart_collision: Rect2 = cart.collision_rect_xz()
	_check(cart_collision.size.is_equal_approx(Vector2(0.96, 1.085)), "半尺寸餐车同步使用半尺寸碰撞矩形")
	customer.position = Vector3(1.6, 0.0, 9.5)
	_check(not customer.collision_rect_xz().intersects(cart.collision_rect_xz()), "食客纵向到达餐车但横向绕开时不算碰撞")
	customer.position = Vector3(3.6, 0.0, 9.5)
	_check(customer.collision_rect_xz().intersects(cart.collision_rect_xz()), "食客与餐车主体范围相交时算碰撞")
	customer.position = Vector3(1.6, 0.0, Playfield.CUSTOMER_DESPAWN_Z)
	_check(not customer.collision_rect_xz().intersects(cart.collision_rect_xz()), "绕开的食客到达道路后方时不算碰撞")
	cart.play_upgrade_feedback(Color.WHITE)
	_check(cart.scale.is_equal_approx(Vector3.ONE * 0.5), "餐车升级反馈保持编辑器配置的半尺寸基准")
	customer.free()
	cart.free()
	field.free()


# 3D版本直接在米制X/Z道路平面运行，六区边界不依赖场景根缩放。
func _test_3d_plane_rules() -> void:
	var field: Playfield = Playfield.new()
	var state: RunState = RunState.new()
	var run_scene: PackedScene = load("res://scenes/run_3d.tscn") as PackedScene
	var cart_scene: PackedScene = load("res://scenes/cart_3d.tscn") as PackedScene
	var customer_scene: PackedScene = load("res://scenes/customer_3d.tscn") as PackedScene
	var gate_scene: PackedScene = load("res://scenes/upgrade_gate_3d.tscn") as PackedScene
	var drop_scene: PackedScene = load("res://scenes/upgrade_drop_3d.tscn") as PackedScene
	var run_scene_instance: Node3D = run_scene.instantiate() as Node3D
	_check(run_scene_instance.scale.is_equal_approx(Vector3.ONE), "3D主场景根节点保持标准单位缩放")
	var scene_cart: Cart3D = run_scene_instance.get_node("Cart3D") as Cart3D
	_check(scene_cart != null, "3D主场景保留可编辑餐车节点")
	_check(scene_cart.scale.is_equal_approx(Vector3.ONE * 0.5), "3D主场景餐车长宽高均缩小为一半")
	var scene_debug_menu: DebugMenu = run_scene_instance.get_node("DebugMenu") as DebugMenu
	_check(scene_debug_menu != null, "3D主场景装配独立Debug菜单")
	run_scene_instance.free()
	var cart: Cart3D = cart_scene.instantiate() as Cart3D
	var editor_position: Vector3 = Vector3(2.75, 0.25, 12.25)
	cart.position = editor_position
	cart.scale = Vector3.ONE * 0.5
	cart.configure(state, field)
	_check(cart.position.is_equal_approx(editor_position), "餐车配置不会覆盖编辑器设置的初始位置")
	_check(is_equal_approx(cart.target_x, editor_position.x), "餐车横移目标从编辑器初始位置开始")
	cart.position = Vector3(3.6, 0.0, Playfield.CART_Z)
	_check(Playfield.FORWARD_SPAWN_Z <= -32.0, "前方生成点覆盖四段道路可见距离")
	cart._primary_touch_active = true
	cart._mouse_drag_active = true
	cart.cancel_pointer_input()
	_check(not cart._primary_touch_active and not cart._mouse_drag_active, "Debug菜单打开时结束餐车拖拽")
	var basic_data: CustomerData = load("res://data/customers/basic_guest.tres") as CustomerData
	var customer: Customer3D = customer_scene.instantiate() as Customer3D
	customer.configure(basic_data, null, 1, 32.0)
	customer.position = Vector3(1.6, 0.0, 9.5)
	_check(not customer.collision_rect_xz().intersects(cart.collision_rect_xz()), "3D食客横向绕开时不算碰撞")
	customer.position = Vector3(3.6, 0.0, 9.5)
	_check(customer.collision_rect_xz().intersects(cart.collision_rect_xz()), "3D食客在X/Z平面实际相交时碰撞")

	var run: RunController3D = RunController3D.new()
	var projectiles: Node3D = Node3D.new()
	var gates: Node3D = Node3D.new()
	var drops: Node3D = Node3D.new()
	var weapon: WeaponController3D = WeaponController3D.new()
	run.state = state
	run.playfield = field
	run.cart = cart
	run.projectiles = projectiles
	run.gates = gates
	run.drops = drops
	run.phase = RunController3D.Phase.FORWARD
	run.add_child(cart)
	run.add_child(projectiles)
	run.add_child(gates)
	run.add_child(drops)
	run.add_child(weapon)
	weapon.configure(run, cart, state)
	var potato: FoodData = load("res://data/foods/potato.tres") as FoodData
	weapon.add_food(potato)
	weapon._tick_food(weapon.foods[0], 0.0)
	_check(projectiles.get_child_count() == 1, "3D武器没有目标时仍朝道路前方发射")
	if projectiles.get_child_count() == 1:
		var projectile: FoodProjectile3D = projectiles.get_child(0) as FoodProjectile3D
		_check(projectile.velocity.z < 0.0 and is_zero_approx(projectile.velocity.y), "3D投射物只在X/Z玩法平面移动")

	var left_upgrade: UpgradeData = UpgradeData.new()
	left_upgrade.configure_value_range(0.05, 0.45, 0.1)
	var right_upgrade: UpgradeData = UpgradeData.new()
	right_upgrade.configure_value_range(0.05, 0.45, 0.8)
	var gate: UpgradeGate3D = gate_scene.instantiate() as UpgradeGate3D
	gate.configure(null, left_upgrade, right_upgrade, false, 100.0, 1)
	var left_health_label: Label3D = gate.get_node("LeftHealthLabel") as Label3D
	var left_health_back: MeshInstance3D = gate.get_node("LeftHealthBack") as MeshInstance3D
	var left_health_fill: MeshInstance3D = gate.get_node("LeftHealthFill") as MeshInstance3D
	var left_panel: MeshInstance3D = gate.get_node("LeftPanel") as MeshInstance3D
	var left_material: StandardMaterial3D = left_panel.material_override as StandardMaterial3D
	var gate_color_before: Color = left_material.albedo_color
	_check(left_health_label.text.to_int() == ceili(gate.left_base_health), "3D普通门在门板上方独立显示公开基础胃口")
	_check(not left_health_back.visible and not left_health_fill.visible, "3D普通门不显示胃口进度条")
	_check(left_health_label.font_size >= 64, "3D普通门使用显眼数字显示公开胃口")
	gate.receive_damage(true, gate.left_base_health)
	gate.receive_damage(true, 50.0)
	_check(left_health_label.text == "0", "3D门额外升值血量保持隐藏，公开数字归零后不再显示")
	_check(not left_material.albedo_color.is_equal_approx(gate_color_before), "3D普通门升值跨稀有度后实时换色")
	gate.free()

	var reward_upgrade: UpgradeData = UpgradeData.new()
	reward_upgrade.configure_value_range(0.05, 0.45, 0.1)
	var reward_gate: UpgradeDrop3D = drop_scene.instantiate() as UpgradeDrop3D
	reward_gate.configure(null, reward_upgrade, Vector3.ZERO, 100.0, 2, 1)
	var reward_health_label: Label3D = reward_gate.get_node("HealthLabel") as Label3D
	var reward_health_back: MeshInstance3D = reward_gate.get_node("HealthBack") as MeshInstance3D
	var reward_health_fill: MeshInstance3D = reward_gate.get_node("HealthFill") as MeshInstance3D
	_check(not reward_health_label.visible, "3D食客奖励门隐藏全部升值血量数字")
	_check(not reward_health_back.visible and not reward_health_fill.visible, "3D食客奖励门隐藏全部升值血量纸条")
	var reward_panel: MeshInstance3D = reward_gate.get_node("Panel") as MeshInstance3D
	var reward_material: StandardMaterial3D = reward_panel.material_override as StandardMaterial3D
	var reward_color_before: Color = reward_material.albedo_color
	reward_gate.receive_damage(50.0)
	_check(not reward_health_label.visible, "3D食客奖励门受击升值后仍不显示血量")
	_check(not reward_material.albedo_color.is_equal_approx(reward_color_before), "3D食客奖励门升值跨稀有度后实时换色")
	reward_gate.free()
	run.free()
	customer.free()
	field.free()


# 法棍先限制正前方90°扇区，再按餐车到目标的X/Z平面真实距离瞄准。
func _test_baguette_targeting() -> void:
	var run: RunController3D = RunController3D.new()
	var state: RunState = RunState.new()
	var cart: Cart3D = Cart3D.new()
	var projectiles: Node3D = Node3D.new()
	var gates: Node3D = Node3D.new()
	var drops: Node3D = Node3D.new()
	var weapon: WeaponController3D = WeaponController3D.new()
	run.state = state
	run.cart = cart
	run.projectiles = projectiles
	run.gates = gates
	run.drops = drops
	run.phase = RunController3D.Phase.FORWARD
	run.add_child(cart)
	run.add_child(projectiles)
	run.add_child(gates)
	run.add_child(drops)
	run.add_child(weapon)
	cart.position = Vector3(3.6, 0.0, 10.0)
	weapon.configure(run, cart, state)

	var baguette: FoodData = load("res://data/foods/baguette.tres") as FoodData
	var outside_but_closer: Customer3D = Customer3D.new()
	outside_but_closer.position = Vector3(4.3, 0.0, 9.5)
	outside_but_closer.active = true
	outside_but_closer.spawn_index = 1
	var nearest_in_cone: Customer3D = Customer3D.new()
	nearest_in_cone.position = Vector3(3.6, 0.0, 8.0)
	nearest_in_cone.active = true
	nearest_in_cone.spawn_index = 2
	var farther_in_cone: Customer3D = Customer3D.new()
	farther_in_cone.position = Vector3(3.6, 0.0, 7.0)
	farther_in_cone.active = true
	farther_in_cone.spawn_index = 3
	run.add_child(outside_but_closer)
	run.add_child(nearest_in_cone)
	run.add_child(farther_in_cone)
	run.customers = [outside_but_closer, nearest_in_cone, farther_in_cone]
	_check(run.get_priority_target() == outside_but_closer, "通用自动瞄准仍选择全平面最近单位")
	_check(
		run.get_priority_target_for_food(baguette) == nearest_in_cone,
		"法棍忽略前方90°之外的更近单位，并选择扇区内最近单位"
	)

	weapon.add_food(baguette)
	weapon._tick_food(weapon.foods[0], 0.0)
	_check(projectiles.get_child_count() == 1, "法棍存在目标时正常发射")
	if projectiles.get_child_count() == 1:
		var projectile: FoodProjectile3D = projectiles.get_child(0) as FoodProjectile3D
		_check(
			is_zero_approx(projectile.velocity.x) and projectile.velocity.z < 0.0,
			"法棍发射方向指向扇区内距离餐车最近的单位"
		)

	var left_boundary: Customer3D = Customer3D.new()
	left_boundary.position = Vector3(1.6, 0.0, 8.0)
	left_boundary.active = true
	left_boundary.spawn_index = 3
	var right_boundary: Customer3D = Customer3D.new()
	right_boundary.position = Vector3(5.6, 0.0, 8.0)
	right_boundary.active = true
	right_boundary.spawn_index = 4
	var just_outside: Customer3D = Customer3D.new()
	just_outside.position = Vector3(1.59, 0.0, 8.0)
	just_outside.active = true
	just_outside.spawn_index = 1
	var behind_cart: Customer3D = Customer3D.new()
	behind_cart.position = Vector3(3.6, 0.0, 12.0)
	behind_cart.active = true
	behind_cart.spawn_index = 0
	run.add_child(left_boundary)
	run.add_child(right_boundary)
	run.add_child(just_outside)
	run.add_child(behind_cart)
	run.customers = [just_outside, behind_cart, left_boundary, right_boundary]
	_check(
		run.get_priority_target_for_food(baguette) == left_boundary,
		"法棍计入北偏西45°边界，并排除边界外与后方单位"
	)
	left_boundary.active = false
	_check(
		run.get_priority_target_for_food(baguette) == right_boundary,
		"法棍计入北偏东45°边界"
	)
	run.free()


# 背景资源保持节点化装配，街景裁剪和尺寸都能直接在编辑器检查器中调整。
func _test_3d_background_and_hud() -> void:
	var background_scene: PackedScene = load("res://scenes/world_background_3d.tscn") as PackedScene
	var background: WorldBackground3D = background_scene.instantiate() as WorldBackground3D
	var camera: Camera3D = background.get_node("PaperCamera") as Camera3D
	var world_environment: WorldEnvironment = background.get_node("PaperEnvironment") as WorldEnvironment
	_check(is_equal_approx(camera.fov, 32.0) and camera.position.z >= 18.0, "固定相机采用参考图式远近透视构图")
	_check(camera.keep_aspect == Camera3D.KEEP_WIDTH, "长竖屏保持横向玩法区域和单位尺寸")
	_check(world_environment.environment.fog_enabled, "Mobile深度雾遮蔽远端生成区域")
	for index: int in range(6):
		_check(background.get_node_or_null("RoadSegment%d" % index) != null, "道路包含第%d个分层循环路段" % index)
	var street_props: Node3D = background.get_node("StreetProps") as Node3D
	_check(street_props.get_child_count() == 6, "街景面片集中在可编辑节点组")
	var road_segment: Node3D = background.get_node("RoadSegment3") as Node3D
	var road_surface: MeshInstance3D = road_segment.get_node("RoadSurface") as MeshInstance3D
	var left_curb: MeshInstance3D = road_segment.get_node("LeftCurb") as MeshInstance3D
	var left_sidewalk: MeshInstance3D = road_segment.get_node("LeftSidewalk") as MeshInstance3D
	var road_mesh: PlaneMesh = road_surface.mesh as PlaneMesh
	var curb_mesh: BoxMesh = left_curb.mesh as BoxMesh
	var sidewalk_mesh: BoxMesh = left_sidewalk.mesh as BoxMesh
	_check(road_mesh.size.is_equal_approx(Vector2(6.041834, 12.8)), "中央马路宽度按拆分贴图比例装配")
	_check(left_curb.position.y + curb_mesh.size.y * 0.5 > road_surface.position.y, "路沿顶面高于马路")
	_check(left_sidewalk.position.y + sidewalk_mesh.size.y * 0.5 > road_surface.position.y, "人行道顶面高于马路")
	for child: Node in street_props.get_children():
		var prop: Sprite3D = child as Sprite3D
		_check(prop != null and prop.region_enabled and prop.region_rect.size.x > 0.0, "%s使用节点自身裁剪区域" % child.name)
	background.free()

	var hud_scene: PackedScene = load("res://scenes/hud.tscn") as PackedScene
	var hud: GameHud = hud_scene.instantiate() as GameHud
	var durability_panel: PanelContainer = hud.get_node("Root/DurabilityPanel") as PanelContainer
	_check(durability_panel.anchor_top == 1.0, "餐车耐久固定在屏幕下方")
	_check(durability_panel.get_parent() == hud.get_node("Root"), "耐久条不再占用顶部信息布局")
	_check(hud.get_node_or_null("Root/ChoiceOverlay/ChoiceStack/ChoiceButtons") != null, "HUD固定结构可以在编辑器预览和调整")
	hud.free()


func _test_projectile_miss_disappear() -> void:
	var projectile_scene: PackedScene = load("res://scenes/projectile_3d.tscn") as PackedScene
	var projectile: FoodProjectile3D = projectile_scene.instantiate() as FoodProjectile3D
	get_root().add_child(projectile)
	projectile._begin_miss_disappear()
	_check(is_equal_approx(FoodProjectile3D.MISS_DISAPPEAR_DURATION, 0.2), "未命中退场持续0.2秒")
	_check(projectile.is_miss_disappearing(), "未命中食材进入0.2秒退场状态")
	_check(not projectile.is_processing(), "食材退场期间停止移动与碰撞")
	projectile.free()


func _test_projectile_evolutions() -> void:
	var projectile_scene: PackedScene = load("res://scenes/projectile_3d.tscn") as PackedScene
	var cart_scene: PackedScene = load("res://scenes/cart_3d.tscn") as PackedScene
	var run: RunController3D = RunController3D.new()
	var cart: Cart3D = cart_scene.instantiate() as Cart3D
	cart.position = Vector3(3.6, 0.0, Playfield.CART_Z)
	run.add_child(cart)
	run.cart = cart
	var projectiles: Node3D = Node3D.new()
	run.add_child(projectiles)
	run.projectiles = projectiles
	var state: RunState = RunState.new()
	run.state = state
	var baguette: FoodData = load("res://data/foods/baguette.tres") as FoodData
	var giant: FoodProjectile3D = projectile_scene.instantiate() as FoodProjectile3D
	run.add_child(giant)
	giant.configure(
		run,
		Vector3(3.6, 0.0, 5.0),
		Vector3.FORWARD,
		baguette,
		8.0,
		7.0,
		0.16,
		1.2,
		3,
		null,
		false,
		0.0,
		true,
		Playfield.REGION_WIDTH * 4.0,
		false
	)
	var target: Node3D = Node3D.new()
	target.position = Vector3(5.8, 0.0, 5.0)
	_check(giant.overlaps_target(target.position, 0.2), "巨型法棍使用横跨四格的道路平面判定")
	_check(not giant.overlaps_target(Vector3(6.8, 0.0, 5.0), 0.2), "巨型法棍不会命中四格宽度外目标")
	giant.register_hit(target)
	_check(not giant.can_hit(target), "巨型法棍单个实例对同一目标最多结算一次")
	target.free()
	giant.free()

	var aimed_baguette: FoodProjectile3D = projectile_scene.instantiate() as FoodProjectile3D
	run.add_child(aimed_baguette)
	aimed_baguette.configure(
		run,
		Vector3(3.6, 0.0, 5.0),
		Vector3(1.0, 0.0, -1.0),
		baguette,
		8.0,
		7.0,
		0.16,
		1.2,
		3,
		null,
		false,
		0.0,
		false,
		0.0,
		false
	)
	aimed_baguette._process_forward_motion(0.0)
	_check(aimed_baguette.rotation.y < 0.0, "法棍朝向右前目标时模型向右旋转")
	aimed_baguette.free()

	state.add_food(&"baguette")
	state.enable_food_evolution(&"baguette_giant")
	var weapon: WeaponController3D = WeaponController3D.new()
	run.add_child(weapon)
	weapon.configure(run, cart, state)
	weapon._tick_giant_baguette(baguette, 0.0)
	weapon._tick_giant_baguette(baguette, 2.9)
	_check(projectiles.get_child_count() == 0, "巨型法棍取得后等待完整三秒间隔")
	weapon._tick_giant_baguette(baguette, 0.1)
	_check(projectiles.get_child_count() == 1, "巨型法棍每三秒额外发射一根")
	var fired_giant: FoodProjectile3D = projectiles.get_child(0) as FoodProjectile3D
	_check(fired_giant._giant_baguette, "额外投射物标记为巨型法棍")
	_check(not fired_giant.homing_enabled, "巨型法棍不跟踪目标")
	_check(fired_giant.remaining_hits == 999, "巨型法棍读取999穿透配置")
	_check(is_equal_approx(fired_giant._initial_lifetime, state.effective_duration(baguette) * 1.5), "巨型法棍持续时间为法棍的1.5倍")
	_check(is_equal_approx(fired_giant.satisfaction, state.effective_satisfaction(baguette) * 3.0), "巨型法棍满足值为法棍的3倍")

	var potato: FoodData = load("res://data/foods/potato.tres") as FoodData
	var fast_projectile: FoodProjectile3D = projectile_scene.instantiate() as FoodProjectile3D
	run.add_child(fast_projectile)
	fast_projectile.configure(
		run,
		Vector3(3.6, 0.0, 10.0),
		Vector3.FORWARD,
		potato,
		10.0,
		30.0,
		0.17,
		2.0,
		1,
		null,
		false,
		0.0,
		false,
		0.0,
		false
	)
	fast_projectile._process_forward_motion(0.333)
	_check(
		fast_projectile.overlaps_target(Vector3(3.6, 0.0, 5.0), 0.2),
		"高弹速投射物使用上一位置到当前位置的连续线段防止穿透"
	)
	fast_projectile.free()

	var mushroom: FoodData = load("res://data/foods/mushroom.tres") as FoodData
	var orbit: FoodProjectile3D = projectile_scene.instantiate() as FoodProjectile3D
	run.add_child(orbit)
	orbit.configure(
		run,
		cart.position,
		Vector3.FORWARD,
		mushroom,
		7.0,
		mushroom.orbit_angular_speed,
		0.22,
		mushroom.base_lifetime,
		1,
		null,
		false,
		0.0,
		false,
		0.0,
		false
	)
	orbit._process_orbit(0.0)
	var turn_duration: float = TAU / mushroom.orbit_angular_speed
	_check(is_equal_approx(orbit.position.distance_to(cart.position), 1.2), "蘑菇从基础半径开始环绕")
	orbit._process_orbit(turn_duration)
	_check(is_equal_approx(orbit.position.distance_to(cart.position), 1.2), "蘑菇先在基础半径完整旋转一圈")
	orbit._process_orbit(turn_duration * 0.5)
	_check(is_equal_approx(orbit.position.distance_to(cart.position), 1.5), "扩张圈中点平滑到基础半径的1.25倍")
	orbit._process_orbit(turn_duration * 0.5)
	_check(is_equal_approx(orbit.position.distance_to(cart.position), 1.8), "扩张圈结束到达当前半径的1.5倍")
	orbit._process_orbit(turn_duration)
	_check(is_equal_approx(orbit.position.distance_to(cart.position), 1.8), "蘑菇在1.5倍半径处再次完整旋转一圈")
	orbit._process_orbit(turn_duration)
	_check(is_equal_approx(orbit.position.distance_to(cart.position), 2.7), "下一扩张圈继续到当前半径的1.5倍")

	var faster_orbit: FoodProjectile3D = projectile_scene.instantiate() as FoodProjectile3D
	run.add_child(faster_orbit)
	faster_orbit.configure(
		run,
		cart.position,
		Vector3.FORWARD,
		mushroom,
		7.0,
		mushroom.orbit_angular_speed * 1.5,
		0.22,
		mushroom.base_lifetime,
		1,
		null,
		false,
		0.0,
		false,
		0.0,
		false
	)
	faster_orbit._process_orbit(TAU * 1.5 / (mushroom.orbit_angular_speed * 1.5))
	_check(
		is_equal_approx(faster_orbit.position.distance_to(cart.position), 1.5),
		"酒只提高转速，相同累计转角仍使用相同分段半径"
	)

	var longer_orbit: FoodProjectile3D = projectile_scene.instantiate() as FoodProjectile3D
	run.add_child(longer_orbit)
	longer_orbit.configure(
		run,
		cart.position,
		Vector3.FORWARD,
		mushroom,
		7.0,
		mushroom.orbit_angular_speed,
		0.22,
		mushroom.base_lifetime * 1.5,
		1,
		null,
		false,
		0.0,
		false,
		0.0,
		false
	)
	_check(
		is_equal_approx(longer_orbit._initial_lifetime, mushroom.base_lifetime * 1.5)
		and is_equal_approx(longer_orbit._orbit_angular_speed, mushroom.orbit_angular_speed)
		and is_equal_approx(longer_orbit._orbit_base_radius, 1.2),
		"淀粉只延长蘑菇存续时间，不直接改变转速或分段半径"
	)

	var breathing_orbit: FoodProjectile3D = projectile_scene.instantiate() as FoodProjectile3D
	run.add_child(breathing_orbit)
	breathing_orbit.configure(
		run,
		cart.position,
		Vector3.FORWARD,
		mushroom,
		7.0,
		mushroom.orbit_angular_speed,
		0.22,
		mushroom.base_lifetime,
		1,
		null,
		false,
		0.0,
		false,
		0.0,
		true
	)
	breathing_orbit._lifetime_remaining = (
		breathing_orbit._initial_lifetime - mushroom.breathing_period * 0.5
	)
	breathing_orbit._process_orbit(0.0)
	_check(
		is_equal_approx(breathing_orbit.position.distance_to(cart.position), 2.4),
		"呼吸进化在当前分段半径上叠加周期倍率"
	)
	run.free()


func _test_run_state() -> void:
	var state: RunState = RunState.new()
	var potato: FoodData = load("res://data/foods/potato.tres") as FoodData
	state.add_food(&"potato")
	_check(state.food_level(&"potato") == 1, "首次取得食材时登记为Lv.1")
	var sugar: UpgradeData = UpgradeData.new()
	sugar.kind = UpgradeData.Kind.SUGAR
	sugar.value = 0.2
	state.apply_upgrade(sugar)
	_check(is_equal_approx(state.effective_satisfaction(potato), 12.0), "满足值按基础值加算")
	state.level_food(&"potato")
	_check(
		is_equal_approx(state.effective_satisfaction(potato), 30.0),
		"食材Lv.2的2.5倍自身倍率与全局倍率相乘"
	)
	state.level_food(&"potato")
	_check(state.food_level(&"potato") == 3, "食材等级最高为Lv.3")
	_check(not state.can_level_food(&"potato"), "满级食材不再进入升级候选")
	state.enable_food_evolution(&"potato_aim")
	_check(state.has_food_evolution(&"potato_aim"), "签名进化状态可独立记录")

	var quick_prep: UpgradeData = UpgradeData.new()
	quick_prep.kind = UpgradeData.Kind.QUICK_PREP
	quick_prep.value = 100.0
	state.apply_upgrade(quick_prep)
	_check(is_equal_approx(state.effective_interval(potato), RunState.MINIMUM_INTERVAL), "攻击间隔限制为每帧一次")
	quick_prep.value = 0.08
	_check(quick_prep.effect_text() == "攻速 +8%", "门使用正向攻击速度描述")

	var additive_state: RunState = RunState.new()
	var half_more: UpgradeData = UpgradeData.new()
	half_more.kind = UpgradeData.Kind.SUGAR
	half_more.value = 0.5
	additive_state.apply_upgrade(half_more)
	additive_state.apply_upgrade(half_more, false)
	_check(
		is_equal_approx(additive_state.effective_satisfaction(potato), 20.0),
		"两次满足值加成在线性倍率池内加算"
	)
	var faster: UpgradeData = UpgradeData.new()
	faster.kind = UpgradeData.Kind.QUICK_PREP
	faster.value = 0.2
	additive_state.apply_upgrade(faster)
	additive_state.apply_upgrade(faster)
	_check(
		is_equal_approx(additive_state.effective_interval(potato), potato.base_interval / 1.4),
		"两次攻速加成线性累计后反推攻击间隔"
	)
	_check(additive_state.dropped_upgrades == 1, "掉落百分比强化使用同一加算链并单独计数")

	var sturdy: UpgradeData = UpgradeData.new()
	sturdy.kind = UpgradeData.Kind.STURDY_CART
	sturdy.value = 10.0
	state.apply_upgrade(sturdy)
	_check(is_equal_approx(state.maximum_durability, 110.0), "最大耐久提高")
	_check(is_equal_approx(state.current_durability, 110.0), "餐车改造同步提高当前耐久")

	state.take_durability_damage(40.0)
	var repair: UpgradeData = UpgradeData.new()
	repair.kind = UpgradeData.Kind.REPAIR
	repair.value = 0.2
	state.apply_upgrade(repair)
	_check(is_equal_approx(state.current_durability, 92.0), "维修按最大耐久比例恢复")
	state.apply_upgrade(repair)
	_check(is_equal_approx(state.current_durability, 110.0), "紧急维修优先补满当前耐久")
	_check(is_equal_approx(state.temporary_shield, 4.0), "溢出维修完整转化为临时护盾")
	var damage_applied: float = state.take_durability_damage(10.0)
	_check(is_equal_approx(damage_applied, 10.0), "临时护盾与耐久共同承受一次伤害")
	_check(is_equal_approx(state.temporary_shield, 0.0), "受击优先消耗临时护盾")
	_check(is_equal_approx(state.current_durability, 104.0), "护盾耗尽后剩余伤害扣除耐久")
	_check(is_equal_approx(state.durability_lost, 46.0), "护盾吸收量不计入实际耐久损失")
	state.add_temporary_shield(100.0)
	_check(is_equal_approx(state.temporary_shield, 100.0), "Debug护盾入口直接增加临时护盾")
	_check(
		repair.effect_text(state.maximum_durability) == "恢复/护盾 +22点",
		"紧急维修门同时说明恢复与溢出护盾"
	)
	var previous_gate_count: int = state.gate_choices
	state.apply_upgrade(sugar, false)
	_check(state.gate_choices == previous_gate_count, "食客奖励门不计入普通双选门")
	_check(state.dropped_upgrades == 1, "食客奖励门单独计数")
	state.add_pierce_bonus()
	_check(state.effective_pierce_count(potato) == 2, "酱油让土豆额外命中一个目标")

	var distance_state: RunState = RunState.new()
	var wine: UpgradeData = UpgradeData.new()
	wine.kind = UpgradeData.Kind.WINE
	wine.value = 0.25
	distance_state.apply_upgrade(wine)
	var starch: UpgradeData = UpgradeData.new()
	starch.kind = UpgradeData.Kind.STARCH
	starch.value = 0.5
	distance_state.apply_upgrade(starch)
	_check(
		is_equal_approx(
			distance_state.effective_projectile_distance(potato),
			potato.projectile_speed * 1.25 * potato.base_lifetime * 1.5
		),
		"弹速与持续时间共同决定投射距离"
	)


func _test_weapon_fires_without_target() -> void:
	var run: RunController3D = RunController3D.new()
	var state: RunState = RunState.new()
	var field: Playfield = Playfield.new()
	var cart_scene: PackedScene = load("res://scenes/cart_3d.tscn") as PackedScene
	var cart: Cart3D = cart_scene.instantiate() as Cart3D
	cart.position = Vector3(3.6, 0.0, Playfield.CART_Z)
	cart.scale = Vector3.ONE * 0.5
	var projectiles: Node3D = Node3D.new()
	var gates: Node3D = Node3D.new()
	var drops: Node3D = Node3D.new()
	var weapon: WeaponController3D = WeaponController3D.new()
	run.state = state
	run.playfield = field
	run.cart = cart
	run.projectiles = projectiles
	run.gates = gates
	run.drops = drops
	run.add_child(field)
	run.add_child(cart)
	run.add_child(projectiles)
	run.add_child(gates)
	run.add_child(drops)
	run.add_child(weapon)
	cart.configure(state, field)
	weapon.configure(run, cart, state)
	var potato: FoodData = load("res://data/foods/potato.tres") as FoodData
	weapon.add_food(potato)
	weapon._tick_food(weapon.foods[0], 0.0)
	_check(projectiles.get_child_count() == 1, "没有目标时食材仍按冷却朝前发射")
	run.free()


func _test_upgrade_gate() -> void:
	var left: UpgradeData = UpgradeData.new()
	left.kind = UpgradeData.Kind.SUGAR
	left.configure_value_range(0.05, 0.45, 0.34)
	var right: UpgradeData = UpgradeData.new()
	right.kind = UpgradeData.Kind.WINE
	right.configure_value_range(0.10, 0.50, 0.80)
	var gate_scene: PackedScene = load("res://scenes/upgrade_gate_3d.tscn") as PackedScene
	var gate: UpgradeGate3D = gate_scene.instantiate() as UpgradeGate3D
	gate.configure(null, left, right, false, 100.0, 1)
	_check(is_equal_approx(gate.position.z, Playfield.FORWARD_SPAWN_Z), "普通门从四段道路的远端生成")
	_check(is_equal_approx(gate.travel_speed(), 2.5), "道路延长不改变普通门接近速度")
	_check(is_equal_approx(gate.left_base_health, 134.0), "左门基础血量按1加百分位乘基准胃口")
	_check(is_equal_approx(gate.right_base_health, 180.0), "稀有门拥有更高基础血量与撞门风险")
	_check(is_equal_approx(gate.left_upgrade_health, 66.0), "34%门的隐藏升值血量为基准胃口的66%")
	_check(is_equal_approx(gate.right_upgrade_health, 20.0), "左右门使用各自抽取百分位计算隐藏血量")
	gate.receive_damage(true, 134.0)
	_check(is_zero_approx(gate.left_base_health), "攻击先击破门的公开基础血量")
	_check(is_equal_approx(left.value_ratio, 0.34), "击破基础层的攻击不会溢出到隐藏升值层")
	gate.receive_damage(true, 33.0)
	_check(is_equal_approx(left.value_ratio, 0.67), "打掉一半隐藏升值血量后百分位由34%提升到67%")
	_check(is_equal_approx(left.value, lerpf(0.05, 0.45, 0.67)), "门奖励随受击百分位实时映射")
	_check(is_equal_approx(gate.right_base_health, 180.0), "攻击左门不会改变右门基础血量")
	_check(is_equal_approx(gate.right_upgrade_health, 20.0), "攻击左门不会改变右门隐藏血量")
	gate.receive_damage(true, 100.0)
	_check(left.is_at_maximum() and not gate.side_is_attackable(true), "门打空后达到区间上限并停止锁定")
	_check(gate.selected_upgrade_for_x(3.599) == left, "中心线左侧只选择左门")
	_check(gate.selected_upgrade_for_x(3.6) == right, "中心点固定只选择右门")
	_check(gate.selected_base_health_for_x(3.6) == gate.right_base_health, "中心点只结算右门碰撞损伤")
	gate.free()

	var start_gate: UpgradeGate3D = gate_scene.instantiate() as UpgradeGate3D
	start_gate.configure(null, left, right, true, 100.0, 2)
	_check(not start_gate.side_is_attackable(true), "开局食材门不可攻击")
	_check(start_gate.target_for_cart_x(2.0) == null, "开局食材门不进入自动目标池")
	start_gate.free()


func _test_start_food_selection() -> void:
	var run_scene: PackedScene = load("res://scenes/run_3d.tscn") as PackedScene
	var run: RunController3D = run_scene.instantiate() as RunController3D
	var unlocked: Array[FoodData] = run._available_start_foods()
	_check(unlocked.size() == 3, "当前原型默认解锁全部三种食材")
	run._upgrade_rng.seed = 20260728
	var options: Array[UpgradeData] = run._roll_start_food_options()
	_check(options.size() == 2, "开局食材门生成两个候选")
	_check(options[0].id != options[1].id, "多种已解锁食材中无放回抽取开局候选")
	var unlocked_ids: Array[StringName] = []
	for food: FoodData in unlocked:
		unlocked_ids.append(food.id)
	_check(
		unlocked_ids.has(options[0].id) and unlocked_ids.has(options[1].id),
		"开局候选只来自已解锁食材"
	)
	run.unlocked_foods = [run.mushroom_data]
	var single_food_options: Array[UpgradeData] = run._roll_start_food_options()
	_check(
		single_food_options.size() == 2
		and single_food_options[0].id == &"mushroom"
		and single_food_options[1].id == &"mushroom",
		"仅解锁一种食材时两侧都提供该食材"
	)
	run.free()


func _test_customer_reward_gate() -> void:
	var reward: UpgradeData = UpgradeData.new()
	reward.kind = UpgradeData.Kind.SUGAR
	reward.configure_value_range(0.05, 0.45, 0.34)
	var basic: CustomerData = load("res://data/customers/basic_guest.tres") as CustomerData
	var elite: CustomerData = load("res://data/customers/elite_guest.tres") as CustomerData
	_check(is_equal_approx(basic.appetite_at(100.0, 0.34), 134.0), "普通食客胃口按奖励百分位提高")
	_check(is_equal_approx(elite.appetite_at(32.0), 48.0), "精英只使用1.5倍基准且不参与随机稀有度")
	var reward_scene: PackedScene = load("res://scenes/upgrade_drop_3d.tscn") as PackedScene
	var reward_gate: UpgradeDrop3D = reward_scene.instantiate() as UpgradeDrop3D
	reward_gate.configure(null, reward, Vector3(1.6, 0.0, 4.0), 100.0, 2, 3)
	_check(is_equal_approx(reward_gate.upgrade_health, 66.0), "食客奖励门没有基础层并按百分位建立升值血量")
	_check(reward_gate.contains_cart_x(1.6), "餐车经过食客原占地区域可以领取奖励门")
	_check(not reward_gate.contains_cart_x(3.6), "餐车绕开奖励门时不能领取")
	reward_gate.receive_damage(33.0)
	_check(is_equal_approx(reward.value_ratio, 0.67), "攻击奖励门继续提高同一份奖励")
	reward_gate.free()


func _test_reward_gate_spacing() -> void:
	var run: RunController3D = RunController3D.new()
	var field: Playfield = Playfield.new()
	var gates: Node3D = Node3D.new()
	var drops: Node3D = Node3D.new()
	run.playfield = field
	run.gates = gates
	run.drops = drops
	run.add_child(field)
	run.add_child(gates)
	run.add_child(drops)
	var gate_scene: PackedScene = load("res://scenes/upgrade_gate_3d.tscn") as PackedScene
	var reward_scene: PackedScene = load("res://scenes/upgrade_drop_3d.tscn") as PackedScene
	var gate: UpgradeGate3D = gate_scene.instantiate() as UpgradeGate3D
	gate.position.z = 4.0
	gates.add_child(gate)
	var existing_drop: UpgradeDrop3D = reward_scene.instantiate() as UpgradeDrop3D
	existing_drop.position.z = 6.5
	drops.add_child(existing_drop)
	var safe_z: float = run._find_reward_gate_spawn_z(5.0)
	_check(
		field.forward_paths_are_separated(safe_z, 2.5, gate.position.z, gate.travel_speed(), Playfield.FORWARD_MIN_CENTER_DISTANCE),
		"新奖励门不会与原普通门重叠或追尾"
	)
	_check(
		field.forward_paths_are_separated(safe_z, 2.5, existing_drop.position.z, existing_drop.travel_speed(), Playfield.FORWARD_MIN_CENTER_DISTANCE),
		"食客奖励门之间不会重叠或追尾"
	)
	_check(absf(safe_z - 5.0) <= 4.001, "奖励门只在食客原位置附近小范围避让")
	run.free()


func _test_customer_reward_randomness() -> void:
	var run: RunController3D = RunController3D.new()
	run._build_prototype_upgrades()
	var pool_ids: Dictionary[StringName, bool] = {}
	for template: UpgradeData in run._normal_upgrade_pool:
		pool_ids[template.id] = true
	var gate_options: Array[UpgradeData] = run._roll_normal_upgrade_options(2)
	_check(gate_options.size() == 2, "普通门从共用池抽出两个候选")
	_check(gate_options[0].id != gate_options[1].id, "普通门同次抽选无放回")
	var first_kinds: Dictionary = {}
	for seed_value: int in range(1, 17):
		run._upgrade_rng.seed = seed_value
		var reward: UpgradeData = run._roll_customer_reward()
		first_kinds[reward.kind] = true
		_check(pool_ids.has(reward.id), "食客奖励候选来自普通强化共用池")
	_check(first_kinds.size() > 1, "首个食客奖励类型由随机数抽取而非固定为糖")
	run.state = RunState.new()
	run._upgrade_rng.seed = 1701
	var special_choices: Array[StringName] = run._roll_special_choices()
	_check(special_choices.size() == 3, "特殊奖励池每次提供三个不同候选")
	_check(
		special_choices[0] != special_choices[1]
		and special_choices[0] != special_choices[2]
		and special_choices[1] != special_choices[2],
		"特殊奖励同一次三选一不重复"
	)
	for choice_id: StringName in special_choices:
		_check(run._special_choice_is_valid(choice_id), "未持有进化不会混入有效候选")
	_check(run._special_choice_pool.size() == 8, "特殊奖励池包含三食材、三进化与两项全局牌")
	_check(run._special_choice_pool.has(&"soy_sauce"), "酱油已进入特殊奖励候选池")
	_check(not run._special_choice_is_valid(&"mushroom_breath"), "蘑菇进化在取得蘑菇前无效")
	run.state.add_food(&"mushroom")
	_check(run._special_choice_is_valid(&"mushroom_breath"), "取得蘑菇后呼吸扩圈进入有效池")
	run.state.enable_food_evolution(&"mushroom_breath")
	_check(not run._special_choice_is_valid(&"mushroom_breath"), "已取得进化会移出有效池")
	run.state.level_food(&"mushroom")
	run.state.level_food(&"mushroom")
	_check(not run._special_choice_is_valid(&"mushroom"), "满级食材卡会移出有效池")
	run.free()


func _test_timeline() -> void:
	var fallback: EncounterTimeline = load("res://data/timelines/vertical_slice.tres") as EncounterTimeline
	var load_result: TimelineExcelLoader.LoadResult = TimelineExcelLoader.load_from_excel(
		"res://balance_tables/时间轴.xlsx",
		fallback
	)
	_check(load_result.loaded_from_excel, "时间轴直接读取 Excel 数值主表")
	var timeline: EncounterTimeline = load_result.timeline
	_check(timeline != null and timeline.is_valid(), "时间轴事件数量一致")
	if timeline == null:
		return
	_check(
		is_equal_approx(timeline.baseline_appetite_at(0.0), roundf(timeline.baseline_appetite_start)),
		"基准胃口曲线使用 Excel 起点"
	)
	_check(
		is_equal_approx(
			timeline.baseline_appetite_at(timeline.baseline_appetite_end_time),
			roundf(timeline.baseline_appetite_end)
		),
		"前段基准胃口曲线使用 Excel 终点和结束时间"
	)
	var midpoint_time: float = timeline.baseline_appetite_end_time * 0.5
	var expected_midpoint: float = roundf(lerpf(
		timeline.baseline_appetite_start,
		timeline.baseline_appetite_end,
		pow(0.5, timeline.baseline_appetite_exponent)
	))
	_check(
		is_equal_approx(timeline.baseline_appetite_at(midpoint_time), expected_midpoint),
		"前段基准胃口曲线使用 Excel 增长指数"
	)
	_check(
		is_equal_approx(
			timeline.baseline_appetite_at(timeline.baseline_appetite_end_time - 0.001),
			timeline.baseline_appetite_at(timeline.baseline_appetite_end_time + 0.001)
		),
		"两段胃口曲线在135秒交界连续"
	)
	for checkpoint: Dictionary in [
		{"time": 180.0, "appetite": 554.0},
		{"time": 210.0, "appetite": 746.0},
		{"time": 270.0, "appetite": 1200.0},
		{"time": 300.0, "appetite": 1200.0},
	]:
		var checkpoint_time: float = float(checkpoint["time"])
		var checkpoint_appetite: float = float(checkpoint["appetite"])
		_check(
			is_equal_approx(
				timeline.baseline_appetite_at(checkpoint_time),
				checkpoint_appetite
			),
			"%.0f秒基准胃口保持计划值%.0f" % [
				checkpoint_time,
				checkpoint_appetite,
			]
		)
	_check(
		is_equal_approx(timeline.normal_wave_interval_at(77.999), 3.2)
		and is_equal_approx(timeline.normal_wave_interval_at(78.0), 2.8),
		"78秒普通波次阶段边界"
	)
	_check(
		is_equal_approx(timeline.normal_wave_interval_at(134.999), 2.8)
		and is_equal_approx(timeline.normal_wave_interval_at(135.0), 3.2),
		"135秒普通波次阶段边界"
	)
	var gate_count: int = 0
	var elite_count: int = 0
	for event_text: String in timeline.event_ids:
		if event_text.begins_with("gate_"):
			gate_count += 1
		elif event_text == "elite":
			elite_count += 1
	_check(gate_count == 24, "构筑验证切片包含24道普通强化门")
	_check(elite_count == 3, "时间轴包含3次精英检查")
	_check(timeline.event_ids.has("boss"), "时间轴包含Boss")
	_check(timeline.event_ids.find("gate_20") > timeline.event_ids.find("boss"), "Boss后保留4道复跑门")
	_check(timeline.event_times.size() == 29, "时间轴仍保留29条显式事件")
	var boss_index: int = timeline.event_ids.find("boss")
	_check(
		boss_index >= 0 and is_equal_approx(timeline.event_times[boss_index], 270.0),
		"Boss请求时间仍为270秒"
	)
	var run: RunController3D = RunController3D.new()
	run.basic_guest_data = load("res://data/customers/basic_guest.tres") as CustomerData
	run.fast_guest_data = load("res://data/customers/fast_guest.tres") as CustomerData
	run.ranged_guest_data = load("res://data/customers/ranged_guest.tres") as CustomerData
	_check(run._customer_spawn_lead_seconds(run.basic_guest_data) > 10.0, "普通食客按新增可见路程提前生成")
	_check(is_equal_approx(run._timeline_event_lead_seconds(&"gate_0"), 14.8), "普通门按原速度补偿新增路程和排队等待")
	var scene_cart: Cart3D = Cart3D.new()
	scene_cart.position.z = Playfield.CART_Z + 2.5
	run.add_child(scene_cart)
	run.cart = scene_cart
	_check(is_equal_approx(run._timeline_event_lead_seconds(&"gate_0"), 15.8), "编辑器餐车位置同步调整普通门提前量")
	run.free()
	var post_elite_gate_index: int = timeline.event_ids.find("gate_4")
	var elite_index: int = timeline.event_ids.find("elite")
	_check(
		post_elite_gate_index > elite_index
		and timeline.event_times[post_elite_gate_index] >= timeline.event_times[elite_index],
		"精英后首门保持在精英事件之后"
	)
	var missing_result: TimelineExcelLoader.LoadResult = TimelineExcelLoader.load_from_excel(
		"res://balance_tables/__missing__.xlsx",
		fallback
	)
	_check(missing_result.used_fallback and missing_result.timeline == fallback, "Excel 缺失时使用 .tres 回退")


func _test_resources() -> void:
	var potato: FoodData = load("res://data/foods/potato.tres") as FoodData
	var baguette: FoodData = load("res://data/foods/baguette.tres") as FoodData
	var mushroom: FoodData = load("res://data/foods/mushroom.tres") as FoodData
	var basic: CustomerData = load("res://data/customers/basic_guest.tres") as CustomerData
	var fast: CustomerData = load("res://data/customers/fast_guest.tres") as CustomerData
	var ranged: CustomerData = load("res://data/customers/ranged_guest.tres") as CustomerData
	var elite: CustomerData = load("res://data/customers/elite_guest.tres") as CustomerData
	var boss: BossPatternData = load("res://data/bosses/prototype_boss.tres") as BossPatternData
	_check(potato != null and is_equal_approx(potato.base_satisfaction, 10.0), "土豆基线")
	_check(potato.initial_aim_mode == FoodData.AimMode.FIXED_FORWARD, "土豆初始固定竖直发射")
	_check(potato.initial_tracking_mode == FoodData.TrackingMode.NONE, "土豆初始为直线非追踪弹道")
	_check(baguette != null and baguette.pierce_count == 2, "法棍默认额外穿透一个目标")
	_check(baguette.initial_tracking_mode == FoodData.TrackingMode.NONE, "法棍初始不追踪")
	_check(
		mushroom != null
		and mushroom.attack_kind == FoodData.AttackKind.ORBITING_MUSHROOM,
		"蘑菇使用环绕攻击类型"
	)
	_check(is_equal_approx(mushroom.breathing_period, 1.2), "蘑菇呼吸扩圈固定为1.2秒周期")
	_check(is_equal_approx(mushroom.breathing_outer_multiplier, 2.0), "蘑菇呼吸扩圈外沿为两倍基础半径")
	_check(is_equal_approx(potato.projectile_speed * potato.base_lifetime / 1280.0, 0.8), "土豆基础持续约0.8屏")
	_check(is_equal_approx(baguette.projectile_speed * baguette.base_lifetime / 1280.0, 0.6), "法棍基础持续约0.6屏")
	_check(
		basic.category == CustomerData.Category.NORMAL
		and basic.behavior == CustomerData.Behavior.NONE
		and basic.display_name == "小鼠食客"
		and basic.customer_scene != null,
		"基础食客回退资源使用可预览小鼠场景与无行为"
	)
	_check(
		fast.category == CustomerData.Category.NORMAL
		and fast.behavior == CustomerData.Behavior.NONE
		and fast.customer_scene != null,
		"急脚狐狸使用独立场景且只通过属性形成行为差异"
	)
	_check(
		ranged.category == CustomerData.Category.NORMAL
		and ranged.behavior == CustomerData.Behavior.RANGED
		and ranged.customer_scene != null,
		"拍桌青蛙回退资源使用独立场景与远程行为"
	)
	_check(elite != null and elite.occupied_regions == 6, "精英横跨六区")
	_check(elite != null and elite.category == CustomerData.Category.ELITE, "精英身份独立于行为类型")
	_check(elite != null and is_equal_approx(elite.appetite_multiplier, 1.5), "精英默认使用1.5倍基准胃口")
	_check(elite != null and elite.customer_scene != null, "精英回退资源使用独立可预览场景")
	var basic_scene_instance: Customer3D = basic.customer_scene.instantiate() as Customer3D
	var basic_model_root: Node3D = basic_scene_instance.get_node("PaperCustomerVisual/ModelRoot") as Node3D
	_check(basic_model_root.get_child_count() == 1, "小鼠模型已静态装配在食客场景中")
	basic_scene_instance.free()
	var elite_scene_instance: Customer3D = elite.customer_scene.instantiate() as Customer3D
	var elite_shadow: MeshInstance3D = elite_scene_instance.get_node(
		"PaperCustomerVisual/ContactShadow"
	) as MeshInstance3D
	_check(is_equal_approx(elite_shadow.scale.x, 5.82), "精英场景直接保存六区阴影宽度")
	elite_shadow.scale.x = 6.1
	elite_scene_instance.configure(elite, null, 1, 100.0)
	_check(is_equal_approx(elite_shadow.scale.x, 6.1), "食客配置不覆盖编辑器阴影宽度")
	elite_scene_instance.free()
	_check(
		basic.spawn_pattern_offset() == 0
		and fast.spawn_pattern_offset() == 1
		and ranged.spawn_pattern_offset() == 2
		and elite.spawn_pattern_offset() == 3,
		"四类食客保持原有生成错位序列"
	)
	_check(boss != null and is_equal_approx(boss.appetite_at(100.0), 300.0), "Boss默认使用3倍基准胃口")
	var boss_scene: PackedScene = load("res://scenes/boss_3d.tscn") as PackedScene
	var boss_instance: PrototypeBoss3D = boss_scene.instantiate() as PrototypeBoss3D
	var boss_body: MeshInstance3D = boss_instance.get_node("Body") as MeshInstance3D
	var boss_head: MeshInstance3D = boss_instance.get_node("Head") as MeshInstance3D
	_check(boss_body.visible and boss_head.visible, "Boss占位视觉已静态装配在可预览场景中")
	var boss_material: StandardMaterial3D = boss_body.material_override as StandardMaterial3D
	boss_material.albedo_color = Color.MAGENTA
	var boss_run: RunController3D = RunController3D.new()
	var boss_cart: Cart3D = Cart3D.new()
	boss_cart.position.z = 14.95819
	boss_run.cart = boss_cart
	boss_instance.configure(boss, boss_run, 100.0)
	_check(boss_material.albedo_color == Color.MAGENTA, "Boss配置不覆盖编辑器材质颜色")
	_check(
		is_equal_approx(
			boss_instance.position.z + PrototypeBoss3D.ENTRY_TRAVEL_DISTANCE,
			boss_cart.position.z - PrototypeBoss3D.COMBAT_DISTANCE_FROM_CART
		),
		"Boss战位随餐车纵坐标调整并保持基础食材可达"
	)
	boss_instance.free()
	boss_cart.free()
	boss_run.free()
	var state: RunState = RunState.new()
	_check(not state.is_food_target_aimed(&"potato"), "特殊强化前土豆不跟随目标角度")
	state.enable_target_aim(&"potato")
	_check(state.is_food_target_aimed(&"potato"), "特殊强化可以开启发射角度瞄准")
	_check(not state.is_food_homing(&"potato"), "特殊强化前土豆不追踪")
	state.enable_homing(&"potato")
	_check(state.is_food_homing(&"potato"), "特殊强化可以为指定食材开启追踪")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("TEST FAILED: %s" % message)
