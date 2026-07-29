extends SceneTree

var _failures: int = 0


func _init() -> void:
	_test_playfield()
	_test_customer_cart_collision()
	_test_progression_store()
	_test_cart_invincibility_duration()
	_test_3d_plane_rules()
	_test_baguette_targeting()
	_test_3d_background_and_hud()
	_test_projectile_miss_disappear()
	_test_projectile_evolutions()
	_test_run_state()
	_test_damage_camera_shake_rules()
	_test_weapon_fires_without_target()
	_test_upgrade_gate()
	_test_start_food_selection()
	_test_customer_reward_gate()
	_test_reward_gate_spacing()
	_test_customer_reward_randomness()
	_test_timeline()
	_test_seeded_spawn_randomness()
	_test_pressure_rules()
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
	var customer_scene: PackedScene = load(
		"res://scenes/characters/customers/customer_base_3d.tscn"
	) as PackedScene
	var cart: Cart3D = cart_scene.instantiate() as Cart3D
	cart.position = Vector3(3.6, 0.0, Playfield.CART_Z)
	cart.scale = Vector3.ONE * 0.5
	cart.configure(state, field)
	var basic_data: CustomerData = load("res://data/customers/basic_guest.tres") as CustomerData
	var reward_upgrade: UpgradeData = UpgradeData.new()
	reward_upgrade.configure_value_range(0.05, 0.45, 0.6)
	var customer: Customer3D = customer_scene.instantiate() as Customer3D
	customer.configure(basic_data, null, 1, 32.0, reward_upgrade)
	var appetite_back: MeshInstance3D = customer.get_node("PaperCustomerVisual/AppetiteBack") as MeshInstance3D
	var appetite_fill: MeshInstance3D = customer.get_node("PaperCustomerVisual/AppetiteFill") as MeshInstance3D
	var appetite_label: Label3D = customer.get_node("PaperCustomerVisual/AppetiteLabel") as Label3D
	_check(not appetite_back.visible and not appetite_fill.visible, "3D食客不显示胃口进度条")
	_check(appetite_label.font_size >= 64, "3D食客使用显眼数字显示胃口")
	_check(
		appetite_label.modulate.is_equal_approx(reward_upgrade.rarity_color),
		"3D普通食客的胃口数字使用其奖励稀有度色"
	)
	var cart_collision: Rect2 = cart.collision_rect_xz()
	_check(cart_collision.size.is_equal_approx(Vector2(0.96, 1.085)), "半尺寸餐车同步使用半尺寸碰撞矩形")
	customer.position = Vector3(1.6, 0.0, 9.5)
	_check(not customer.collision_rect_xz().intersects(cart.collision_rect_xz()), "食客纵向到达餐车但横向绕开时不算碰撞")
	customer.position = Vector3(3.6, 0.0, 9.5)
	_check(customer.collision_rect_xz().intersects(cart.collision_rect_xz()), "食客与餐车主体范围相交时算碰撞")
	customer.position = Vector3(1.6, 0.0, Playfield.CUSTOMER_DESPAWN_Z)
	_check(not customer.collision_rect_xz().intersects(cart.collision_rect_xz()), "绕开的食客到达道路后方时不算碰撞")
	var run: RunController3D = RunController3D.new()
	run.cart = cart
	customer.position = Vector3(3.6, 0.0, Playfield.CART_Z + 2.0)
	_check(
		run.customer_swept_collides_with_cart(customer, Playfield.CART_Z - 2.0),
		"高压阶段跨帧越过餐车时仍连续结算接触"
	)
	cart.play_upgrade_feedback(Color.WHITE)
	_check(cart.scale.is_equal_approx(Vector3.ONE * 0.5), "餐车升级反馈保持编辑器配置的半尺寸基准")
	customer.free()
	cart.free()
	field.free()
	run.free()


func _test_progression_store() -> void:
	var test_path: String = "user://test_progression_store.cfg"
	var absolute_path: String = ProjectSettings.globalize_path(test_path)
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(absolute_path)
	var first_result: int = ProgressionStore.record_final_boss_first_clear(test_path)
	var repeated_result: int = ProgressionStore.record_final_boss_first_clear(test_path)
	_check(
		first_result == ProgressionStore.UnlockResult.UNLOCKED_NOW,
		"最终Boss首次通关会建立后续内容解锁记录"
	)
	_check(
		repeated_result == ProgressionStore.UnlockResult.ALREADY_UNLOCKED,
		"最终Boss重复通关会识别既有解锁记录"
	)
	var config: ConfigFile = ConfigFile.new()
	var load_error: Error = config.load(test_path)
	_check(
		load_error == OK
		and bool(config.get_value(
			ProgressionStore.CONTENT_UNLOCKS_SECTION,
			ProgressionStore.FINAL_BOSS_FIRST_CLEAR_KEY,
			false
		)),
		"最终Boss首胜状态以持久化布尔值保存"
	)
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(absolute_path)


