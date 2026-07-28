extends SceneTree

var _failures: int = 0


func _init() -> void:
	var load_result: GameplayExcelLoader.SpecialUpgradeLoadResult = (
		GameplayExcelLoader.load_special_upgrades("res://balance_tables/特殊强化.xlsx")
	)
	_check(load_result.loaded_from_excel, "巨型法棍配置表可读取")
	_check(is_equal_approx(load_result.baguette_giant_interval_seconds, 3.0), "发射间隔为3秒")
	_check(is_equal_approx(load_result.baguette_giant_width_regions, 4.0), "横向宽度为4格")
	_check(load_result.baguette_giant_pierce_count == 999, "穿透为999")
	_check(is_equal_approx(load_result.baguette_giant_duration_multiplier, 1.5), "持续倍率为1.5")
	_check(is_equal_approx(load_result.baguette_giant_satisfaction_multiplier, 3.0), "满足倍率为3")
	_test_runtime(load_result)
	if _failures == 0:
		print("BAGUETTE_GIANT_TEST_OK")
		quit(0)
	else:
		push_error("BAGUETTE_GIANT_TEST_FAILED count=%d" % _failures)
		quit(1)


# 验证进化的独立节拍、投射物参数、朝向与道路平面碰撞。
func _test_runtime(load_result: GameplayExcelLoader.SpecialUpgradeLoadResult) -> void:
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
	state.baguette_giant_width_regions = load_result.baguette_giant_width_regions
	state.baguette_giant_pierce_count = load_result.baguette_giant_pierce_count
	state.baguette_giant_duration_multiplier = load_result.baguette_giant_duration_multiplier
	state.baguette_giant_satisfaction_multiplier = load_result.baguette_giant_satisfaction_multiplier
	state.add_food(&"baguette")
	state.enable_food_evolution(&"baguette_giant")
	run.state = state
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
	_check(giant._giant_baguette, "额外投射物使用巨型法棍模式")
	_check(not giant.homing_enabled and giant.tracking_target == null, "巨型法棍不追踪")
	_check(giant.velocity.normalized().is_equal_approx(Vector3.FORWARD), "巨型法棍沿道路直线前进")
	_check(giant.remaining_hits == 999, "巨型法棍应用独立穿透")
	_check(is_equal_approx(giant._giant_half_width * 2.0, Playfield.REGION_WIDTH * 4.0), "巨型法棍应用四格宽度")
	_check(is_equal_approx(giant._initial_lifetime, state.effective_duration(baguette) * 1.5), "巨型法棍应用持续倍率")
	_check(is_equal_approx(giant.satisfaction, state.effective_satisfaction(baguette) * 3.0), "巨型法棍应用满足倍率")
	_check(giant.overlaps_target(Vector3(5.8, 0.0, giant.position.z), 0.2), "四格范围内目标会被命中")
	_check(not giant.overlaps_target(Vector3(6.8, 0.0, giant.position.z), 0.2), "四格范围外目标不会被命中")

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
	aimed._process_forward_motion(0.0)
	_check(aimed.rotation.y < 0.0, "普通法棍朝右前目标时模型向右旋转")
	run.free()


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("TEST FAILED: %s" % label)
