class_name PrototypeBoss
extends Node2D

signal satisfied
signal appetite_changed(current: float, maximum: float)

enum State {
	ENTER,
	MOVE,
	TELEGRAPH_LINE,
	TELEGRAPH_AREA,
	RECOVER,
	DONE,
}

const INK: Color = Color("#241f1a")

var data: BossPatternData
var run: RunController
var remaining_appetite: float = 0.0
# 登场时锁定最大胃口，避免基准曲线在 Boss 战中继续改变血量与显示上限。
var maximum_appetite: float = 0.0
var active: bool = false
var _state: State = State.ENTER
var _state_time: float = 0.0
var _attack_index: int = 0
var _locked_target_x: float = 360.0
var _direction: float = 1.0


# Boss 登场时把当前基准胃口与资源倍率结算为本场固定胃口。
func configure(source_data: BossPatternData, run_controller: RunController, baseline_appetite: float) -> void:
	data = source_data
	run = run_controller
	maximum_appetite = data.appetite_at(baseline_appetite)
	remaining_appetite = maximum_appetite
	position = Vector2(360.0, -120.0)
	active = true
	_state = State.ENTER
	_state_time = 0.0
	appetite_changed.emit(remaining_appetite, maximum_appetite)
	queue_redraw()


func _process(delta: float) -> void:
	if not active or data == null or run == null:
		return
	_state_time += delta
	match _state:
		State.ENTER:
			position.y = move_toward(position.y, 300.0, 300.0 * delta)
			if position.y >= 299.0:
				_change_state(State.MOVE)
		State.MOVE:
			position.x += _direction * data.move_speed * delta
			if position.x < 180.0 or position.x > 540.0:
				_direction *= -1.0
				position.x = clampf(position.x, 180.0, 540.0)
			if _state_time >= 2.2:
				_locked_target_x = run.cart.position.x
				_change_state(State.TELEGRAPH_LINE if _attack_index % 2 == 0 else State.TELEGRAPH_AREA)
		State.TELEGRAPH_LINE:
			if _state_time >= data.telegraph_duration:
				if absf(run.cart.position.x - _locked_target_x) <= 54.0:
					run.damage_cart(remaining_appetite * data.line_attack_ratio, "Boss直线投掷")
				_finish_attack()
		State.TELEGRAPH_AREA:
			if _state_time >= data.telegraph_duration:
				if absf(run.cart.position.x - _locked_target_x) <= 110.0:
					run.damage_cart(remaining_appetite * data.area_attack_ratio, "Boss范围攻击")
				_finish_attack()
		State.RECOVER:
			if _state_time >= data.recovery_duration:
				_change_state(State.MOVE)
		State.DONE:
			pass
	queue_redraw()


func receive_satisfaction(amount: float) -> void:
	if not active or amount <= 0.0:
		return
	remaining_appetite = maxf(0.0, remaining_appetite - amount)
	appetite_changed.emit(remaining_appetite, maximum_appetite)
	if remaining_appetite <= 0.0:
		active = false
		_change_state(State.DONE)
		satisfied.emit()
	queue_redraw()


func hit_radius() -> float:
	return 108.0


func _finish_attack() -> void:
	_attack_index += 1
	_change_state(State.RECOVER)


func _change_state(next_state: State) -> void:
	_state = next_state
	_state_time = 0.0


func _draw() -> void:
	if data == null:
		return
	if _state == State.TELEGRAPH_LINE:
		var progress: float = clampf(_state_time / data.telegraph_duration, 0.0, 1.0)
		draw_rect(Rect2(_locked_target_x - position.x - 54.0, 70.0, 108.0, Playfield.CART_Y - position.y), Color(0.9, 0.2, 0.08, 0.12 + progress * 0.28))
		for y: float in range(90, int(Playfield.CART_Y - position.y), 44):
			draw_line(Vector2(_locked_target_x - position.x - 50.0, y), Vector2(_locked_target_x - position.x + 50.0, y + 26.0), Color("#e84f27"), 5.0)
	elif _state == State.TELEGRAPH_AREA:
		var progress: float = clampf(_state_time / data.telegraph_duration, 0.0, 1.0)
		draw_circle(Vector2(_locked_target_x - position.x, Playfield.CART_Y - position.y), 110.0, Color(0.9, 0.2, 0.08, 0.12 + progress * 0.3))
		draw_arc(Vector2(_locked_target_x - position.x, Playfield.CART_Y - position.y), 110.0, 0.0, TAU, 48, Color("#e84f27"), 8.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-96.0, -28.0),
		Vector2(-62.0, -86.0),
		Vector2(0.0, -104.0),
		Vector2(66.0, -82.0),
		Vector2(100.0, -22.0),
		Vector2(82.0, 64.0),
		Vector2(-78.0, 64.0),
	]), data.body_color)
	draw_polyline(PackedVector2Array([
		Vector2(-96.0, -28.0),
		Vector2(-62.0, -86.0),
		Vector2(0.0, -104.0),
		Vector2(66.0, -82.0),
		Vector2(100.0, -22.0),
		Vector2(82.0, 64.0),
		Vector2(-78.0, 64.0),
		Vector2(-96.0, -28.0),
	]), INK, 7.0)
	draw_circle(Vector2(-34.0, -22.0), 11.0, Color("#efbd4b"))
	draw_circle(Vector2(38.0, -22.0), 11.0, Color("#efbd4b"))
	draw_line(Vector2(-48.0, -46.0), Vector2(-20.0, -35.0), INK, 7.0)
	draw_line(Vector2(52.0, -46.0), Vector2(22.0, -35.0), INK, 7.0)
	draw_arc(Vector2(0.0, 21.0), 32.0, 0.2, 2.95, 24, INK, 7.0)
	for x: float in range(-76, 76, 30):
		draw_line(Vector2(x, -72.0), Vector2(x + 42.0, 52.0), Color(0.12, 0.1, 0.09, 0.35), 3.0)
	var font: Font = ThemeDB.fallback_font
	var appetite_text: String = str(ceili(remaining_appetite))
	var text_position: Vector2 = Vector2(-130.0, -130.0)
	for offset: Vector2 in [Vector2(-3.0, 0.0), Vector2(3.0, 0.0), Vector2(0.0, -3.0), Vector2(0.0, 3.0)]:
		draw_string(font, text_position + offset, appetite_text, HORIZONTAL_ALIGNMENT_CENTER, 260.0, 38, INK)
	draw_string(font, text_position, appetite_text, HORIZONTAL_ALIGNMENT_CENTER, 260.0, 38, Color("#ffe09a"))