func _test_cart_invincibility_duration() -> void:
	var field: Playfield = Playfield.new()
	var state: RunState = RunState.new()
	var cart_scene: PackedScene = load("res://scenes/cart_3d.tscn") as PackedScene
	var cart: Cart3D = cart_scene.instantiate() as Cart3D
	get_root().add_child(cart)
	cart.configure(state, field, 0.5)
	_check(cart.take_damage(10.0), "餐车首次受击正常结算")
	_check(not cart.take_damage(10.0), "餐车在无敌时间内忽略重复伤害")
	cart._physics_process(0.49)
	_check(not cart.take_damage(10.0), "0.49秒时餐车仍处于无敌状态")
	cart._physics_process(0.02)
	_check(cart.take_damage(10.0), "0.5秒后餐车可以再次受击")
	cart.queue_free()
	field.free()


# 3D版本直接在米制X/Z道路平面运行，六区边界不依赖场景根缩放。
func _test_3d_plane_rules() -> void:
	var field: Playfield = Playfield.new()
	var state: RunState = RunState.new()
	var run_scene: PackedScene = load("res://scenes/run_3d.tscn") as PackedScene
	var cart_scene: PackedScene = load("res://scenes/cart_3d.tscn") as PackedScene
	var customer_scene: PackedScene = load(
		"res://scenes/characters/customers/customer_base_3d.tscn"
	) as PackedScene
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
	cart._visual_root = cart.get_node("PaperCartVisual") as Node3D
	_check(cart.position.is_equal_approx(editor_position), "餐车配置不会覆盖编辑器设置的初始位置")
	_check(is_equal_approx(cart.target_x, editor_position.x), "餐车横移目标从编辑器初始位置开始")
	_check(is_equal_approx(cart.target_z, editor_position.z), "餐车纵移目标从编辑器初始位置开始")
	var movement_boss: PrototypeBoss3D = PrototypeBoss3D.new()
	movement_boss.position = Vector3(3.6, 0.0, 6.0)
	cart.begin_boss_movement(movement_boss)
	var boss_boundary_z: float = cart.boss_minimum_z()
	_check(boss_boundary_z > movement_boss.position.z, "Boss纵向边界在Boss与餐车主体之间保留间距")
	cart.position = Vector3(3.6, 0.25, 12.25)
	cart.target_x = 6.0
	cart.target_z = 9.85
	cart._physics_process(0.1)
	_check(
		is_equal_approx(Vector2(cart.position.x - 3.6, cart.position.z - 12.25).length(), 0.9),
		"Boss战斜向移动与原横移使用相同合速度"
	)
	cart.position.z = boss_boundary_z - 1.0
	cart.target_z = movement_boss.position.z - 2.0
	cart._physics_process(0.1)
	_check(cart.position.z >= boss_boundary_z, "Boss战餐车不能越过Boss前边界")
	cart.end_boss_movement()
	_check(is_equal_approx(cart.position.z, editor_position.z), "Boss战结束后餐车恢复开战站位")
	cart.target_z = movement_boss.position.z
	cart._physics_process(0.1)
	_check(is_equal_approx(cart.position.z, editor_position.z), "普通阶段忽略纵向目标并维持横移")
	movement_boss.free()
	var locked_attack_position: Vector3 = Vector3(3.6, 0.0, 12.25)
	var attack_origin: Vector3 = Vector3(3.6, 0.0, 4.25)
	_check(
		PrototypeBoss3D.line_attack_hits(
			locked_attack_position,
			attack_origin,
			locked_attack_position
		),
		"Boss直线攻击命中锁定点"
	)
	_check(
		not PrototypeBoss3D.line_attack_hits(
			locked_attack_position + Vector3(0.0, 0.0, 0.01),
			attack_origin,
			locked_attack_position
		),
		"餐车沿Z轴移出可见直线末端后躲开攻击"
	)
	_check(
		PrototypeBoss3D.area_attack_hits(
			locked_attack_position,
			locked_attack_position
		),
		"Boss范围攻击命中锁定点"
	)
	_check(
		not PrototypeBoss3D.area_attack_hits(
			locked_attack_position + Vector3(0.0, 0.0, PrototypeBoss3D.AREA_ATTACK_RADIUS + 0.01),
			locked_attack_position
		),
		"餐车沿Z轴移出可见范围圆后躲开攻击"
	)
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
	var right_health_label: Label3D = gate.get_node("RightHealthLabel") as Label3D
	var left_health_back: MeshInstance3D = gate.get_node("LeftHealthBack") as MeshInstance3D
	var left_health_fill: MeshInstance3D = gate.get_node("LeftHealthFill") as MeshInstance3D
	var left_panel: MeshInstance3D = gate.get_node("LeftPanel") as MeshInstance3D
	var left_material: StandardMaterial3D = left_panel.material_override as StandardMaterial3D
	var gate_color_before: Color = left_material.albedo_color
	var number_color_before: Color = left_health_label.modulate
	_check(left_health_label.text.to_int() == ceili(gate.left_base_health), "3D普通门在门板上方独立显示公开基础胃口")
	_check(not left_health_back.visible and not left_health_fill.visible, "3D普通门不显示胃口进度条")
	_check(left_health_label.font_size >= 64, "3D普通门使用显眼数字显示公开胃口")
	_check(
		left_health_label.modulate.is_equal_approx(left_upgrade.rarity_color)
		and right_health_label.modulate.is_equal_approx(right_upgrade.rarity_color),
		"3D普通门左右公开胃口数字分别使用当前奖励稀有度色"
	)
	gate.receive_damage(true, gate.left_base_health)
	gate.receive_damage(true, 50.0)
	_check(left_health_label.text == "0", "3D门额外升值血量保持隐藏，公开数字归零后不再显示")
	_check(not left_material.albedo_color.is_equal_approx(gate_color_before), "3D普通门升值跨稀有度后实时换色")
	_check(
		left_health_label.modulate.is_equal_approx(left_upgrade.rarity_color)
		and not left_health_label.modulate.is_equal_approx(number_color_before),
		"3D普通门升值跨稀有度后公开胃口数字同步换色"
	)
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


