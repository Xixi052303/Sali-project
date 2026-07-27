class_name WeaponController
extends Node

var run: RunController
var cart: Cart
var state: RunState
var foods: Array[FoodRuntime] = []


func configure(run_controller: RunController, source_cart: Cart, run_state: RunState) -> void:
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


func _tick_food(runtime: FoodRuntime, delta: float) -> void:
	if not runtime.ready:
		runtime.cooldown_remaining -= delta
		if runtime.cooldown_remaining <= 0.0:
			runtime.ready = true
	if not runtime.ready:
		return
	var target: Node2D = run.get_priority_target()
	runtime.ready = false
	runtime.cooldown_remaining = state.effective_interval(runtime.data)
	_fire(runtime.data, target)


func _fire(food: FoodData, target: Node2D) -> void:
	var amount: float = state.effective_satisfaction(food)
	var speed: float = state.effective_projectile_speed(food)
	var radius: float = state.effective_projectile_radius(food)
	var count: int = maxi(1, state.servings)
	var base_direction: Vector2 = Vector2.UP
	if target != null and (
		food.initial_aim_mode == FoodData.AimMode.TARGET_SNAPSHOT
		or state.is_food_target_aimed(food.id)
	):
		base_direction = (target.global_position - cart.global_position).normalized()
	for index: int in range(count):
		var direction: Vector2 = base_direction
		var spread: float = (float(index) - float(count - 1) * 0.5) * 0.075
		direction = direction.rotated(spread)
		run.spawn_projectile(cart.global_position + Vector2(0.0, -135.0), direction, food, amount, speed, radius, target)
