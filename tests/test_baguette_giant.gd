extends SceneTree

var _failures: int = 0


func _init() -> void:
	var load_result: GameplayExcelLoader.WeaponLoadResult = (
		GameplayExcelLoader.load_weapons("res://balance_tables/武器.xlsx")
	)
	_check(load_result.loaded_from_excel, "巨型法棍配置表可读取")
	_check(is_equal_approx(load_result.baguette_giant_interval_seconds, 3.0), "发射间隔为3秒")
	_check(is_equal_approx(load_result.baguette_giant_attack_speed_scale, 0.05), "攻速强化倍率为0.05")
	_check(is_equal_approx(load_result.baguette_giant_minimum_interval_seconds, 1.0), "最快一秒发射一次")
	_check(is_equal_approx(load_result.baguette_giant_width_regions, 4.0), "横向宽度为4格")
	_check(load_result.baguette_giant_pierce_count == 999, "穿透为999")
	_check(is_equal_approx(load_result.baguette_giant_duration_multiplier, 1.5), "持续倍率为1.5")
	_check(is_equal_approx(load_result.baguette_giant_satisfaction_multiplier, 3.0), "满足倍率为3")
	_test_runtime(load_result)
	_test_camera_shake()
	if _failures == 0:
		print("BAGUETTE_GIANT_TEST_OK")
		quit(0)
	else:
		push_error("BAGUETTE_GIANT_TEST_FAILED count=%d" % _failures)
		quit(1)


