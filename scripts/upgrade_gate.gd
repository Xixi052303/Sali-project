class_name UpgradeGate
extends Node2D

const INK: Color = Color("#241f1a")
const LEFT_PANEL: Rect2 = Rect2(66.0, -72.0, 288.0, 144.0)
const RIGHT_PANEL: Rect2 = Rect2(366.0, -72.0, 288.0, 144.0)
const SIDE_DIVIDER_X: float = 360.0

var run: RunController
var left_upgrade: UpgradeData
var right_upgrade: UpgradeData
var start_food_gate: bool = false
var resolved: bool = false
var move_speed: float = 250.0
var spawn_index: int = 0
var baseline_appetite: float = 1.0
# 基础血量负责撞门损伤并公开显示；隐藏血量只负责基础层击破后的奖励升值。
var left_base_health: float = 0.0
var right_base_health: float = 0.0
var left_upgrade_health: float = 0.0
var right_upgrade_health: float = 0.0

# 两个目标节点只用于稳定区分左右门的瞄准与投射物命中记录。
var _left_target: Node2D
var _right_target: Node2D
var _left_hit_feedback: float = 0.0
var _right_hit_feedback: float = 0.0


# 生成时锁定门的基准胃口，并分别建立公开基础层和隐藏升值层。
func configure(
	run_controller: RunController,
	left: UpgradeData,
	right: UpgradeData,
	is_start_gate: bool = false,
	gate_baseline_appetite: float = 1.0,
	index: int = 0
) -> void:
	run = run_controller
	left_upgrade = left
	right_upgrade = right
	start_food_gate = is_start_gate
	baseline_appetite = maxf(1.0, gate_baseline_appetite)
	spawn_index = index
	position = Vector2.ZERO
	_ensure_targets()
	if not start_food_gate:
		left_base_health = baseline_appetite
		right_base_health = baseline_appetite
		left_upgrade_health = baseline_appetite * (1.0 - left_upgrade.value_ratio)
		right_upgrade_health = baseline_appetite * (1.0 - right_upgrade.value_ratio)
	queue_redraw()


func _process(delta: float) -> void:
	if run == null or resolved:
		return
	if _left_hit_feedback > 0.0 or _right_hit_feedback > 0.0:
		_left_hit_feedback = maxf(0.0, _left_hit_feedback - delta)
		_right_hit_feedback = maxf(0.0, _right_hit_feedback - delta)
		queue_redraw()
	if run.is_world_scrolling():
		position.y += move_speed * delta
	if position.y >= Playfield.CART_Y:
		resolved = true
		var cart_x: float = run.cart.position.x
		run.on_gate_selected(
			selected_upgrade_for_x(cart_x),
			start_food_gate,
			selected_base_health_for_x(cart_x)
		)
		queue_free()


# 返回餐车当前半区仍可强化的门目标，满额侧不会自动改打另一侧。
func target_for_cart_x(cart_x: float) -> Node2D:
	if start_food_gate or resolved:
		return null
	var use_left: bool = cart_x < SIDE_DIVIDER_X
	if not side_is_attackable(use_left):
		return null
	return _left_target if use_left else _right_target


# 中心点固定归右侧，越线结算始终只返回一个门选项。
func selected_upgrade_for_x(cart_x: float) -> UpgradeData:
	return left_upgrade if cart_x < SIDE_DIVIDER_X else right_upgrade


func selected_base_health_for_x(cart_x: float) -> float:
	return left_base_health if cart_x < SIDE_DIVIDER_X else right_base_health


# 投射物按实际所在面板结算，左右两侧的命中历史互不共享。
func try_receive_projectile(projectile: FoodProjectile) -> bool:
	if start_food_gate or resolved or projectile == null:
		return false
	var local_position: Vector2 = to_local(projectile.global_position)
	var hit_left: bool = local_position.x < SIDE_DIVIDER_X
	var panel: Rect2 = LEFT_PANEL if hit_left else RIGHT_PANEL
	if not panel.grow(projectile.radius).has_point(local_position):
		return false
	if not side_is_attackable(hit_left):
		return false
	var target: Node2D = _left_target if hit_left else _right_target
	if not projectile.can_hit(target):
		return false
	receive_damage(hit_left, projectile.satisfaction)
	return projectile.register_hit(target)