# 法棍先按表中30度半角限制正前方60度扇区，再按X/Z平面真实距离瞄准。
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
		"法棍忽略前方60°之外的更近单位，并选择扇区内最近单位"
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

	var boundary_horizontal: float = tan(deg_to_rad(30.0)) * 2.0
	var left_boundary: Customer3D = Customer3D.new()
	left_boundary.position = Vector3(3.6 - boundary_horizontal, 0.0, 8.0)
	left_boundary.active = true
	left_boundary.spawn_index = 3
	var right_boundary: Customer3D = Customer3D.new()
	right_boundary.position = Vector3(3.6 + boundary_horizontal, 0.0, 8.0)
	right_boundary.active = true
	right_boundary.spawn_index = 4
	var just_outside: Customer3D = Customer3D.new()
	just_outside.position = Vector3(3.6 - boundary_horizontal - 0.01, 0.0, 8.0)
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
		"法棍计入北偏西30°边界，并排除边界外与后方单位"
	)
	left_boundary.active = false
	_check(
		run.get_priority_target_for_food(baguette) == right_boundary,
		"法棍计入北偏东30°边界"
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
	_check(street_props.get_child_count() == 7, "街景面片及道路贴花集中在可编辑节点组")
	var road_segment: Node3D = background.get_node("RoadSegment3") as Node3D
	var road_surface: MeshInstance3D = road_segment.get_node("RoadSurface") as MeshInstance3D
	var left_curb: MeshInstance3D = road_segment.get_node("LeftCurbFace") as MeshInstance3D
	var left_sidewalk: MeshInstance3D = road_segment.get_node("LeftSidewalk") as MeshInstance3D
	var road_mesh: PlaneMesh = road_surface.mesh as PlaneMesh
	var curb_mesh: QuadMesh = left_curb.mesh as QuadMesh
	var sidewalk_mesh: PlaneMesh = left_sidewalk.mesh as PlaneMesh
	_check(road_mesh.size.is_equal_approx(Vector2(6.041834, 12.8)), "中央马路宽度按拆分贴图比例装配")
	_check(curb_mesh.size.is_equal_approx(Vector2(0.5, 12.8)), "路沿立面保持独立可编辑宽度")
	_check(sidewalk_mesh.size.is_equal_approx(Vector2(1.69, 12.8)), "人行道保持独立可编辑宽度")
	for child: Node in street_props.find_children("*", "Sprite3D", true, false):
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
		Vector3.ZERO,
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
		Vector3.ZERO,
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
		Vector3.ZERO,
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
		Vector3.ZERO,
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
	var base_orbit_radius: float = Playfield.design_to_world(mushroom.orbit_radius)
	_check(is_equal_approx(orbit.position.distance_to(cart.position), base_orbit_radius), "蘑菇从配置的基础半径开始环绕")
	orbit._process_orbit(turn_duration)
	_check(is_equal_approx(orbit.position.distance_to(cart.position), base_orbit_radius), "蘑菇先在基础半径完整旋转一圈")
	orbit._process_orbit(turn_duration * 0.5)
	_check(is_equal_approx(orbit.position.distance_to(cart.position), base_orbit_radius * 1.25), "扩张圈中点平滑到基础半径的1.25倍")
	orbit._process_orbit(turn_duration * 0.5)
	_check(is_equal_approx(orbit.position.distance_to(cart.position), base_orbit_radius * 1.5), "扩张圈结束到达当前半径的1.5倍")
	orbit._process_orbit(turn_duration)
	_check(is_equal_approx(orbit.position.distance_to(cart.position), base_orbit_radius * 1.5), "蘑菇在1.5倍半径处再次完整旋转一圈")
	orbit._process_orbit(turn_duration)
	_check(is_equal_approx(orbit.position.distance_to(cart.position), base_orbit_radius * 2.25), "下一扩张圈继续到当前半径的1.5倍")

	var faster_orbit: FoodProjectile3D = projectile_scene.instantiate() as FoodProjectile3D
	run.add_child(faster_orbit)
	faster_orbit.configure(
		run,
		cart.position,
		Vector3.FORWARD,
		mushroom,
		7.0,
		mushroom.orbit_angular_speed * 1.5,
		Vector3.ZERO,
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
		is_equal_approx(faster_orbit.position.distance_to(cart.position), base_orbit_radius * 1.25),
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
		Vector3.ZERO,
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
		and is_equal_approx(longer_orbit._orbit_base_radius, base_orbit_radius),
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
		Vector3.ZERO,
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
		is_equal_approx(breathing_orbit.position.distance_to(cart.position), base_orbit_radius * 2.0),
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
	_check(
		state.normal_upgrade_choice_counts.get(&"sugar", 0) == 1
		and is_equal_approx(state.normal_upgrade_value_totals.get(&"sugar", 0.0), 0.2),
		"普通强化选择记录实际结算次数与数值"
	)
	state.level_food(&"potato")
	_check(
		is_equal_approx(state.effective_satisfaction(potato), 27.0),
		"食材Lv.2的2.25倍独立倍率与糖的全局倍率相乘"
	)
	state.level_food(&"potato")
	_check(state.food_level(&"potato") == 3, "食材等级最高为Lv.3")
	_check(not state.can_level_food(&"potato"), "满级食材不再进入升级候选")
	state.enable_food_evolution(&"potato_aim")
	_check(state.has_food_evolution(&"potato_aim"), "签名进化状态可独立记录")

	var quick_prep: UpgradeData = UpgradeData.new()
	quick_prep.id = &"quick_prep"
	quick_prep.kind = UpgradeData.Kind.QUICK_PREP
	quick_prep.value = 100.0
	state.apply_upgrade(quick_prep)
	_check(is_equal_approx(state.effective_interval(potato), RunState.MINIMUM_INTERVAL), "攻击间隔限制为每帧一次")
	quick_prep.value = 0.08
	_check(quick_prep.effect_text() == "攻速 +8%", "门使用正向攻击速度描述")
	state.record_normal_upgrade_offer([sugar, quick_prep])
	_check(
		state.normal_upgrade_offer_counts.get(&"sugar", 0) == 1
		and state.normal_upgrade_offer_counts.get(&"quick_prep", 0) == 1,
		"普通强化候选按类型记录被提供次数"
	)

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
	sturdy.value = 0.1
	_check(sturdy.effect_text(100.0) == "耐久 +10点", "餐车改造按当前最大耐久显示实际点数")
	state.apply_upgrade(sturdy)
	_check(is_equal_approx(state.maximum_durability, 110.0), "最大耐久按当前上限百分比提高")
	_check(is_equal_approx(state.current_durability, 110.0), "餐车改造同步增加相同实际耐久")

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
	var expected_wine_multiplier: float = 1.0 + log(1.0 + 0.25 * potato.wine_upgrade_scale)
	var expected_duration_multiplier: float = 1.0 + log(1.0 + 0.5 * potato.duration_upgrade_scale)
	_check(
		is_equal_approx(
			distance_state.effective_projectile_distance(potato),
			potato.projectile_speed * expected_wine_multiplier
			* potato.base_lifetime * expected_duration_multiplier
		),
		"弹速与持续时间按各自食材转译和对数曲线共同决定投射距离"
	)
	_check(
		distance_state._log_upgrade_multiplier(0.01, 1.0, 1.0) > 1.009
		and distance_state._log_upgrade_multiplier(2.0, 1.0, 1.0) < 3.0,
		"物理强化低层近似线性且高层持续递减"
	)
	var mushroom: FoodData = load("res://data/foods/mushroom.tres") as FoodData
	var mushroom_state: RunState = RunState.new()
	var scallion: UpgradeData = UpgradeData.new()
	scallion.kind = UpgradeData.Kind.SCALLION
	scallion.value = 0.6
	mushroom_state.apply_upgrade(scallion)
	starch.value = 0.6
	mushroom_state.apply_upgrade(starch)
	_check(
		is_equal_approx(
			mushroom_state.effective_projectile_radius(mushroom),
			mushroom.projectile_radius * (1.0 + 4.0 * log(1.0 + 0.6 * 0.5 / 4.0))
		),
		"蘑菇以0.5倍率转译范围强化后进入C=4对数曲线"
	)
	_check(
		is_equal_approx(
			mushroom_state.effective_duration(mushroom),
			mushroom.base_lifetime * (1.0 + log(1.0 + 0.6 * 0.15))
		),
		"蘑菇以0.15倍率转译持续强化后进入C=1对数曲线"
	)


# 受伤震屏覆盖两类判据及严格百分比边界，避免临界值落入错误档位。
func _test_damage_camera_shake_rules() -> void:
	_check(
		RunController3D.damage_shake_level(50.0, 100.0, 50.0)
		== RunController3D.DamageShakeLevel.MEDIUM,
		"单次伤害正好50%时使用中等震屏"
	)
	_check(
		RunController3D.damage_shake_level(50.01, 100.0, 50.0)
		== RunController3D.DamageShakeLevel.STRONG,
		"单次伤害高于50%时使用强力震屏"
	)
	_check(
		RunController3D.damage_shake_level(10.0, 100.0, 19.99)
		== RunController3D.DamageShakeLevel.STRONG,
		"受伤后耐久低于20%时使用强力震屏"
	)
	_check(
		RunController3D.damage_shake_level(30.0, 100.0, 70.0)
		== RunController3D.DamageShakeLevel.MEDIUM,
		"单次伤害正好30%时使用中等震屏"
	)
	_check(
		RunController3D.damage_shake_level(10.0, 100.0, 49.99)
		== RunController3D.DamageShakeLevel.MEDIUM,
		"受伤后耐久低于50%时使用中等震屏"
	)
	_check(
		RunController3D.damage_shake_level(10.0, 100.0, 50.0)
		== RunController3D.DamageShakeLevel.SMALL,
		"其他有效伤害使用小幅震屏"
	)
	var run: RunController3D = RunController3D.new()
	var background: WorldBackground3D = WorldBackground3D.new()
	run.state = RunState.new()
	run.background = background
	run.state.current_durability = 49.0
	run._on_cart_damaged(30.0)
	_check(
		is_equal_approx(
			background._camera_shake_strength,
			RunController3D.DAMAGE_SHAKE_MEDIUM_STRENGTH
		),
		"餐车受伤信号实际调用中等震屏参数"
	)
	run.free()
	background.free()


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
	reward.set_source_scale(0.4, "小份奖励")
	_check(is_equal_approx(reward.value, 0.0744), "小份奖励保留百分位并把实际强化值缩放为40%")
	_check(is_equal_approx(basic.appetite_at(100.0, 0.34, 0.4), 114.0), "小份奖励的额外胃口只按40%计算")
	_check(is_equal_approx(elite.appetite_at(32.0), 48.0), "精英只使用1.5倍基准且不参与随机稀有度")
	var reward_scene: PackedScene = load("res://scenes/upgrade_drop_3d.tscn") as PackedScene
	var reward_gate: UpgradeDrop3D = reward_scene.instantiate() as UpgradeDrop3D
	reward_gate.configure(null, reward, Vector3(1.6, 0.0, 4.0), 100.0, 2, 3)
	_check(is_equal_approx(reward_gate.upgrade_health, 26.4), "小份奖励门的隐藏升值血量按40%缩放")
	_check(reward_gate.contains_cart_x(1.6), "餐车经过食客原占地区域可以领取奖励门")
	_check(not reward_gate.contains_cart_x(3.6), "餐车绕开奖励门时不能领取")
	reward_gate.receive_damage(13.2)
	_check(is_equal_approx(reward.value_ratio, 0.67), "攻击小份奖励门继续提高原百分位与稀有度")
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
	existing_drop.position = Vector3(1.6, 0.0, 6.5)
	drops.add_child(existing_drop)
	var customer: Customer3D = Customer3D.new()
	customer.data = load("res://data/customers/basic_guest.tres") as CustomerData
	customer.run = run
	customer.active = true
	customer.position = Vector3(1.6, 0.0, 6.5)
	run.customers.append(customer)
	run.add_child(customer)
	var safe_z: float = run._find_reward_gate_spawn_z(5.0, 1.6, 2)
	_check(
		is_equal_approx(safe_z, 5.0),
		"奖励门优先保留食客位置，并允许与食客、普通门和奖励门有限重合"
	)
	existing_drop.position = Vector3(5.6, 0.0, 5.0)
	_check(
		is_equal_approx(run._find_reward_gate_spawn_z(5.0, 1.6, 2), 5.0),
		"横向不相交的奖励门可以共享食客原纵向位置"
	)
	gate.position.z = -10.0
	existing_drop.position = Vector3(1.6, 0.0, 5.0)
	var overlapped_z: float = run._find_reward_gate_spawn_z(5.0, 1.6, 2)
	_check(
		absf(overlapped_z - 5.0) >= RunController3D.REWARD_GATE_MIN_CENTER_DISTANCE
		and absf(overlapped_z - 5.0) < UpgradeDrop3D.PANEL_HEIGHT,
		"同横向奖励门只做最小避让并保留约半个门深的重合"
	)
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
	_check(timeline != null and timeline.is_valid(), "正式距离时间轴通过类型化校验")
	if timeline == null:
		return
	_check(
		is_equal_approx(timeline.baseline_appetite_at_elapsed_seconds(0.0), 15.0)
		and is_equal_approx(timeline.baseline_appetite_at_elapsed_seconds(135.0), 350.0)
		and is_equal_approx(timeline.baseline_appetite_at_elapsed_seconds(300.0), 2825.0)
		and is_equal_approx(timeline.baseline_appetite_at_elapsed_seconds(480.0), 12000.0)
		and is_equal_approx(timeline.baseline_appetite_at_elapsed_seconds(600.0), 12000.0),
		"胃口曲线按有效时间经过三段锚点并在480秒后封顶"
	)
	var expected_first_midpoint: float = roundf(lerpf(15.0, 350.0, pow(0.5, 2.1)))
	_check(
		is_equal_approx(
			timeline.baseline_appetite_at_elapsed_seconds(67.5),
			expected_first_midpoint
		),
		"第一段胃口指数2.1只控制段内增长形状"
	)
	_check(
		is_equal_approx(timeline.speed_multiplier_at_progress(0.1874), 1.0)
		and is_equal_approx(timeline.speed_multiplier_at_progress(0.1875), 1.1)
		and is_equal_approx(timeline.speed_multiplier_at_progress(0.8125), 3.0),
		"六档前进倍率在指定路程边界切换"
	)
	_check(
		is_equal_approx(timeline.course_distance, 1310.763)
		and timeline.normal_gate_count == 50
		and timeline.normal_wave_count == 250
		and timeline.expected_normal_customer_count() == 312,
		"正式流程以独立总路程排布50门、250波和312只普通食客"
	)
	_check(timeline.event_ids.count("start_gate") == 1, "正式流程包含一道开局食材门")
	var start_gate_index: int = timeline.event_ids.find("start_gate")
	_check(
		start_gate_index >= 0
		and is_equal_approx(timeline.event_progresses[start_gate_index], 0.01),
		"正式开局食材门位于总路程1%进度"
	)
	_check(timeline.event_ids.count("elite") == 6, "正式流程包含六次精英检查")
	_check(timeline.event_ids.count("boss") == 2, "正式流程包含两场Boss")
	var first_boss_index: int = timeline.event_ids.find("boss")
	var second_boss_index: int = timeline.event_ids.rfind("boss")
	_check(
		first_boss_index >= 0
		and is_equal_approx(timeline.event_progresses[first_boss_index], 0.5)
		and is_equal_approx(timeline.event_progresses[second_boss_index], 1.0),
		"两场Boss分别位于50%与100%路程点"
	)
	_check(
		timeline.course_distance > 0.0,
		"正式总路程是独立运行参数"
	)
	var missing_result: TimelineExcelLoader.LoadResult = TimelineExcelLoader.load_from_excel(
		"res://balance_tables/__missing__.xlsx",
		fallback
	)
	_check(missing_result.used_fallback and missing_result.timeline == fallback, "Excel 缺失时使用 .tres 回退")


# 波次路程与食客路线都由局种子稳定复现，同时严格保持配置的间隔边界。
func _test_seeded_spawn_randomness() -> void:
	var timeline: EncounterTimeline = EncounterTimeline.new()
	timeline.normal_wave_count = 19
	timeline.normal_wave_interval_jitter_ratio = 0.2
	var run: RunController3D = RunController3D.new()
	run._spawn_rng.seed = 20260730
	var first_progresses: PackedFloat32Array = run._build_normal_wave_progresses(timeline)
	run._spawn_rng.seed = 20260730
	var repeated_progresses: PackedFloat32Array = run._build_normal_wave_progresses(timeline)
	run._spawn_rng.seed = 20260731
	var different_progresses: PackedFloat32Array = run._build_normal_wave_progresses(timeline)
	_check(first_progresses == repeated_progresses, "同种子复现相同普通波次路程")
	_check(first_progresses != different_progresses, "不同种子产生不同普通波次路程")
	var base_gap: float = 1.0 / float(timeline.normal_wave_count + 1)
	var minimum_gap: float = base_gap * 0.8 - 0.000001
	var maximum_gap: float = base_gap * 1.2 + 0.000001
	var previous_progress: float = 0.0
	for progress: float in first_progresses:
		var gap: float = progress - previous_progress
		_check(gap >= minimum_gap and gap <= maximum_gap, "波次路程间隔保持在配置的正负20%内")
		previous_progress = progress
	var final_gap: float = 1.0 - previous_progress
	_check(final_gap >= minimum_gap and final_gap <= maximum_gap, "末波到终点的路程间隔也保持在边界内")
	var safe_regions: Array[int] = [0, 1, 2, 3, 4]
	run._spawn_rng.seed = 7001
	var first_routes: Array[int] = []
	for _index: int in range(12):
		first_routes.append(run._choose_spawn_first_region(safe_regions))
	run._spawn_rng.seed = 7001
	var repeated_routes: Array[int] = []
	for _index: int in range(12):
		repeated_routes.append(run._choose_spawn_first_region(safe_regions))
	run._spawn_rng.seed = 7002
	var different_routes: Array[int] = []
	for _index: int in range(12):
		different_routes.append(run._choose_spawn_first_region(safe_regions))
	_check(first_routes == repeated_routes, "同种子复现相同食客路线序列")
	_check(first_routes != different_routes, "不同种子产生不同食客路线序列")
	run.free()


# 验证压力档位同时驱动风场、食材免疫规则和末段操控目标。
func _test_pressure_rules() -> void:
	var timeline: EncounterTimeline = load("res://data/timelines/vertical_slice.tres") as EncounterTimeline
	var run: RunController3D = RunController3D.new()
	var director: EncounterDirector = EncounterDirector.new()
	var state: RunState = RunState.new()
	director.timeline = timeline
	run.add_child(director)
	run.director = director
	run.state = state
	state.forward_distance = timeline.course_distance * 0.9
	var expected_headwind: float = (
		1.25 * RunController3D.BASE_WORLD_SCROLL_SPEED * (3.0 - 1.0)
	)
	_check(is_equal_approx(run.forward_speed_multiplier(), 3.0), "末段使用3.0倍前进速度")
	_check(is_equal_approx(run.current_headwind_speed(), expected_headwind), "迎面风按1.25倍基础滚动差值计算")
	_check(is_equal_approx(absf(run.current_crosswind_speed()), Playfield.design_to_world(60.0)), "末段侧漂达到60px/s")
	var potato: FoodData = load("res://data/foods/potato.tres") as FoodData
	var mushroom: FoodData = load("res://data/foods/mushroom.tres") as FoodData
	var normal_wind: Vector3 = run._projectile_environment_velocity(potato, false)
	_check(run._projectile_environment_velocity(mushroom, false).is_zero_approx(), "蘑菇免疫位移风")
	_check(run._projectile_environment_velocity(potato, true).is_equal_approx(normal_wind * 0.25), "巨型法棍只承受普通投射物25%的风偏")
	state.cart_base_speed_factor = 0.8
	state.cart_speed_bonus = 2700.0
	var late_cart_speed: float = (
		Cart3D.BASE_MOVE_SPEED_DESIGN * state.cart_base_speed_factor
		+ state.effective_cart_speed_bonus(Cart3D.BASE_MOVE_SPEED_DESIGN)
	)
	var crossing_seconds: float = Playfield.world_to_design(6.12 - 1.08) / late_cart_speed
	_check(crossing_seconds >= 0.28 and crossing_seconds <= 0.34, "末段混合构筑横穿可操作宽度约0.30秒")
	run.free()


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
	_check(baguette != null and baguette.pierce_count == 3, "法棍默认额外穿透两个目标")
	_check(baguette.initial_tracking_mode == FoodData.TrackingMode.NONE, "法棍初始不追踪")
	_check(
		mushroom != null
		and mushroom.attack_kind == FoodData.AttackKind.ORBITING_MUSHROOM,
		"蘑菇使用环绕攻击类型"
	)
	_check(is_equal_approx(mushroom.breathing_period, 1.2), "蘑菇呼吸扩圈固定为1.2秒周期")
	_check(is_equal_approx(mushroom.breathing_outer_multiplier, 2.0), "蘑菇呼吸扩圈外沿为两倍基础半径")
	_check(
		is_equal_approx(potato.projectile_speed, 680.0)
		and is_equal_approx(potato.base_lifetime, 1.3473684)
		and is_equal_approx(
			roundf(
				potato.projectile_speed * potato.base_lifetime / 1280.0 * 100.0
			) / 100.0,
			0.72
		),
		"土豆回退参数保持当前约0.72屏基础射程"
	)
	_check(
		is_equal_approx(baguette.base_satisfaction, 10.0)
		and is_equal_approx(baguette.base_interval, 1.0)
		and is_equal_approx(baguette.projectile_speed, 2000.0)
		and is_equal_approx(baguette.base_lifetime, 0.5)
		and is_equal_approx(
			roundf(
				baguette.projectile_speed * baguette.base_lifetime / 1280.0 * 100.0
			) / 100.0,
			0.78
		),
		"法棍回退参数保持当前约0.78屏基础射程与10点理论DPS"
	)
	_check(
		basic.category == CustomerData.Category.NORMAL
		and basic.behavior == CustomerData.Behavior.NONE
		and basic.id == &"basic_guest"
		and not basic.display_name.is_empty()
		and basic.customer_scene != null,
		"基础食客回退资源保留ID、非空显示名、可预览场景与无行为"
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
	_check(
		elite != null and elite.occupied_regions == 6 and is_zero_approx(elite.move_speed),
		"精英横跨六区且不主动移动"
	)
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
	_check(boss != null and is_equal_approx(boss.appetite_at(100.0), 300.0), "Boss默认使用3倍基准胃口")
	var boss_scene: PackedScene = load(
		"res://scenes/characters/bosses/prototype_boss_3d.tscn"
	) as PackedScene
	var boss_instance: PrototypeBoss3D = boss_scene.instantiate() as PrototypeBoss3D
	var boss_body: MeshInstance3D = boss_instance.get_node("Body") as MeshInstance3D
	var boss_head: MeshInstance3D = boss_instance.get_node("Head") as MeshInstance3D
	_check(boss_body.visible and boss_head.visible, "Boss占位视觉已静态装配在可预览场景中")
	var boss_animation_player: AnimationPlayer = boss_instance.get_node("AnimationPlayer") as AnimationPlayer
	_check(
		boss_animation_player.has_animation(&"line_attack")
		and boss_animation_player.has_animation(&"area_attack"),
		"Boss直线与范围预警使用可编辑AnimationPlayer动画"
	)
	_check(
		boss_instance.get_node_or_null("AttackOrigin") is Marker3D
		and boss_instance.get_node_or_null("LineAttackAnchor/LineAttackRig/LineImpactMarker") is Marker3D
		and boss_instance.get_node_or_null("AreaAttackAnchor/AreaAttackRig/AreaImpactMarker") is Marker3D,
		"Boss攻击场景保留代码可读取的生成与落点Marker3D"
	)
	var line_telegraph: MeshInstance3D = boss_instance.get_node(
		"LineAttackAnchor/LineAttackRig/LineTelegraph"
	) as MeshInstance3D
	var area_telegraph: MeshInstance3D = boss_instance.get_node(
		"AreaAttackAnchor/AreaAttackRig/AreaTelegraph"
	) as MeshInstance3D
	var line_mesh: BoxMesh = line_telegraph.mesh as BoxMesh
	var area_mesh: CylinderMesh = area_telegraph.mesh as CylinderMesh
	_check(
		is_equal_approx(line_mesh.size.x, PrototypeBoss3D.LINE_ATTACK_WIDTH)
		and is_equal_approx(area_mesh.top_radius, PrototypeBoss3D.AREA_ATTACK_RADIUS)
		and is_equal_approx(area_mesh.bottom_radius, PrototypeBoss3D.AREA_ATTACK_RADIUS),
		"Boss攻击命中范围与可见预警几何使用同一尺寸"
	)
	var boss_material: StandardMaterial3D = boss_body.material_override as StandardMaterial3D
	var boss_appetite_back: MeshInstance3D = boss_instance.get_node("AppetiteBack") as MeshInstance3D
	var boss_appetite_fill: MeshInstance3D = boss_instance.get_node("AppetiteFill") as MeshInstance3D
	var boss_appetite_label: Label3D = boss_instance.get_node("AppetiteLabel") as Label3D
	var boss_fill_mesh: BoxMesh = boss_appetite_fill.mesh as BoxMesh
	_check(
		boss_appetite_back.visible
		and boss_appetite_fill.visible
		and is_equal_approx(boss_fill_mesh.size.x, PrototypeBoss3D.APPETITE_FILL_WIDTH),
		"Boss独立显示可编辑纸条胃口条"
	)
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
	boss_instance.receive_satisfaction(boss_instance.maximum_appetite * 0.5)
	_check(
		is_equal_approx(boss_appetite_fill.scale.x, 0.5)
		and boss_appetite_label.text.to_int() == ceili(boss_instance.maximum_appetite * 0.5),
		"Boss纸条填充与数字同步反映剩余胃口"
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
