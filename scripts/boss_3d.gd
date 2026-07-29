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

const COMBAT_DISTANCE_FROM_CART: float = 8.0
const ENTRY_TRAVEL_DISTANCE: float = 4.2
const LINE_ATTACK_ANIMATION: StringName = &"line_attack"
const AREA_ATTACK_ANIMATION: StringName = &"area_attack"

var data: BossPatternData
var run: RunController3D
var remaining_appetite: float = 0.0
# 登场时锁定最大胃口，避免基准曲线在 Boss 战中继续改变血量与显示上限。
var maximum_appetite: float = 0.0
var active: bool = false
var _state: State = State.ENTER
var _state_time: float = 0.0
var _attack_index: int = 0
# 每次攻击开始时锁定完整道路坐标，动画锚点与代码命中共享同一目标快照。
var _locked_target_position: Vector3 = Vector3(3.6, 0.0, Playfield.CART_Z)
var _direction: float = 1.0
var _combat_z: float = 3.0
@onready var _appetite_label: Label3D = %AppetiteLabel
@onready var _line_attack_anchor: Node3D = %LineAttackAnchor
@onready var _area_attack_anchor: Node3D = %AreaAttackAnchor
@onready var _telegraph_line: MeshInstance3D = %LineTelegraph
@onready var _telegraph_area: MeshInstance3D = %AreaTelegraph
@onready var _line_impact_marker: Marker3D = %LineImpactMarker
@onready var _animation_player: AnimationPlayer = %AnimationPlayer
@onready var _line_box: BoxMesh = _telegraph_line.mesh as BoxMesh


# Boss 登场时把当前基准胃口与资源倍率结算为本场固定胃口。
func configure(source_data: BossPatternData, run_controller: RunController3D, baseline_appetite: float) -> void:
	_resolve_visual_nodes()
	data = source_data
	run = run_controller
	maximum_appetite = data.appetite_at(baseline_appetite)
	remaining_appetite = maximum_appetite
	# 战位跟随编辑器中的餐车纵坐标，确保当前土豆与法棍基础射程都能参与满足。
	_combat_z = run.cart_destination_z() - COMBAT_DISTANCE_FROM_CART
	position = Vector3(3.6, 0.0, _combat_z - ENTRY_TRAVEL_DISTANCE)
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
			position.z = move_toward(position.z, _combat_z, 3.0 * delta)
			if position.z >= _combat_z - 0.01:
				_change_state(State.MOVE)
		State.MOVE:
			position.x += _direction * Playfield.design_to_world(data.move_speed) * delta
			if position.x < 1.8 or position.x > 5.4:
				_direction *= -1.0
				position.x = clampf(position.x, 1.8, 5.4)
			if _state_time >= 2.2:
				_locked_target_position = run.cart.position
				_change_state(State.TELEGRAPH_LINE if _attack_index % 2 == 0 else State.TELEGRAPH_AREA)
		State.TELEGRAPH_LINE:
			if _state_time >= data.telegraph_duration:
				if absf(run.cart.position.x - _locked_target_position.x) <= 0.54:
					run.damage_cart(remaining_appetite * data.line_attack_ratio, "Boss直线投掷")
				_finish_attack()
		State.TELEGRAPH_AREA:
			if _state_time >= data.telegraph_duration:
				if absf(run.cart.position.x - _locked_target_position.x) <= 1.1:
					run.damage_cart(remaining_appetite * data.area_attack_ratio, "Boss范围攻击")
				_finish_attack()
		State.RECOVER:
			if _state_time >= data.recovery_duration:
				_change_state(State.MOVE)
		State.DONE:
			pass


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
	return 1.08


func _resolve_visual_nodes() -> void:
	if _animation_player != null:
		return
	_appetite_label = get_node("AppetiteLabel") as Label3D
	_line_attack_anchor = get_node("LineAttackAnchor") as Node3D
	_area_attack_anchor = get_node("AreaAttackAnchor") as Node3D
	_telegraph_line = get_node("LineAttackAnchor/LineAttackRig/LineTelegraph") as MeshInstance3D
	_telegraph_area = get_node("AreaAttackAnchor/AreaAttackRig/AreaTelegraph") as MeshInstance3D
	_line_impact_marker = get_node("LineAttackAnchor/LineAttackRig/LineImpactMarker") as Marker3D
	_animation_player = get_node("AnimationPlayer") as AnimationPlayer
	_line_box = _telegraph_line.mesh as BoxMesh


func _finish_attack() -> void:
	_reset_attack_animation()
	_attack_index += 1
	_change_state(State.RECOVER)


func _change_state(next_state: State) -> void:
	_state = next_state
	_state_time = 0.0
	if next_state == State.TELEGRAPH_LINE:
		_play_attack_animation(LINE_ATTACK_ANIMATION)
	elif next_state == State.TELEGRAPH_AREA:
		_play_attack_animation(AREA_ATTACK_ANIMATION)
	elif next_state == State.DONE:
		_reset_attack_animation()


func _configure_visual() -> void:
	_appetite_label.text = str(ceili(remaining_appetite))
	_reset_attack_animation()


# RESET轨道是动画编辑器与运行时共同认可的基础姿态，避免攻击结束时停在半帧缩放上。
func _reset_attack_animation() -> void:
	_animation_player.stop()
	_animation_player.play(&"RESET")
	_animation_player.advance(0.0)
	_animation_player.stop()


# 代码只放置动态锚点；轨迹节点的局部位移、缩放和显隐完全交给动画资源。
func _play_attack_animation(animation_name: StringName) -> void:
	var target_offset: Vector3 = _locked_target_position - position
	if animation_name == LINE_ATTACK_ANIMATION:
		_line_attack_anchor.position = Vector3(target_offset.x, 0.02, 0.0)
		_line_box.size = Vector3(1.08, 0.03, absf(target_offset.z))
		_telegraph_line.position = Vector3(0.0, 0.0, target_offset.z * 0.5)
		_line_impact_marker.position = Vector3(0.0, 0.0, target_offset.z)
	else:
		_area_attack_anchor.position = Vector3(target_offset.x, 0.02, target_offset.z)
	var attack_animation: Animation = _animation_player.get_animation(animation_name)
	var authored_duration: float = attack_animation.length if attack_animation != null else 1.0
	var animation_speed: float = authored_duration / maxf(0.001, data.telegraph_duration)
	_animation_player.play(animation_name, -1.0, animation_speed)
