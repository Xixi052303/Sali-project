class_name WeaponController3D
extends Node

signal food_added(food: FoodData)
signal food_removed(food_id: StringName)
signal cooking_progress_changed(
	food_id: StringName,
	progress: float,
	remaining_seconds: float
)

var run: RunController3D
var cart: Cart3D
var state: RunState
var player_slot: int = 1
var foods: Array[FoodRuntime] = []
# 巨型法棍使用独立固定节拍，不受普通法棍攻速和加量影响。
var _giant_baguette_enabled: bool = false
var _giant_baguette_cooldown: float = 0.0


func configure(
	run_controller: RunController3D,
	source_cart: Cart3D,
	run_state: RunState,
	owner_slot: int = 1
) -> void:
	run = run_controller
	cart = source_cart
	state = run_state
	player_slot = maxi(1, owner_slot)


func set_player_slot(owner_slot: int) -> void:
	player_slot = maxi(1, owner_slot)


func add_food(food: FoodData) -> void:
	for runtime: FoodRuntime in foods:
		if runtime.data.id == food.id:
			return
	var runtime: FoodRuntime = FoodRuntime.new(food)
	foods.append(runtime)
	state.add_food(food.id)
	food_added.emit(food)
	cooking_progress_changed.emit(food.id, 1.0, 0.0)


# Debug移除全部运行中食材，并让新取得的食材从首轮烹饪节拍重新开始。
func remove_all_foods() -> int:
	var removed_count: int = foods.size()
	for runtime: FoodRuntime in foods:
		if runtime.data != null:
			food_removed.emit(runtime.data.id)
	foods.clear()
	_giant_baguette_enabled = false
	_giant_baguette_cooldown = 0.0
	if state != null:
		state.clear_foods()
	return removed_count


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
		_emit_cooking_progress(runtime)
		return
	var target: Node3D = run.get_priority_target_for_food(runtime.data, player_slot)
	runtime.ready = false
	runtime.cooldown_duration = state.effective_interval(runtime.data)
	runtime.cooldown_remaining = runtime.cooldown_duration
	_fire(runtime.data, target)
	_emit_cooking_progress(runtime)


func _emit_cooking_progress(runtime: FoodRuntime) -> void:
	var duration: float = maxf(runtime.cooldown_duration, RunState.MINIMUM_INTERVAL)
	var remaining: float = maxf(0.0, runtime.cooldown_remaining)
	var progress: float = 1.0 if runtime.ready else 1.0 - clampf(remaining / duration, 0.0, 1.0)
	cooking_progress_changed.emit(runtime.data.id, progress, remaining)


func _fire(food: FoodData, target: Node3D) -> void:
	var amount: float = MultiplayerRules.ghost_output(
		state.effective_satisfaction(food),
		run.output_multiplier_for_slot(player_slot)
	)
	var speed: float = Playfield.design_to_world(state.effective_projectile_speed(food))
	if food.attack_kind == FoodData.AttackKind.ORBITING_MUSHROOM:
		speed = state.effective_orbit_angular_speed(food)
	elif food.attack_kind == FoodData.AttackKind.CARROT_SWEEP:
		# Excel用环绕角速度维护扫掠节拍；进入投射物后仍换算为弧线切向线速度。
		speed = (
			Playfield.design_to_world(food.sweep_radius)
			* state.effective_orbit_angular_speed(food)
		)
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
	var burst: Array[Dictionary] = []
	for index: int in range(count):
		var direction: Vector3 = base_direction
		var spread: float = (float(index) - float(count - 1) * 0.5) * 0.075
		direction = direction.rotated(Vector3.UP, spread)
		# 蘑菇使用角度相位，胡萝卜复用同一相位在往返周期内错峰。
		var orbit_phase: float = TAU * float(index) / float(count)
		burst.append({
			"direction": _vector_payload(direction),
			"orbit_phase": orbit_phase,
		})
	run.spawn_projectile_burst(
		cart_position + Vector3(0.0, 0.0, -1.35),
		burst,
		food,
		amount,
		speed,
		radius,
		target,
		false,
		player_slot
	)


# 进化取得后等待完整间隔，再额外发射一根固定份数的巨型法棍。
func _tick_giant_baguette(food: FoodData, delta: float) -> void:
	if not state.has_food_evolution(&"baguette_giant"):
		_giant_baguette_enabled = false
		_giant_baguette_cooldown = 0.0
		return
	var interval: float = state.effective_giant_baguette_interval()
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
	run.spawn_projectile_burst(
		cart_position + Vector3(0.0, 0.0, -1.35),
		[{
			"direction": _vector_payload(Vector3.FORWARD),
			"orbit_phase": 0.0,
		}],
		food,
		MultiplayerRules.ghost_output(
			state.effective_satisfaction(food) * state.baguette_giant_satisfaction_multiplier,
			run.output_multiplier_for_slot(player_slot)
		),
		Playfield.design_to_world(state.effective_projectile_speed(food)),
		Playfield.design_to_world(state.effective_projectile_radius(food)),
		null,
		true,
		player_slot
	)


func _vector_payload(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}
