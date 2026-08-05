class_name CookingIndicator
extends Control

const ICON_PATHS: Dictionary[StringName, String] = {
	&"potato": "res://assets/ui/food_icons/potato.svg",
	&"baguette": "res://assets/ui/food_icons/baguette.svg",
	&"mushroom": "res://assets/ui/food_icons/mushroom.svg",
}
const RING_CENTER: Vector2 = Vector2(38.0, 38.0)
const RING_RADIUS: float = 31.0
const RING_WIDTH: float = 6.0

@onready var _icon: TextureRect = %Icon
@onready var _fallback_label: Label = %FallbackLabel
@onready var _remaining_label: Label = %RemainingLabel
@onready var _level_label: Label = %LevelLabel

var food_id: StringName
var _progress: float = 1.0
var _ring_color: Color = Color("#e2b650")


func configure(food: FoodData, level: int) -> void:
	_resolve_runtime_nodes()
	food_id = food.id
	_ring_color = food.visual_color
	var icon_path: String = ICON_PATHS.get(food.id, "")
	var icon_texture: Texture2D = (
		load(icon_path) as Texture2D
		if not icon_path.is_empty() and ResourceLoader.exists(icon_path)
		else null
	)
	_icon.texture = icon_texture
	_icon.visible = icon_texture != null
	_fallback_label.visible = icon_texture == null
	_fallback_label.text = food.display_name.substr(0, 1)
	set_level(level)
	set_cooking_progress(1.0, 0.0)


func set_level(level: int) -> void:
	_resolve_runtime_nodes()
	if _level_label != null:
		_level_label.text = "Lv.%d" % maxi(1, level)


func set_cooking_progress(progress: float, remaining_seconds: float) -> void:
	_resolve_runtime_nodes()
	_progress = clampf(progress, 0.0, 1.0)
	if _remaining_label != null:
		_remaining_label.text = "%.1fs" % maxf(0.0, remaining_seconds)
	queue_redraw()


# 测试脚本可能在节点完成 ready 前配置圆环，按固定路径补齐可选控件。
func _resolve_runtime_nodes() -> void:
	if _icon == null:
		_icon = get_node_or_null("Icon") as TextureRect
	if _fallback_label == null:
		_fallback_label = get_node_or_null("FallbackLabel") as Label
	if _remaining_label == null:
		_remaining_label = get_node_or_null("RemainingLabel") as Label
	if _level_label == null:
		_level_label = get_node_or_null("LevelLabel") as Label


func _draw() -> void:
	draw_circle(RING_CENTER, RING_RADIUS + 4.0, Color("#241f1a"))
	draw_arc(
		RING_CENTER,
		RING_RADIUS,
		-PI * 0.5,
		PI * 1.5,
		48,
		Color("#594c3d"),
		RING_WIDTH,
		true
	)
	if _progress <= 0.0001:
		return
	draw_arc(
		RING_CENTER,
		RING_RADIUS,
		-PI * 0.5,
		-PI * 0.5 + TAU * _progress,
		48,
		_ring_color,
		RING_WIDTH,
		true
	)
