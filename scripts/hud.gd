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
var _party_health_root: VBoxContainer
var _party_rows: Dictionary[int, Dictionary] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(_apply_safe_area)
	_pause_button.pressed.connect(_on_pause_pressed)
	_resume_button.pressed.connect(_on_resume_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_build_party_health_hud()
	_apply_safe_area()


func set_durability(current: float, maximum: float, temporary_shield: float) -> void:
	_resolve_runtime_nodes()
	if _durability_bar == null or _durability_label == null:
		return
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


func set_party_health(players: Array[Dictionary], local_slot: int = 1) -> void:
	if _party_health_root == null:
		return
	var visible_slots: Dictionary[int, bool] = {}
	for record: Dictionary in players:
		var slot: int = int(record.get("slot", 0))
		if slot < 1 or slot > 4:
			continue
		visible_slots[slot] = true
		var row: Dictionary = _party_rows.get(slot, {})
		var row_root: HBoxContainer = row.get("root") as HBoxContainer
		var slot_badge: PanelContainer = row.get("badge") as PanelContainer
		var slot_label: Label = row.get("slot_label") as Label
		var health_label: Label = row.get("health") as Label
		var extra_label: Label = row.get("extra") as Label
		if row_root == null:
			continue
		var color_text: String = str(record.get("color", "#ffffff"))
		if not color_text.begins_with("#"):
			color_text = "#" + color_text
		var color: Color = Color(color_text)
		slot_label.text = "P%d" % slot
		health_label.text = "0" if bool(record.get("ghost", false)) else "%.0f" % float(record.get("current", 0.0))
		health_label.modulate = color if not bool(record.get("ghost", false)) else color.darkened(0.35)
		extra_label.text = (
			"复活 %.0fs" % ceilf(float(record.get("respawn", 0.0)))
			if bool(record.get("ghost", false))
			else ("+%.0f" % float(record.get("shield", 0.0)) if float(record.get("shield", 0.0)) > 0.0 else "")
		)
		extra_label.modulate = Color("#9babb7") if bool(record.get("ghost", false)) else Color("#78d8ff")
		slot_badge.add_theme_stylebox_override(&"panel", _make_party_badge_style(color, slot == local_slot))
		row_root.visible = true
	for slot: int in _party_rows:
		var row_root: HBoxContainer = (_party_rows[slot].get("root") as HBoxContainer)
		if row_root != null:
			row_root.visible = visible_slots.has(slot)
	_apply_party_toast_layout(visible_slots.size())


func set_phase(text: String) -> void:
	_resolve_runtime_nodes()
	if _phase_label == null:
		return
	_phase_label.text = text


func set_time(seconds: float) -> void:
	_resolve_runtime_nodes()
	if _time_label == null:
		return
	var total: int = maxi(0, floori(seconds))
	_time_label.text = "%02d:%02d" % [floori(float(total) / 60.0), total % 60]


func add_cooking_food(food: FoodData, level: int) -> void:
	if _cooking_row == null:
		_cooking_row = get_node_or_null("Root/CookingArea/CookingRow") as HFlowContainer
	if _cooking_row == null:
		return
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
	_resolve_runtime_nodes()
	if _pause_button == null:
		return
	_pause_button.visible = (
		available
		and (_pause_overlay == null or not _pause_overlay.visible)
		and (_choice_overlay == null or not _choice_overlay.visible)
		and (_results_overlay == null or not _results_overlay.visible)
	)


func show_pause(details: String) -> void:
	_resolve_runtime_nodes()
	if _pause_details == null or _pause_overlay == null:
		return
	_pause_details.text = details
	_pause_overlay.visible = true
	if _pause_button != null:
		_pause_button.visible = false


func hide_pause() -> void:
	_resolve_runtime_nodes()
	if _pause_overlay == null:
		return
	_pause_overlay.visible = false


func is_pause_visible() -> bool:
	_resolve_runtime_nodes()
	return _pause_overlay != null and _pause_overlay.visible


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
			choice_texts.get(choice_id, str(choice_id))
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


func _build_party_health_hud() -> void:
	_party_health_root = VBoxContainer.new()
	_party_health_root.name = "PartyHealth"
	_party_health_root.position = Vector2(24.0, 104.0)
	_party_health_root.custom_minimum_size = Vector2(290.0, 0.0)
	_party_health_root.add_theme_constant_override(&"separation", 4)
	_root.add_child(_party_health_root)
	for slot: int in range(1, 5):
		var row_root := HBoxContainer.new()
		row_root.name = "P%dRow" % slot
		row_root.custom_minimum_size = Vector2(270.0, 46.0)
		row_root.add_theme_constant_override(&"separation", 8)
		var badge := PanelContainer.new()
		badge.custom_minimum_size = Vector2(46.0, 46.0)
		var badge_label := Label.new()
		badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge_label.add_theme_font_size_override(&"font_size", 15)
		badge.add_child(badge_label)
		row_root.add_child(badge)
		var health := Label.new()
		health.custom_minimum_size = Vector2(130.0, 46.0)
		health.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		health.add_theme_font_size_override(&"font_size", 24)
		row_root.add_child(health)
		var extra := Label.new()
		extra.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		extra.add_theme_font_size_override(&"font_size", 15)
		row_root.add_child(extra)
		_party_health_root.add_child(row_root)
		_party_rows[slot] = {
			"root": row_root,
			"badge": badge,
			"slot_label": badge_label,
			"health": health,
			"extra": extra,
		}
		row_root.visible = false
	_apply_party_toast_layout(0)


# 多人队伍占用顶部四行时，把临时提示移到队伍下方，避免遮住耐久数字。
func _apply_party_toast_layout(visible_slot_count: int) -> void:
	if _toast_label == null:
		return
	var safe_count: int = clampi(visible_slot_count, 0, 4)
	var party_height: float = float(safe_count) * 46.0 + maxf(0.0, float(safe_count - 1)) * 4.0
	var party_top: float = _party_health_root.position.y if _party_health_root != null else 104.0
	var toast_top: float = 190.0 if safe_count == 0 else party_top + party_height + 16.0
	_toast_label.position.y = toast_top


func _make_party_badge_style(color: Color, local_player: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.55)
	style.border_color = Color.WHITE if local_player else color
	style.set_border_width_all(3 if local_player else 2)
	style.set_corner_radius_all(23)
	return style


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
	_resolve_runtime_nodes()
	if _safe_margin == null or _durability_panel == null or _cooking_area == null or _debug_label == null:
		return
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
	_party_health_root.position = Vector2(24.0, float(top_margin) + 70.0)
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


# 测试脚本可能在 CanvasLayer 的 ready 回调前调用显示接口，按固定路径补齐控件。
func _resolve_runtime_nodes() -> void:
	if _safe_margin == null:
		_safe_margin = get_node_or_null("Root/SafeMargin") as MarginContainer
	if _durability_panel == null:
		_durability_panel = get_node_or_null("Root/DurabilityPanel") as PanelContainer
	if _durability_bar == null:
		_durability_bar = get_node_or_null("Root/DurabilityPanel/DurabilityStack/DurabilityBar") as ProgressBar
	if _durability_label == null:
		_durability_label = get_node_or_null("Root/DurabilityPanel/DurabilityStack/DurabilityLabel") as Label
	if _phase_label == null:
		_phase_label = get_node_or_null("Root/SafeMargin/TopLayout/Header/PhaseLabel") as Label
	if _time_label == null:
		_time_label = get_node_or_null("Root/SafeMargin/TopLayout/Header/TimeLabel") as Label
	if _cooking_area == null:
		_cooking_area = get_node_or_null("Root/CookingArea") as MarginContainer
	if _cooking_row == null:
		_cooking_row = get_node_or_null("Root/CookingArea/CookingRow") as HFlowContainer
	if _debug_label == null:
		_debug_label = get_node_or_null("Root/DebugLabel") as Label
	if _pause_overlay == null:
		_pause_overlay = get_node_or_null("Root/PauseOverlay") as ColorRect
	if _pause_details == null:
		_pause_details = get_node_or_null(
			"Root/PauseOverlay/PausePanel/PauseStack/PauseScroll/PauseDetails"
		) as Label


func _on_choice_pressed(choice_id: StringName) -> void:
	special_choice_selected.emit(choice_id)


func _on_pause_pressed() -> void:
	pause_requested.emit()


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_restart_pressed() -> void:
	restart_requested.emit()
