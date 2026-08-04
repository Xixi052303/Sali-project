class_name GameHud
extends CanvasLayer

signal special_choice_selected(choice_id: StringName)
signal restart_requested
signal pause_requested
signal resume_requested

const INK: Color = Color("#241f1a")
const PAPER: Color = Color("#d3b77f")
const COOKING_INDICATOR_SCENE: PackedScene = preload(
	"res://scenes/cooking_indicator.tscn"
)

@onready var _root: Control = %Root
@onready var _safe_margin: MarginContainer = %SafeMargin
@onready var _durability_panel: PanelContainer = %DurabilityPanel
@onready var _durability_bar: ProgressBar = %DurabilityBar
@onready var _durability_label: Label = %DurabilityLabel
@onready var _phase_label: Label = %PhaseLabel
@onready var _time_label: Label = %TimeLabel
@onready var _pause_button: Button = %PauseButton
@onready var _cooking_area: MarginContainer = %CookingArea
@onready var _cooking_row: HFlowContainer = %CookingRow
@onready var _toast_label: Label = %ToastLabel
@onready var _debug_label: Label = %DebugLabel
@onready var _pause_overlay: ColorRect = %PauseOverlay
@onready var _pause_details: Label = %PauseDetails
@onready var _resume_button: Button = %ResumeButton
@onready var _choice_overlay: ColorRect = %ChoiceOverlay
@onready var _choice_title: Label = %ChoiceTitle
@onready var _choice_buttons: VBoxContainer = %ChoiceButtons
@onready var _results_overlay: ColorRect = %ResultsOverlay
@onready var _results_label: Label = %ResultsLabel
@onready var _restart_button: Button = %RestartButton

var _toast_tween: Tween
var _cooking_indicators: Dictionary[StringName, CookingIndicator] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(_apply_safe_area)
	_pause_button.pressed.connect(_on_pause_pressed)
	_resume_button.pressed.connect(_on_resume_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_apply_safe_area()


func set_durability(current: float, maximum: float, temporary_shield: float) -> void:
	_durability_bar.max_value = maximum
	_durability_bar.value = current
	if temporary_shield > 0.0:
		_durability_label.text = "餐车耐久  %.0f / %.0f   临时护盾 +%.0f" % [
			current,
			maximum,
			temporary_shield,
		]
	else:
		_durability_label.text = "餐车耐久  %.0f / %.0f" % [current, maximum]


func set_phase(text: String) -> void:
	_phase_label.text = text


func set_time(seconds: float) -> void:
	var total: int = maxi(0, floori(seconds))
	_time_label.text = "%02d:%02d" % [floori(float(total) / 60.0), total % 60]


func add_cooking_food(food: FoodData, level: int) -> void:
	var existing: CookingIndicator = _cooking_indicators.get(food.id)
	if existing != null:
		existing.set_level(level)
		return
	var indicator: CookingIndicator = COOKING_INDICATOR_SCENE.instantiate() as CookingIndicator
	_cooking_row.add_child(indicator)
	indicator.configure(food, level)
	_cooking_indicators[food.id] = indicator
	_refresh_cooking_indicator_sizes()


# 调试清空时移除对应烹饪圆环，避免HUD保留已卸下的食材。
func remove_cooking_food(food_id: StringName) -> void:
	var indicator: CookingIndicator = _cooking_indicators.get(food_id)
	if indicator == null:
		return
	_cooking_indicators.erase(food_id)
	if is_instance_valid(indicator):
		indicator.free()
	_refresh_cooking_indicator_sizes()


func set_cooking_progress(
	food_id: StringName,
	progress: float,
	remaining_seconds: float
) -> void:
	var indicator: CookingIndicator = _cooking_indicators.get(food_id)
	if indicator != null:
		indicator.set_cooking_progress(progress, remaining_seconds)


func set_cooking_level(food_id: StringName, level: int) -> void:
	var indicator: CookingIndicator = _cooking_indicators.get(food_id)
	if indicator != null:
		indicator.set_level(level)


func set_pause_available(available: bool) -> void:
	_pause_button.visible = (
		available
		and not _pause_overlay.visible
		and not _choice_overlay.visible
		and not _results_overlay.visible
	)


func show_pause(details: String) -> void:
	_pause_details.text = details
	_pause_overlay.visible = true
	_pause_button.visible = false


func hide_pause() -> void:
	_pause_overlay.visible = false


func is_pause_visible() -> bool:
	return _pause_overlay.visible


func set_debug_text(text: String) -> void:
	_debug_label.text = text


func show_toast(text: String, color: Color = PAPER) -> void:
	_toast_label.text = text
	_toast_label.modulate = color
	_toast_label.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_toast_tween.tween_interval(1.1)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.45)


