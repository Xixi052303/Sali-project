class_name UpgradeDrop
extends Node2D

const INK: Color = Color("#241f1a")
const PANEL_HEIGHT: float = 144.0

var run: RunController
var upgrade: UpgradeData
# 奖励门在生成后锁定升值基准、占位和次序，直到被领取或错过。
var baseline_appetite: float = 1.0
var occupied_regions: int = 2
var spawn_index: int = 0
var upgrade_health: float = 0.0
var move_speed: float = 250.0
var resolved: bool = false
# 单目标节点用于自动瞄准和投射物的同目标防重复命中。
var _target: Node2D
var _hit_feedback_remaining: float = 0.0


# 奖励门继承食客生成时的奖励百分位，只保留可升值的隐藏血量。
func configure(
	run_controller: RunController,
	upgrade_data: UpgradeData,
	start_position: Vector2,
	gate_baseline_appetite: float,
	gate_occupied_regions: int,
	index: int
) -> void:
	run = run_controller
	upgrade = upgrade_data
	baseline_appetite = maxf(1.0, gate_baseline_appetite)
	occupied_regions = clampi(gate_occupied_regions, 1, Playfield.REGION_COUNT)
	spawn_index = index
	upgrade_health = baseline_appetite * (1.0 - upgrade.value_ratio)
	global_position = start_position
	_target = Node2D.new()
	_target.name = "RewardTarget"
	add_child(_target)
	queue_redraw()


func _process(delta: float) -> void:
	if resolved or run == null or upgrade == null:
		return
	if _hit_feedback_remaining > 0.0:
		_hit_feedback_remaining = maxf(0.0, _hit_feedback_remaining - delta)
		queue_redraw()
	if run.is_world_scrolling():
		position.y += move_speed * delta
	if position.y >= Playfield.CART_Y:
		resolved = true
		if contains_cart_x(run.cart.global_position.x):
			run.on_customer_reward_gate_collected(upgrade)
		queue_free()


func target_for_cart_x(cart_x: float) -> Node2D:
	if resolved or upgrade_health <= 0.0001 or not contains_cart_x(cart_x):
		return null
	return _target


func contains_cart_x(cart_x: float) -> bool:
	var half_width: float = _panel_width() * 0.5
	return cart_x >= global_position.x - half_width and cart_x < global_position.x + half_width


func try_receive_projectile(projectile: FoodProjectile) -> bool:
	if resolved or projectile == null or upgrade_health <= 0.0001:
		return false
	var panel: Rect2 = _panel_rect()
	if not panel.grow(projectile.radius).has_point(to_local(projectile.global_position)):
		return false
	if not projectile.can_hit(_target):
		return false
	receive_damage(projectile.satisfaction)
	return projectile.register_hit(_target)


func receive_damage(amount: float) -> void:
	if resolved or amount <= 0.0 or upgrade_health <= 0.0001:
		return
	upgrade_health = maxf(0.0, upgrade_health - amount)
	upgrade.set_value_ratio(1.0 - upgrade_health / baseline_appetite)
	_hit_feedback_remaining = 0.12
	queue_redraw()


func travel_speed() -> float:
	return move_speed


func _draw() -> void:
	if upgrade == null:
		return
	var rect: Rect2 = _panel_rect()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("#47604c").lightened(0.35) if _hit_feedback_remaining > 0.0 else Color("#47604c")
	style.border_color = Color.WHITE if _hit_feedback_remaining > 0.0 else upgrade.rarity_color
	style.set_border_width_all(7 if _hit_feedback_remaining > 0.0 else 5)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	draw_style_box(style, rect)
	var font: Font = ThemeDB.fallback_font
	var padding: float = 10.0
	var text_width: float = rect.size.x - padding * 2.0
	var compact: bool = rect.size.x < 140.0
	var title_size: int = 14 if compact else 20
	var effect_size: int = 8 if compact else 16
	var rarity_size: int = 12 if compact else 16
	var maximum_durability: float = 100.0 if run == null else run.state.maximum_durability
	var effect_text: String = upgrade.effect_text(maximum_durability)
	draw_string(font, rect.position + Vector2(padding, 36.0), upgrade.display_name, HORIZONTAL_ALIGNMENT_CENTER, text_width, title_size, Color.WHITE)
	draw_string(font, rect.position + Vector2(padding, 76.0), effect_text, HORIZONTAL_ALIGNMENT_CENTER, text_width, effect_size, Color("#f0dfb6"))
	draw_string(font, rect.position + Vector2(padding, 115.0), upgrade.rarity_name, HORIZONTAL_ALIGNMENT_CENTER, text_width, rarity_size, upgrade.rarity_color)


func _panel_width() -> float:
	return maxf(82.0, float(occupied_regions) * Playfield.REGION_WIDTH - 18.0)


func _panel_rect() -> Rect2:
	var width: float = _panel_width()
	return Rect2(-width * 0.5, -PANEL_HEIGHT * 0.5, width, PANEL_HEIGHT)
