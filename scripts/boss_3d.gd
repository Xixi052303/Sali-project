class_name PrototypeBoss3D
extends Node3D

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

var data: BossPatternData
var run: RunController3D
var remaining_appetite: float = 0.0
# 登场时锁定最大胃口，避免基准曲线在 Boss 战中继续改变血量与显示上限。
var maximum_appetite: float = 0.0
var active: bool = false
var _state: State = State.ENTER
var _state_time: float = 0.0
var _attack_index: int = 0
var _locked_target_x: float = 360.0
var _direction: float = 1.0
@onready var _body_mesh: MeshInstance3D = %Body
@onready var _head_mesh: MeshInstance3D = %Head
@onready var _appetite_label: Label3D = %AppetiteLabel
@onready var _telegraph_line: MeshInstance3D = %LineTelegraph
@onready var _telegraph_area: MeshInstance3D = %AreaTelegraph
@onready var _line_box: BoxMesh = _telegraph_line.mesh as BoxMesh
@onready var _telegraph_material: StandardMaterial3D = _telegraph_line.material_override as StandardMaterial3D


# Boss 登场时把当前基准胃口与资源倍率结算为本场固定胃口。
func configure(source_data: BossPatternData, run_controller: RunController3D, baseline_appetite: float) -> void:
	_resolve_visual_nodes()
	data = source_data
	run = run_controller
	maximum_appetite = data.appetite_at(baseline_appetite)
	remaining_appetite = maximum_appetite
	position = Vector3(360.0, 0.0, -120.0)
	active = true
	_state = State.ENTER
	_state_time = 0.0
	_configure_visual()
	appetite_changed.emit(remaining_appetite, maximum_appetite)


func _process(delta: float) -> void:
	if not active or data == null or run == null:
		return
	_state_time += delta
	match _state:
		State.ENTER:
			position.z = move_toward(position.z, 300.0, 300.0 * delta)
			if position.z >= 299.0:
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
	_update_telegraph()


func receive_satisfaction(amount: float) -> void:
	if not active or amount <= 0.0:
		return
	remaining_appetite = maxf(0.0, remaining_appetite - amount)
	_appetite_label.text = str(ceili(remaining_appetite))
	appetite_changed.emit(remaining_appetite, maximum_appetite)
	if remaining_appetite <= 0.0:
		active = false
		_change_state(State.DONE)
		satisfied.emit()


func hit_radius() -> float:
	return 108.0


func _resolve_visual_nodes() -> void:
	if _body_mesh != null:
		return
	_body_mesh = get_node("Body") as MeshInstance3D
	_head_mesh = get_node("Head") as MeshInstance3D
	_appetite_label = get_node("AppetiteLabel") as Label3D
	_telegraph_line = get_node("LineTelegraph") as MeshInstance3D
	_telegraph_area = get_node("AreaTelegraph") as MeshInstance3D
	_line_box = _telegraph_line.mesh as BoxMesh
	_telegraph_material = _telegraph_line.material_override as StandardMaterial3D


func _finish_attack() -> void:
	_attack_index += 1
	_change_state(State.RECOVER)


func _change_state(next_state: State) -> void:
	_state = next_state
	_state_time = 0.0


func _configure_visual() -> void:
	var color: Color = data.body_color
	var body_material: StandardMaterial3D = _body_mesh.material_override as StandardMaterial3D
	body_material.albedo_color = color
	var head_material: StandardMaterial3D = _head_mesh.material_override as StandardMaterial3D
	head_material.albedo_color = color.lightened(0.1)
	_appetite_label.text = str(ceili(remaining_appetite))
	_telegraph_line.visible = false
	_telegraph_area.visible = false


func _update_telegraph() -> void:
	_telegraph_line.visible = _state == State.TELEGRAPH_LINE
	_telegraph_area.visible = _state == State.TELEGRAPH_AREA
	if not _telegraph_line.visible and not _telegraph_area.visible:
		return
	var progress: float = clampf(_state_time / maxf(0.001, data.telegraph_duration), 0.0, 1.0)
	_telegraph_material.albedo_color = Color(0.91, 0.22, 0.06, 0.16 + progress * 0.3)
	var target_offset_x: float = _locked_target_x - position.x
	var cart_offset_z: float = Playfield.CART_Z - position.z
	if _telegraph_line.visible:
		_line_box.size = Vector3(108.0, 3.0, absf(cart_offset_z))
		_telegraph_line.position = Vector3(target_offset_x, 2.0, cart_offset_z * 0.5)
	else:
		_telegraph_area.position = Vector3(target_offset_x, 2.0, cart_offset_z)
