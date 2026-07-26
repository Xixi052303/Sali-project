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
var left_max_health: float = 0.0
var right_max_health: float = 0.0
var left_health: float = 0.0
var right_health: float = 0.0

# 两个目标节点只用于稳定区分左右门的瞄准与投射物命中记录。
var _left_target: Node2D
var _right_target: Node2D
var _left_hit_feedback: float = 0.0
var _right_hit_feedback: float = 0.0


# 生成时锁定门的基准胃口，后续伤害只改变各侧奖励百分位。
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
		left_max_health = baseline_appetite * (1.0 - left_upgrade.value_ratio)
		right_max_health = baseline_appetite * (1.0 - right_upgrade.value_ratio)
		left_health = left_max_health
		right_health = right_max_health
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
		var chose_left: bool = run.cart.position.x < SIDE_DIVIDER_X
		run.on_gate_selected(left_upgrade if chose_left else right_upgrade, start_food_gate)
		queue_free()


# 返回餐车当前半区仍可强化的门目标，满额侧不会自动改打另一侧。
func target_for_cart_x(cart_x: float) -> Node2D:
	if start_food_gate or resolved:
		return null
	var use_left: bool = cart_x < SIDE_DIVIDER_X
	if not side_is_attackable(use_left):
		return null
	return _left_target if use_left else _right_target


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


# 门血减少时，奖励百分位按剩余血量连续映射到完整数值区间。
func receive_damage(hit_left: bool, amount: float) -> void:
	if start_food_gate or resolved or amount <= 0.0 or not side_is_attackable(hit_left):
		return
	if hit_left:
		left_health = maxf(0.0, left_health - amount)
		left_upgrade.set_value_ratio(1.0 - left_health / baseline_appetite)
		_left_hit_feedback = 0.12
	else:
		right_health = maxf(0.0, right_health - amount)
		right_upgrade.set_value_ratio(1.0 - right_health / baseline_appetite)
		_right_hit_feedback = 0.12
	queue_redraw()


func side_is_attackable(left_side: bool) -> bool:
	if start_food_gate:
		return false
	return left_health > 0.0001 if left_side else right_health > 0.0001


func travel_speed() -> float:
	return move_speed


func _draw() -> void:
	_draw_panel(LEFT_PANEL, left_upgrade, Color("#3d513d"), true)
	_draw_panel(RIGHT_PANEL, right_upgrade, Color("#694035"), false)
	draw_line(Vector2(SIDE_DIVIDER_X, -82.0), Vector2(SIDE_DIVIDER_X, 82.0), Color("#efbd4b"), 7.0)


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
	draw_string(font, rect.position + Vector2(20.0, 34.0), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40.0, 24, Color.WHITE)
	draw_string(font, rect.position + Vector2(20.0, 69.0), value_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40.0, 18, Color("#f0dfb6"))
	if start_food_gate:
		return
	var current_health: float = left_health if left_side else right_health
	var maximum_health: float = left_max_health if left_side else right_max_health
	var health_text: String = "已强化至上限" if current_health <= 0.0001 else "门耐久 %d / %d" % [ceili(current_health), ceili(maximum_health)]
	var detail_size: int = 18 if feedback > 0.0 else 16
	draw_string(font, rect.position + Vector2(20.0, 100.0), upgrade.rarity_name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40.0, 16, upgrade.rarity_color)
	draw_string(font, rect.position + Vector2(20.0, 128.0), health_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40.0, detail_size, Color("#fff3d0"))


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