# 每次展示时只按本轮候选重建按钮，固定界面结构均保留在 hud.tscn 中。
func show_special_choices(
	choice_ids: Array[StringName],
	choice_texts: Dictionary[StringName, String] = {},
	title: String = "六席贵客满意了！挑一份特别赏赐"
) -> void:
	for child: Node in _choice_buttons.get_children():
		child.free()
	for choice_id: StringName in choice_ids:
		_add_choice_button(
			_choice_buttons,
			choice_id,
			choice_texts.get(choice_id, String(choice_id))
		)
	_choice_overlay.visible = true
	_pause_button.visible = false
	_choice_title.text = title


func hide_special_choices() -> void:
	_choice_overlay.visible = false


func show_results(title: String, body: String) -> void:
	_results_overlay.visible = true
	_pause_button.visible = false
	_results_label.text = "%s\n\n%s" % [title, body]


func _refresh_cooking_indicator_sizes() -> void:
	var compact: bool = _cooking_indicators.size() > 8
	for indicator: CookingIndicator in _cooking_indicators.values():
		indicator.custom_minimum_size = Vector2(60.0, 76.0) if compact else Vector2(76.0, 94.0)
		indicator.scale = Vector2.ONE * (0.79 if compact else 1.0)


func _add_choice_button(parent: VBoxContainer, choice_id: StringName, text: String) -> void:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(640.0, 132.0)
	button.add_theme_font_size_override(&"font_size", 24)
	button.add_theme_color_override(&"font_color", Color.WHITE)
	button.add_theme_stylebox_override(&"normal", _make_panel_style(Color("#3d513d"), Color("#d6ae55"), 5))
	button.add_theme_stylebox_override(&"hover", _make_panel_style(Color("#516b4e"), Color("#f2d47b"), 6))
	button.add_theme_stylebox_override(&"pressed", _make_panel_style(Color("#704638"), Color("#f2d47b"), 6))
	button.pressed.connect(_on_choice_pressed.bind(choice_id))
	parent.add_child(button)


func _make_panel_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


# 节点保留编辑器中的设计位置，运行时仅叠加设备安全区边距。
func _apply_safe_area() -> void:
	var top_margin: int = 24
	var bottom_margin: int = 24
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	var safe_rect: Rect2i = DisplayServer.get_display_safe_area()
	if screen_size.x > 0 and screen_size.y > 0 and safe_rect.size.x > 0 and safe_rect.size.y > 0:
		var logical_scale_y: float = 1280.0 / float(screen_size.y)
		top_margin = maxi(top_margin, roundi(float(safe_rect.position.y) * logical_scale_y) + 14)
		var bottom_pixels: int = screen_size.y - safe_rect.end.y
		bottom_margin = maxi(bottom_margin, roundi(float(bottom_pixels) * logical_scale_y) + 14)
	_safe_margin.add_theme_constant_override(&"margin_top", top_margin)
	_safe_margin.add_theme_constant_override(&"margin_bottom", bottom_margin)
	_safe_margin.add_theme_constant_override(&"margin_left", 24)
	_safe_margin.add_theme_constant_override(&"margin_right", 24)
	_durability_panel.offset_left = 24.0
	_durability_panel.offset_right = -24.0
	_durability_panel.offset_top = -float(bottom_margin) - 82.0
	_durability_panel.offset_bottom = -float(bottom_margin)
	_cooking_area.offset_top = -float(bottom_margin) - 284.0
	_cooking_area.offset_bottom = -float(bottom_margin) - 88.0
	_debug_label.offset_left = -330.0
	_debug_label.offset_right = -30.0
	_debug_label.offset_top = -float(bottom_margin) - 150.0
	_debug_label.offset_bottom = -float(bottom_margin) - 92.0


func _on_choice_pressed(choice_id: StringName) -> void:
	special_choice_selected.emit(choice_id)


func _on_pause_pressed() -> void:
	pause_requested.emit()


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_restart_pressed() -> void:
	restart_requested.emit()
