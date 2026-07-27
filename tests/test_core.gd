extends SceneTree

var _failures: int = 0


func _init() -> void:
	_test_playfield()
	_test_customer_cart_collision()
	_test_3d_plane_rules()
	_test_3d_background_and_hud()
	_test_projectile_miss_disappear()
	_test_run_state()
	_test_weapon_fires_without_target()
	_test_upgrade_gate()
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
	_check(reward_health_label.text.to_int() == ceili(reward_gate.upgrade_health), "3D食客奖励门显示唯一可攻击血量")
	_check(not reward_health_back.visible and not reward_health_fill.visible, "3D食客奖励门不显示血量进度条")
	_check(reward_health_label.font_size >= 64, "3D食客奖励门使用显眼数字显示血量")
	var reward_panel: MeshInstance3D = reward_gate.get_node("Panel") as MeshInstance3D
	var reward_material: StandardMaterial3D = reward_panel.material_override as StandardMaterial3D
	var reward_color_before: Color = reward_material.albedo_color
	reward_gate.receive_damage(50.0)
	_check(not reward_material.albedo_color.is_equal_approx(reward_color_before), "3D食客奖励门升值跨稀有度后实时换色")
	reward_gate.free()
	run.free()
	customer.free()
	field.free()


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


func _test_run_state() -> void:
	var state: RunState = RunState.new()
	var potato: FoodData = load("res://data/foods/potato.tres") as FoodData
	var sugar: UpgradeData = UpgradeData.new()
	sugar.kind = UpgradeData.Kind.SUGAR
	sugar.value = 0.2
	state.apply_upgrade(sugar)
	_check(is_equal_approx(state.effective_satisfaction(potato), 12.0), "满足值按基础值加算")

	var quick_prep: UpgradeData = UpgradeData.new()
	quick_prep.kind = UpgradeData.Kind.QUICK_PREP
	quick_prep.value = 3.0
	state.apply_upgrade(quick_prep)
	_check(is_equal_approx(state.effective_interval(potato), RunState.MINIMUM_INTERVAL), "攻击间隔限制为每帧一次")
	quick_prep.value = 0.08
	_check(quick_prep.effect_text() == "间隔 -8%", "门使用简洁攻击间隔描述")

	var multiplicative_state: RunState = RunState.new()
	var half_more: UpgradeData = UpgradeData.new()
	half_more.kind = UpgradeData.Kind.SUGAR
	half_more.value = 0.5
	multiplicative_state.apply_upgrade(half_more)
	multiplicative_state.apply_upgrade(half_more, false)
	_check(
		is_equal_approx(multiplicative_state.effective_satisfaction(potato), 22.5),
		"两次满足值加成按1.5乘1.5累计"
	)
	var faster: UpgradeData = UpgradeData.new()
	faster.kind = UpgradeData.Kind.QUICK_PREP
	faster.value = 0.2
	multiplicative_state.apply_upgrade(faster)
	multiplicative_state.apply_upgrade(faster)
	_check(
		is_equal_approx(multiplicative_state.effective_interval(potato), potato.base_interval * 0.64),
		"两次间隔缩短按0.8乘0.8累计"
	)
	_check(multiplicative_state.dropped_upgrades == 1, "掉落百分比强化使用同一乘算链并单独计数")

	var sturdy: UpgradeData = UpgradeData.new()
	sturdy.kind = UpgradeData.Kind.STURDY_CART
	sturdy.value = 10.0
	state.apply_upgrade(sturdy)
	_check(is_equal_approx(state.maximum_durability, 110.0), "最大耐久提高")
	_check(is_equal_approx(state.current_durability, 110.0), "坚固餐车同步提高当前耐久")

	state.take_durability_damage(40.0)
	var repair: UpgradeData = UpgradeData.new()
	repair.kind = UpgradeData.Kind.REPAIR
	repair.value = 0.2
	state.apply_upgrade(repair)
	_check(is_equal_approx(state.current_durability, 92.0), "维修按最大耐久比例恢复")
	_check(repair.effect_text(state.maximum_durability) == "修复 +22点", "维修门显示简洁实际点数")
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
	run._build_drop_upgrades()
	var first_kinds: Dictionary = {}
	for seed_value: int in range(1, 17):
		run._upgrade_rng.seed = seed_value
		var reward: UpgradeData = run._roll_customer_reward()
		first_kinds[reward.kind] = true
	_check(first_kinds.size() > 1, "首个食客奖励类型由随机数抽取而非固定为糖")
	run.state = RunState.new()
	run._upgrade_rng.seed = 1701
	var special_choices: Array[StringName] = run._roll_special_choices()
	_check(special_choices.size() == 3, "特殊奖励池每次提供三个不同候选")
	_check(run._special_choice_pool.has(&"soy_sauce"), "酱油已进入特殊奖励候选池")
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
		"基准胃口曲线使用 Excel 终点和结束时间"
	)
	var midpoint_time: float = timeline.baseline_appetite_end_time * 0.5
	var expected_midpoint: float = roundf(lerpf(
		timeline.baseline_appetite_start,
		timeline.baseline_appetite_end,
		pow(0.5, timeline.baseline_appetite_exponent)
	))
	_check(
		is_equal_approx(timeline.baseline_appetite_at(midpoint_time), expected_midpoint),
		"基准胃口曲线使用 Excel 增长指数"
	)
	var gate_count: int = 0
	for event_text: String in timeline.event_ids:
		if event_text.begins_with("gate_"):
			gate_count += 1
	_check(gate_count == 12, "竖切片包含12道普通强化门")
	_check(timeline.event_ids.has("elite"), "时间轴包含精英")
	_check(timeline.event_ids.has("boss"), "时间轴包含Boss")
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
	var post_elite_gate_index: int = timeline.event_ids.find("gate_6")
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
	var elite: CustomerData = load("res://data/customers/elite_guest.tres") as CustomerData
	var boss: BossPatternData = load("res://data/bosses/prototype_boss.tres") as BossPatternData
	_check(potato != null and is_equal_approx(potato.base_satisfaction, 10.0), "土豆基线")
	_check(potato.initial_aim_mode == FoodData.AimMode.FIXED_FORWARD, "土豆初始固定竖直发射")
	_check(potato.initial_tracking_mode == FoodData.TrackingMode.NONE, "土豆初始为直线非追踪弹道")
	_check(baguette != null and baguette.pierce_count == 3, "法棍穿透数")
	_check(baguette.initial_tracking_mode == FoodData.TrackingMode.NONE, "法棍初始不追踪")
	_check(is_equal_approx(potato.projectile_speed * potato.base_lifetime / 1280.0, 0.8), "土豆基础持续约0.8屏")
	_check(is_equal_approx(baguette.projectile_speed * baguette.base_lifetime / 1280.0, 0.6), "法棍基础持续约0.6屏")
	_check(elite != null and elite.occupied_regions == 6, "精英横跨六区")
	_check(elite != null and is_equal_approx(elite.appetite_multiplier, 1.5), "精英默认使用1.5倍基准胃口")
	_check(boss != null and is_equal_approx(boss.appetite_at(100.0), 300.0), "Boss默认使用3倍基准胃口")
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