# 伤害必须先击破公开基础层；后续攻击才消耗隐藏层并提高奖励。
func receive_damage(hit_left: bool, amount: float) -> void:
	if start_food_gate or resolved or amount <= 0.0 or not side_is_attackable(hit_left):
		return
	if hit_left:
		if left_base_health > 0.0001:
			left_base_health = maxf(0.0, left_base_health - amount)
		else:
			left_upgrade_health = maxf(0.0, left_upgrade_health - amount)
			left_upgrade.set_value_ratio(1.0 - left_upgrade_health / baseline_appetite)
		_left_hit_feedback = 0.12
	else:
		if right_base_health > 0.0001:
			right_base_health = maxf(0.0, right_base_health - amount)
		else:
			right_upgrade_health = maxf(0.0, right_upgrade_health - amount)
			right_upgrade.set_value_ratio(1.0 - right_upgrade_health / baseline_appetite)
		_right_hit_feedback = 0.12
	queue_redraw()


func side_is_attackable(left_side: bool) -> bool:
	if start_food_gate:
		return false
	if left_side:
		return left_base_health > 0.0001 or left_upgrade_health > 0.0001
	return right_base_health > 0.0001 or right_upgrade_health > 0.0001


func travel_speed() -> float:
	return move_speed


func _draw() -> void:
	_draw_panel(LEFT_PANEL, left_upgrade, Color("#3d513d"), true)
	_draw_panel(RIGHT_PANEL, right_upgrade, Color("#694035"), false)
	draw_line(Vector2(SIDE_DIVIDER_X, -82.0), Vector2(SIDE_DIVIDER_X, 82.0), Color("#efbd4b"), 7.0)
	if not start_food_gate:
		_draw_base_health(LEFT_PANEL, left_base_health)
		_draw_base_health(RIGHT_PANEL, right_base_health)


func _draw_panel(rect: Rect2, upgrade: UpgradeData, color: Color, left_side: bool) -> void:
	if upgrade == null:
		return
	var feedback: float = _left_hit_feedback if left_side else _right_hit_feedback
	var panel_color: Color = color.lightened(0.35) if feedback > 0.0 else color
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = panel_color
	style.border_color = Color.WHITE if feedback > 0.0 else upgrade.rarity_color
	style.set_border_width_all(7 if feedback > 0.0 else 5)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	draw_style_box(style, rect)
	var font: Font = ThemeDB.fallback_font
	var title: String = "土豆 Lv.1" if start_food_gate else upgrade.display_name
	var maximum_durability: float = 100.0 if run == null else run.state.maximum_durability
	var value_text: String = "选择开局食材" if start_food_gate else upgrade.effect_text(maximum_durability)
	draw_string(font, rect.position + Vector2(20.0, 39.0), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40.0, 24, Color.WHITE)
	draw_string(font, rect.position + Vector2(20.0, 82.0), value_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40.0, 18, Color("#f0dfb6"))
	if start_food_gate:
		return
	draw_string(font, rect.position + Vector2(20.0, 121.0), upgrade.rarity_name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40.0, 17, upgrade.rarity_color)


func _draw_base_health(rect: Rect2, health: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var health_text: String = str(ceili(health))
	var text_position: Vector2 = Vector2(rect.position.x, rect.position.y - 14.0)
	for offset: Vector2 in [Vector2(-2.0, 0.0), Vector2(2.0, 0.0), Vector2(0.0, -2.0), Vector2(0.0, 2.0)]:
		draw_string(font, text_position + offset, health_text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 30, INK)
	draw_string(font, text_position, health_text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 30, Color("#ffe09a"))


func _ensure_targets() -> void:
	if _left_target == null:
		_left_target = Node2D.new()
		_left_target.name = "LeftTarget"
		_left_target.position = Vector2(210.0, 0.0)
		add_child(_left_target)
	if _right_target == null:
		_right_target = Node2D.new()
		_right_target.name = "RightTarget"
		_right_target.position = Vector2(510.0, 0.0)
		add_child(_right_target)
