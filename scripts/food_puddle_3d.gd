class_name FoodPuddle3D
extends Node3D

const MISS_DISAPPEAR_DURATION: float = 0.2
const APPEAR_DURATION: float = 0.12
const APPEAR_START_SCALE: float = 0.08
const VISUAL_CENTER_Y: float = 0.04
const MAXIMUM_VISUAL_RANGE_SCALE: float = 1.5
const RANGE_OUTLINE_WIDTH: float = 0.035
const LIQUID_MODEL_SIZE: Vector3 = Vector3(0.998046875, 0.146484375, 0.990234375)

var run: RunController3D
var food_id: StringName = &"egg"
var derived_attack_id: StringName = &"egg_puddle"
var satisfaction: float = 0.0
var radius: float = 0.16
var _lifetime_remaining: float = 1.0
var _tick_interval: float = 0.5
var _target_cooldowns: Dictionary[int, float] = {}
var _observed_target_ids: Dictionary[int, bool] = {}
var _range_scale: float = 1.0
var _disappearing: bool = false
# 蛋液生成时的短Tween；不参与伤害计时，只负责视觉入场。
var _appearance_tween: Tween
# 蛋液包装场景的编辑器缩放与偏移作为基准，运行时只叠加有效范围尺寸。
var _visual_nodes_resolved: bool = false
var _liquid_visual_base_scale: Vector3 = Vector3.ONE
var _liquid_visual_base_position: Vector3 = Vector3.ZERO

@onready var _liquid_visual: Node3D = %LiquidVisual
@onready var _range_circle_outline: MeshInstance3D = %RangeCircleOutline


# 蛋液固定在命中位置，按世界滚动同步道路并维护每个目标自己的周期。
func configure(
	run_controller: RunController3D,
	start_position: Vector3,
	source_food: FoodData,
	derived_attack: FoodData,
	amount: float,
	hit_radius_value: float,
	lifetime: float,
	tick_interval: float
) -> void:
	_resolve_visual_nodes()
	run = run_controller
	position = start_position
	food_id = source_food.id
	derived_attack_id = derived_attack.id
	satisfaction = amount
	radius = hit_radius_value
	_lifetime_remaining = maxf(0.01, lifetime)
	_tick_interval = maxf(0.01, tick_interval)
	_range_scale = radius / maxf(
		0.001,
		Playfield.design_to_world(derived_attack.projectile_radius)
	)
	_configure_visual()
	_play_appear_animation()


func _resolve_visual_nodes() -> void:
	if _visual_nodes_resolved:
		return
	_liquid_visual = get_node("LiquidVisual") as Node3D
	_range_circle_outline = get_node("RangeCircleOutline") as MeshInstance3D
	_liquid_visual_base_scale = _liquid_visual.scale
	_liquid_visual_base_position = _liquid_visual.position
	_visual_nodes_resolved = true


func _process(delta: float) -> void:
	if run == null:
		queue_free()
		return
	_lifetime_remaining -= delta
	if _lifetime_remaining <= 0.0:
		_begin_miss_disappear()
		return
	if run.is_world_scrolling():
		position.z += run.world_scroll_speed * delta
	for target_id: int in _target_cooldowns.keys():
		_target_cooldowns[target_id] = maxf(
			0.0,
			_target_cooldowns[target_id] - delta
		)
	run.resolve_puddle_hits(self)


func begin_contact_scan() -> void:
	_observed_target_ids.clear()


# 返回本次扫描是否应对目标结算伤害，并在结算后启动下一次周期。
func observe_target(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var target_id: int = target.get_instance_id()
	_observed_target_ids[target_id] = true
	var cooldown: float = _target_cooldowns.get(target_id, 0.0)
	if cooldown > 0.000001:
		return false
	_target_cooldowns[target_id] = _tick_interval
	return true


# 命中生成时已经立即结算一次，随后从完整0.5秒周期开始。
func prime_target(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_target_cooldowns[target.get_instance_id()] = _tick_interval


func end_contact_scan() -> void:
	for target_id: int in _target_cooldowns.keys():
		if not _observed_target_ids.has(target_id):
			_target_cooldowns.erase(target_id)
	_observed_target_ids.clear()


func overlaps_target(target_position: Vector3, target_radius: float) -> bool:
	var puddle_position: Vector3 = run.logic_position(self)
	return Vector2(puddle_position.x, puddle_position.z).distance_to(
		Vector2(target_position.x, target_position.z)
	) <= radius + target_radius


# 蛋液命中后立即以极小尺寸出现，在短时间内放大到完整范围，保留首跳即时结算。
func _play_appear_animation() -> void:
	if not is_inside_tree():
		scale = Vector3.ONE
		return
	if _appearance_tween != null:
		_appearance_tween.kill()
	scale = Vector3.ONE * APPEAR_START_SCALE
	_appearance_tween = create_tween()
	_appearance_tween.set_trans(Tween.TRANS_QUAD)
	_appearance_tween.set_ease(Tween.EASE_OUT)
	_appearance_tween.tween_property(self, "scale", Vector3.ONE, APPEAR_DURATION)


func _configure_visual() -> void:
	var visual_range_scale: float = minf(_range_scale, MAXIMUM_VISUAL_RANGE_SCALE)
	var diameter: float = maxf(0.12, radius / maxf(0.001, _range_scale) * visual_range_scale * 2.0)
	var liquid_scale: float = diameter / maxf(LIQUID_MODEL_SIZE.x, LIQUID_MODEL_SIZE.z)
	_liquid_visual.scale = _liquid_visual_base_scale * Vector3.ONE * liquid_scale
	_liquid_visual.position = _liquid_visual_base_position + Vector3(
		0.0,
		VISUAL_CENTER_Y,
		0.0
	)
	_range_circle_outline.visible = false
	if _range_scale > MAXIMUM_VISUAL_RANGE_SCALE:
		var torus: TorusMesh = _range_circle_outline.mesh as TorusMesh
		var outer_radius: float = maxf(RANGE_OUTLINE_WIDTH * 2.0, radius)
		var inner_radius: float = maxf(RANGE_OUTLINE_WIDTH, outer_radius - RANGE_OUTLINE_WIDTH)
		torus.outer_radius = outer_radius
		torus.inner_radius = inner_radius
		_range_circle_outline.visible = true


func _begin_miss_disappear() -> void:
	if _disappearing:
		return
	_disappearing = true
	if _appearance_tween != null:
		_appearance_tween.kill()
	set_process(false)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, MISS_DISAPPEAR_DURATION)
	_tween_visual_transparency(tween, _liquid_visual)
	_tween_visual_transparency(tween, _range_circle_outline)
	tween.chain().tween_callback(queue_free)


func _tween_visual_transparency(tween: Tween, visual: Node3D) -> void:
	if visual is GeometryInstance3D:
		tween.tween_property(
			visual as GeometryInstance3D,
			"transparency",
			1.0,
			MISS_DISAPPEAR_DURATION
		)
	for child: Node in visual.find_children("*", "GeometryInstance3D", true, false):
		var geometry: GeometryInstance3D = child as GeometryInstance3D
		if geometry != null:
			tween.tween_property(
				geometry,
				"transparency",
				1.0,
				MISS_DISAPPEAR_DURATION
			)
