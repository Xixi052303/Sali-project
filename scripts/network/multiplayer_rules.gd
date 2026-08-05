class_name MultiplayerRules
extends RefCounted

## 纯规则计算集中在这里，便于房主结算和离线单元测试共用同一份公式。

static func scale_enemy_appetite(base_appetite: float, player_count: int) -> float:
	return maxf(0.0, base_appetite) * float(maxi(1, player_count))


static func per_player_damage(shared_remaining: float, player_count: int) -> float:
	return maxf(0.0, shared_remaining) / float(maxi(1, player_count))


static func respawn_delay(
	base_seconds: float,
	increment_seconds: float,
	max_seconds: float,
	death_count_before_batch: int
) -> float:
	return minf(
		maxf(0.0, max_seconds),
		maxf(0.0, base_seconds)
		+ maxf(0.0, increment_seconds) * float(maxi(0, death_count_before_batch))
	)


static func ghost_output(base_amount: float, ghost_multiplier: float) -> float:
	return maxf(0.0, base_amount) * clampf(ghost_multiplier, 0.0, 1.0)




static func ghost_can_claim_normal_gate(base_health: float) -> bool:
	return maxf(0.0, base_health) <= 0.0001


static func all_players_ghost(life_states: Array[bool]) -> bool:
	if life_states.is_empty():
		return false
	for is_ghost: bool in life_states:
		if not is_ghost:
			return false
	return true
