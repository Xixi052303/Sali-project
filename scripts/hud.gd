class_name GameHud
extends CanvasLayer

signal special_choice_selected(choice_id: StringName)
signal restart_requested

const INK: Color = Color("#241f1a")
const PAPER: Color = Color("#d3b77f")
const PANEL: Color = Color(0.12, 0.1, 0.08, 0.88)

var _root: Control
var _safe_margin: MarginContainer
var _durability_panel: PanelContainer
var _durability_bar: ProgressBar
var _durability_label: Label
var _phase_label: Label
var _time_label: Label
var _toast_label: Label
var _debug_label: Label
var _choice_overlay: ColorRect
var _choice_title: Label
var _choice_buttons: VBoxContainer
var _results_overlay: ColorRect
var _results_label: Label
var _toast_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func set_durability(current: float, maximum: float) -> void:
	_durability_bar.max_value = maximum
	_durability_bar.value = current
	_durability_label.text = "餐车耐久  %.0f / %.0f" % [current, maximum]


func set_phase(text: String) -> void:
	_phase_label.text = text


func set_time(seconds: float) -> void:
	var total: int = maxi(0, floori(seconds))
	_time_label.text = "%02d:%02d" % [floori(float(total) / 60.0), total % 60]


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


# 每次展示时按本轮候选重建按钮，保持特殊奖励始终是有效三选一。
func show_special_choices(choice_ids: Array[StringName]) -> void:
	for child: Node in _choice_buttons.get_children():
		child.free()
	for choice_id: StringName in choice_ids:
		_add_choice_button(_choice_buttons, choice_id, _special_choice_text(choice_id))
	_choice_overlay.visible = true
	_choice_title.text = "六席贵客满意了！挑一份特别赏赐"


func hide_special_choices() -> void:
	_choice_overlay.visible = false


func show_results(title: String, body: String) -> void:
	_results_overlay.visible = true
	_results_label.text = "%s\n\n%s" % [title, body]


func _build_interface() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_safe_margin = MarginContainer.new()
	_safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_safe_margin)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override(&"separation", 8)
	_safe_margin.add_child(layout)

	var header: HBoxContainer = HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(header)

	_phase_label = _make_label("准备出餐", 24, PAPER)
	_phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_phase_label)
	_time_label = _make_label("00:00", 28, Color.WHITE)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.custom_minimum_size.x = 120.0
	header.add_child(_time_label)

	_durability_panel = PanelContainer.new()
	_durability_panel.anchor_right = 1.0
	_durability_panel.anchor_top = 1.0
	_durability_panel.anchor_bottom = 1.0
	_durability_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_durability_panel.add_theme_stylebox_override(&"panel", _make_panel_style(Color("#4e372d"), Color("#d6ae55"), 4))
	_root.add_child(_durability_panel)
	var durability_stack: VBoxContainer = VBoxContainer.new()
	durability_stack.add_theme_constant_override(&"separation", 1)
	_durability_panel.add_child(durability_stack)
	_durability_label = _make_label("餐车耐久  100 / 100", 20, Color.WHITE)
	durability_label_margins(_durability_label)
	durability_stack.add_child(_durability_label)
	_durability_bar = ProgressBar.new()
	_durability_bar.custom_minimum_size.y = 15.0
	_durability_bar.show_percentage = false
	_durability_bar.add_theme_stylebox_override(&"background", _make_panel_style(Color("#201c18"), INK, 0))
	_durability_bar.add_theme_stylebox_override(&"fill", _make_panel_style(Color("#d06a3f"), Color("#d06a3f"), 0))
	durability_stack.add_child(_durability_bar)

	_toast_label = _make_label("", 28, Color("#f2d47b"))
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.position = Vector2(35.0, 190.0)
	_toast_label.size = Vector2(650.0, 80.0)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.add_theme_stylebox_override(&"normal", _make_panel_style(Color(0.08, 0.07, 0.06, 0.76), INK, 4))
	_root.add_child(_toast_label)

	_debug_label = _make_label("", 15, Color(0.95, 0.9, 0.75, 0.78))
	_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_debug_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_debug_label.anchor_left = 1.0
	_debug_label.anchor_right = 1.0
	_debug_label.anchor_top = 1.0
	_debug_label.anchor_bottom = 1.0
	_root.add_child(_debug_label)

	_build_choice_overlay()
	_build_results_overlay()


func durability_label_margins(label: Label) -> void:
	label.add_theme_constant_override(&"outline_size", 3)
	label.add_theme_color_override(&"font_outline_color", INK)


func _build_choice_overlay() -> void:
	_choice_overlay = ColorRect.new()
	_choice_overlay.color = Color(0.07, 0.06, 0.05, 0.94)
	_choice_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_choice_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_choice_overlay.visible = false
	_root.add_child(_choice_overlay)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.position = Vector2(40.0, 250.0)
	stack.size = Vector2(640.0, 700.0)
	stack.add_theme_constant_override(&"separation", 30)
	_choice_overlay.add_child(stack)
	_choice_title = _make_label("选择特别赏赐", 32, Color("#f4d27a"))
	_choice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_choice_title)
	_choice_buttons = VBoxContainer.new()
	_choice_buttons.add_theme_constant_override(&"separation", 20)
	stack.add_child(_choice_buttons)


func _special_choice_text(choice_id: StringName) -> String:
	match choice_id:
		&"baguette":
			return "法棍\n获得穿透最多3名食客的新食材"
		&"serving":
			return "全局加量\n当前与未来食材各多发一份"
		&"potato_aim":
			return "瞄准投喂\n土豆发射时朝向当前目标"
		&"soy_sauce":
			return "酱油\n所有当前与未来食材穿透次数 +1"
	return String(choice_id)


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


func _build_results_overlay() -> void:
	_results_overlay = ColorRect.new()
	_results_overlay.color = Color(0.07, 0.06, 0.05, 0.95)
	_results_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_results_overlay.visible = false
	_root.add_child(_results_overlay)
	var panel: VBoxContainer = VBoxContainer.new()
	panel.position = Vector2(70.0, 250.0)
	panel.size = Vector2(580.0, 720.0)
	panel.add_theme_constant_override(&"separation", 28)
	_results_overlay.add_child(panel)
	_results_label = _make_label("", 27, Color("#f2deb0"))
	_results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_results_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_results_label)
	var restart: Button = Button.new()
	restart.text = "再来一局"
	restart.custom_minimum_size.y = 86.0
	restart.add_theme_font_size_override(&"font_size", 28)
	restart.add_theme_stylebox_override(&"normal", _make_panel_style(Color("#6d4335"), Color("#e1ba62"), 5))
	restart.pressed.connect(_on_restart_pressed)
	panel.add_child(restart)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", INK)
	label.add_theme_constant_override(&"outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_panel_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


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
	_debug_label.offset_left = -330.0
	_debug_label.offset_right = -30.0
	_debug_label.offset_top = -float(bottom_margin) - 150.0
	_debug_label.offset_bottom = -float(bottom_margin) - 92.0


func _on_choice_pressed(choice_id: StringName) -> void:
	special_choice_selected.emit(choice_id)


func _on_restart_pressed() -> void:
	restart_requested.emit()