# 验证进化的独立节拍、投射物参数、朝向与道路平面碰撞。
func _test_runtime(load_result: GameplayExcelLoader.WeaponLoadResult) -> void:
	var run: RunController3D = RunController3D.new()
	var cart_scene: PackedScene = load("res://scenes/cart_3d.tscn") as PackedScene
	var cart: Cart3D = cart_scene.instantiate() as Cart3D
	var projectiles: Node3D = Node3D.new()
	run.add_child(cart)
	run.add_child(projectiles)
	run.cart = cart
	run.projectiles = projectiles
	cart.position = Vector3(3.6, 0.0, Playfield.CART_Z)
	var state: RunState = RunState.new()
	state.baguette_giant_interval_seconds = load_result.baguette_giant_interval_seconds
	state.baguette_giant_attack_speed_scale = load_result.baguette_giant_attack_speed_scale
	state.baguette_giant_minimum_interval_seconds = load_result.baguette_giant_minimum_interval_seconds
	state.baguette_giant_width_regions = load_result.baguette_giant_width_regions
	state.baguette_giant_pierce_count = load_result.baguette_giant_pierce_count
	state.baguette_giant_duration_multiplier = load_result.baguette_giant_duration_multiplier
	state.baguette_giant_satisfaction_multiplier = load_result.baguette_giant_satisfaction_multiplier
	state.attack_speed_bonus = 1.0
	_check(
		is_equal_approx(state.effective_giant_baguette_interval(), 3.0 / 1.05),
		"巨型法棍只吸收5%的累计攻速"
	)
	state.attack_speed_bonus = 1000.0
	_check(is_equal_approx(state.effective_giant_baguette_interval(), 1.0), "巨型法棍间隔下限为1秒")
	state.attack_speed_bonus = 0.0
	state.range_multiplier = 3.0
	state.add_food(&"baguette")
	state.enable_food_evolution(&"baguette_giant")
	run.state = state
	var background: WorldBackground3D = WorldBackground3D.new()
	run.background = background
	var baguette: FoodData = load("res://data/foods/baguette.tres") as FoodData
	var weapon: WeaponController3D = WeaponController3D.new()
	run.add_child(weapon)
	weapon.configure(run, cart, state)
	weapon._tick_giant_baguette(baguette, 0.0)
	weapon._tick_giant_baguette(baguette, 2.9)
	_check(projectiles.get_child_count() == 0, "取得后等待完整发射间隔")
	weapon._tick_giant_baguette(baguette, 0.1)
	_check(projectiles.get_child_count() == 1, "到达3秒时额外发射一根")
	if projectiles.get_child_count() == 0:
		run.free()
		return
	var giant: FoodProjectile3D = projectiles.get_child(0) as FoodProjectile3D
	var range_scale: float = state.effective_projectile_radius(baguette) / baguette.projectile_radius
	_check(giant._giant_baguette, "额外投射物使用巨型法棍模式")
	_check(not giant.homing_enabled and giant.tracking_target == null, "巨型法棍不追踪")
	_check(giant.velocity.normalized().is_equal_approx(Vector3.FORWARD), "巨型法棍沿道路直线前进")
	_check(giant.remaining_hits == 999, "巨型法棍应用独立穿透")
	_check(is_equal_approx(giant._giant_half_width * 2.0, Playfield.REGION_WIDTH * 4.0 * range_scale), "巨型法棍以四格为基础同步应用对数范围倍率")
	_check(is_equal_approx(giant._initial_lifetime, state.effective_duration(baguette) * 1.5), "巨型法棍应用持续倍率")
	_check(is_equal_approx(giant.satisfaction, state.effective_satisfaction(baguette) * 3.0), "巨型法棍应用满足倍率")
	_check(background._camera_shake_remaining > 0.0, "巨型法棍发射时调用可复用震屏入口")
	var giant_dimensions: Vector3 = giant._giant_baguette_visual.model_scale() * GiantBaguette3D.MODEL_SIZE
	var visual_scale: float = minf(range_scale, FoodProjectile3D.MAXIMUM_VISUAL_RANGE_SCALE)
	_check(
		giant_dimensions.is_equal_approx(
			Vector3(
				0.2 * visual_scale,
				0.18 * visual_scale,
				minf(4.0 * visual_scale, Playfield.ROAD_WIDTH)
			)
		),
		"巨型法棍实体尺寸封顶且不超过六区道路"
	)
	_check(giant._range_box_outline.visible, "巨型法棍超过视觉上限时显示范围轮廓")
	giant.position.x = Playfield.ROAD_LEFT + 0.1
	giant._configure_visual()
	var side_dimensions: Vector3 = (
		giant._giant_baguette_visual.model_scale() * GiantBaguette3D.MODEL_SIZE
	)
	var side_visual_center: float = giant.position.x + giant._giant_baguette_visual.position.x
	_check(
		side_visual_center - side_dimensions.z * 0.5 >= Playfield.ROAD_LEFT - 0.001
		and side_visual_center + side_dimensions.z * 0.5
		<= Playfield.ROAD_LEFT + Playfield.ROAD_WIDTH + 0.001,
		"道路侧边发射时巨型法棍实体裁到六区道路内"
	)
	giant.position.x = Playfield.ROAD_LEFT + Playfield.ROAD_WIDTH * 0.5
	giant._configure_visual()
	var giant_model: Node3D = giant._giant_baguette_visual.get_node("RollPivot/ModelScale/BaguetteModel") as Node3D
	_check((giant_model.position + Vector3(0.0, 0.16503906, 0.0)).is_zero_approx(), "巨型法棍模型几何中心对齐滚动原点")
	giant._process_forward_motion(0.1)
	var roll_pivot: Node3D = giant._giant_baguette_visual.get_node("RollPivot") as Node3D
	_check(not is_zero_approx(roll_pivot.rotation.z), "巨型法棍由独立中心节点驱动滚动")
	_check(
		giant.overlaps_target(
			Vector3(giant.position.x + giant._giant_half_width - 0.1, 0.0, giant.position.z),
			0.0
		),
		"视觉封顶后巨型法棍仍使用完整范围判定"
	)
	_check(
		not giant.overlaps_target(
			Vector3(giant.position.x + giant._giant_half_width + giant.radius + 0.1, 0.0, giant.position.z),
			0.0
		),
		"巨型法棍不会命中完整范围之外的目标"
	)

	var projectile_scene: PackedScene = load("res://scenes/projectile_3d.tscn") as PackedScene
	var aimed: FoodProjectile3D = projectile_scene.instantiate() as FoodProjectile3D
	run.add_child(aimed)
	aimed.configure(
		run,
		Vector3(3.6, 0.0, 5.0),
		Vector3(1.0, 0.0, -1.0),
		baguette,
		8.0,
		7.0,
		Vector3.ZERO,
		Playfield.design_to_world(state.effective_projectile_radius(baguette)),
		1.2,
		3,
		null,
		false,
		0.0,
		false,
		0.0,
		false
	)
	aimed._process_forward_motion(0.0)
	_check(aimed.rotation.y < 0.0, "普通法棍朝右前目标时模型向右旋转")
	var aimed_visual: Node3D = aimed.get_node("BaguetteVisual") as Node3D
	var aimed_dimensions: Vector3 = aimed_visual.scale * FoodProjectile3D.BAGUETTE_MODEL_SIZE
	_check(
		aimed_dimensions.is_equal_approx(
			Vector3(0.2, 0.18, 0.8) * visual_scale
		),
		"普通法棍实体尺寸在1.5倍封顶"
	)
	_check(aimed._range_box_outline.visible, "普通法棍超过视觉上限时显示细长范围轮廓")
	run.free()
	background.free()


# 震屏必须实际移动主相机，并在持续时间结束后精确归位。
func _test_camera_shake() -> void:
	var background_scene: PackedScene = load("res://scenes/world_background_3d.tscn") as PackedScene
	var background: WorldBackground3D = background_scene.instantiate() as WorldBackground3D
	get_root().add_child(background)
	background.scrolling = false
	var camera: Camera3D = background.get_node("PaperCamera") as Camera3D
	var base_position: Vector3 = camera.position
	background.shake_camera(0.05, 0.1)
	background._process_camera_shake(0.02)
	_check(not camera.position.is_equal_approx(base_position), "震屏期间主相机发生小幅位移")
	background._process_camera_shake(0.2)
	_check(camera.position.is_equal_approx(base_position), "震屏结束后主相机精确归位")
	background.free()


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("TEST FAILED: %s" % label)
