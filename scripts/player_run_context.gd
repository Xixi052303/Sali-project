class_name PlayerRunContext
extends RefCounted

## 保存单个玩家的局内状态；共享敌人与门由 RunController3D 持有。

enum LifeState {
	ALIVE,
	GHOST,
}

var slot: int = 1
var peer_id: int = 1
var state: RunState
var cart: Cart3D
var weapon_controller: WeaponController3D
var life_state: LifeState = LifeState.ALIVE
var respawn_remaining: float = 0.0
var pending_repair_points: float = 0.0
var last_input_sequence: int = 0
# 局内个人死亡累计与幽灵停留时间，用于复活档位和结算记录。
var death_count: int = 0
var ghost_elapsed_seconds: float = 0.0


func configure(
	player_slot: int,
	player_peer_id: int,
	player_state: RunState,
	player_cart: Cart3D,
	player_weapon_controller: WeaponController3D
) -> void:
	slot = player_slot
	peer_id = player_peer_id
	state = player_state
	cart = player_cart
	weapon_controller = player_weapon_controller
	life_state = LifeState.ALIVE
	respawn_remaining = 0.0
	pending_repair_points = 0.0
	last_input_sequence = 0
	death_count = 0
	ghost_elapsed_seconds = 0.0


func is_ghost() -> bool:
	return life_state == LifeState.GHOST


func can_receive_damage() -> bool:
	return life_state == LifeState.ALIVE and state != null and state.current_durability > 0.0


func output_multiplier(ghost_damage_multiplier: float) -> float:
	return ghost_damage_multiplier if is_ghost() else 1.0


func enter_ghost(respawn_seconds: float) -> void:
	life_state = LifeState.GHOST
	respawn_remaining = maxf(0.0, respawn_seconds)
	death_count += 1
	if state != null:
		state.current_durability = 0.0
		state.temporary_shield = 0.0
		state.durability_changed.emit(
			state.current_durability,
			state.maximum_durability,
			state.temporary_shield
		)
	if cart != null:
		cart.set_ghost_visual(true)


func cache_repair(points: float) -> void:
	pending_repair_points += maxf(0.0, points)


func tick_respawn(delta: float) -> bool:
	if not is_ghost():
		return false
	var elapsed: float = maxf(0.0, delta)
	ghost_elapsed_seconds += elapsed
	respawn_remaining = maxf(0.0, respawn_remaining - elapsed)
	return respawn_remaining <= 0.0


func respawn(
	initial_ratio: float,
	invincibility_seconds: float = RunState.DEFAULT_RESPAWN_INVINCIBILITY_SECONDS
) -> void:
	if state == null:
		return
	life_state = LifeState.ALIVE
	state.current_durability = state.maximum_durability * clampf(initial_ratio, 0.0, 1.0)
	state.temporary_shield = 0.0
	if pending_repair_points > 0.0:
		state.repair(pending_repair_points)
	pending_repair_points = 0.0
	respawn_remaining = 0.0
	state.durability_changed.emit(
		state.current_durability,
		state.maximum_durability,
		state.temporary_shield
	)
	if cart != null:
		cart.set_ghost_visual(false)
		cart.begin_respawn_protection(invincibility_seconds)
