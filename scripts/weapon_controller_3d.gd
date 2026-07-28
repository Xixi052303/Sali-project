class_name WeaponController3D
extends Node

var run: RunController3D
var cart: Cart3D
var state: RunState
var foods: Array[FoodRuntime] = []
# 巨型法棍使用独立固定节拍，不受普通法棍攻速和加量影响。
var _giant_baguette_enabled: bool = false
var _giant_baguette_cooldown: float = 0.0


func configure(run_controller: RunController3D, source_cart: Cart3D, run_state: RunState) -> void:
	run = run_controller
	cart = source_cart
	state = run_state


func add_food(food: FoodData) -> void:
	for runtime: FoodRuntime in foods:
		if runtime.data.id == food.id:
			return
	var runtime: FoodRuntime = FoodRuntime.new(food)
	foods.append(runtime)
	state.add_food(food.id)


func _process(delta: float) -> void:
	if run == null or cart == null or state == null or not run.can_weapons_fire():
		return
	for runtime: FoodRuntime in foods:
		_tick_food(runtime, delta)
		if runtime.data.id == &"baguette":
			_tick_giant_baguette(runtime.data, delta)


func _tick_food(runtime: FoodRuntime, delta: float) -> void:
	if not runtime.ready:
		runtime.cooldown_remaining -= delta
		if runtime.cooldown_remaining <= 0.0:
			runtime.ready = true
	if not runtime.ready:
		return
	var target: Node3D = run.get_priority_target_for_food(runtime.data)
	runtime.ready = false
	runtime.cooldown_remaining = state.effective_interval(runtime.data)
	_fire(runtime.data, target)


func _fire(food: FoodData, target: Node3D) -> void:
	var amount: float = state.effective_satisfaction(food)
	var speed: float = Playfield.design_to_world(state.effective_projectile_speed(food))
	if food.attack_kind == FoodData.AttackKind.ORBITING_MUSHROOM:
		speed = state.effective_orbit_angular_speed(food)
	var radius: float = Playfield.design_to_world(state.effective_projectile_radius(food))
	var count: int = maxi(1, state.servings)
	var base_direction: Vector3 = Vector3.FORWARD
	var cart_position: Vector3 = run.logic_position(cart)
	if target != null and (
		food.initial_aim_mode == FoodData.AimMode.TARGET_SNAPSHOT
		or state.is_food_target_aimed(food.id)
	):
		var target_position: Vector3 = run.logic_position(target)
		base_direction = target_position - cart_position
		base_direction.y = 0.0
		base_direction = base_direction.normalized()
	for index: int in range(count):
		var direction: Vector3 = base_direction
		var spread: float = (float(index) - float(count - 1) * 0.5) * 0.075
		direction = direction.rotated(Vector3.UP, spread)
		var orbit_phase: float = TAU * float(index) / float(count)
		run.spawn_projectile(
			cart_position + Vector3(0.0, 0.0, -1.35),
			direction,
			food,
			amount,
			speed,
			radius,
			target,
			orbit_phase
		)


# 进化取得后等待完整间隔，再额外发射一根固定份数的巨型法棍。
func _tick_giant_baguette(food: FoodData, delta: float) -> void:
	if not state.has_food_evolution(&"baguette_giant"):
		_giant_baguette_enabled = false
		_giant_baguette_cooldown = 0.0
		return
	var interval: float = maxf(RunState.MINIMUM_INTERVAL, state.baguette_giant_interval_seconds)
	if not _giant_baguette_enabled:
		_giant_baguette_enabled = true
		_giant_baguette_cooldown = interval
		return
	_giant_baguette_cooldown -= delta
	if _giant_baguette_cooldown > 0.000001:
		return
	_giant_baguette_cooldown += interval
	_fire_giant_baguette(food)


# 巨型法棍继承法棍当前基础成长，再应用表格中的专属伤害倍率。
func _fire_giant_baguette(food: FoodData) -> void:
	var cart_position: Vector3 = run.logic_position(cart)
	run.spawn_projectile(
		cart_position + Vector3(0.0, 0.0, -1.35),
		Vector3.FORWARD,
		food,
		state.effective_satisfaction(food) * state.baguette_giant_satisfaction_multiplier,
		Playfield.design_to_world(state.effective_projectile_speed(food)),
		Playfield.design_to_world(state.effective_projectile_radius(food)),
		null,
		0.0,
		true
	)
