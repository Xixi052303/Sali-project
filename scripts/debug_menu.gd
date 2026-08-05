class_name DebugMenu
extends CanvasLayer

signal action_requested(action_id: StringName)
signal menu_opened
signal menu_closed

const PAPER: Color = Color("#f2dfb0")
const INK: Color = Color("#241f1a")
const ACCENT: Color = Color("#e4b85b")

@onready var _root: Control = %Root
@onready var _status_label: Label = %StatusLabel
@onready var _actions: VBoxContainer = %Actions
@onready var _feedback_label: Label = %FeedbackLabel
@onready var _close_button: Button = %CloseButton

var _was_tree_paused: bool = false
var _action_buttons: Dictionary[StringName, Button] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_close_button.pressed.connect(close)
	if not OS.is_debug_build():
		_root.visible = false
		set_process_input(false)
		return
	_build_actions()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.is_echo() or not _is_debug_toggle_key(key_event):
		return
	if _root.visible:
		close()
	else:
		open()
	get_viewport().set_input_as_handled()


func open() -> void:
	if not OS.is_debug_build() or _root.visible:
		return
	_was_tree_paused = get_tree().paused
	get_tree().paused = true
	_root.visible = true
	_feedback_label.text = "选择一项测试操作；再次按 ~ 可关闭"
	menu_opened.emit()


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	get_tree().paused = _was_tree_paused
	menu_closed.emit()


func set_status_text(text: String) -> void:
	_status_label.text = text


func show_feedback(text: String, success: bool = true) -> void:
	_feedback_label.text = text
	_feedback_label.modulate = Color("#a9e69d") if success else Color("#ff9b7d")


func set_toggle_states(invincible: bool, hud_visible: bool) -> void:
	var invincible_button: Button = _action_buttons.get(&"toggle_invincible")
	if invincible_button != null:
		invincible_button.text = "关闭餐车无敌" if invincible else "开启餐车无敌"
	var hud_button: Button = _action_buttons.get(&"toggle_hud")
	if hud_button != null:
		hud_button.text = "隐藏正式 HUD" if hud_visible else "显示正式 HUD"


func _is_debug_toggle_key(event: InputEventKey) -> bool:
	return (
		event.keycode == KEY_QUOTELEFT
		or event.physical_keycode == KEY_QUOTELEFT
		or event.unicode == 96
		or event.unicode == 126
	)


func _build_actions() -> void:
	_add_section("局内控制")
	_add_action_row([
		["0.5× 速度", &"speed_0_5"],
		["1× 速度", &"speed_1"],
	])
	_add_action_row([
		["2× 速度", &"speed_2"],
		["5× 速度", &"speed_5"],
	])
	_add_action_row([
		["时间前进 30 秒", &"advance_30"],
		["重新开始本局", &"restart"],
	])

	_add_section("餐车与构筑")
	_add_action_row([
		["修满餐车耐久", &"restore_cart"],
		["临时护盾 +100", &"add_shield"],
	])
	_add_action_row([
		["开启餐车无敌", &"toggle_invincible"],
		["一键解锁全部食材", &"unlock_all_foods"],
	])
	_add_action_row([
		["全部食材升满级", &"max_all_foods"],
		["解锁全部特殊能力", &"unlock_all_specials"],
	])

	_add_section("食材调试")
	_add_action_row([
		["获取土豆", &"get_food_potato"],
		["获取法棍", &"get_food_baguette"],
	])
	_add_action_row([
		["获取蘑菇", &"get_food_mushroom"],
		["获取鸡蛋", &"get_food_egg"],
	])
	_add_action_row([
		["获取胡萝卜", &"get_food_carrot"],
		["移除当前所有食材", &"remove_all_foods"],
	])
	_add_action_row([
		["随机满品质普通强化", &"random_normal_upgrade"],
		["全部普通强化各 1 层", &"all_normal_upgrades"],
	])

	_add_section("遭遇与流程")
	_add_action_row([
		["生成普通食客", &"spawn_basic"],
		["生成快速食客", &"spawn_fast"],
	])
	_add_action_row([
		["生成远程食客", &"spawn_ranged"],
		["生成精英食客", &"spawn_elite"],
	])
	_add_action_row([
		["生成普通强化门", &"spawn_gate"],
		["立即开始 Boss", &"start_boss"],
	])
	_add_action_row([
		["瞬间满足当前目标", &"satisfy_targets"],
		["清空路面对象", &"clear_forward"],
	])

	_add_section("显示")
	_add_action_row([
		["隐藏正式 HUD", &"toggle_hud"],
	])


func _add_section(title: String) -> void:
	var label: Label = Label.new()
	label.text = title
	label.add_theme_color_override(&"font_color", ACCENT)
	label.add_theme_font_size_override(&"font_size", 24)
	label.add_theme_constant_override(&"outline_size", 3)
	label.add_theme_color_override(&"font_outline_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_actions.add_child(label)


func _add_action_row(definitions: Array) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	_actions.add_child(row)
	for definition: Array in definitions:
		_add_action_button(row, str(definition[0]), StringName(definition[1]))


func _add_action_button(parent: HBoxContainer, label: String, action_id: StringName) -> void:
	var button: Button = Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0.0, 66.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override(&"font_size", 19)
	button.add_theme_color_override(&"font_color", PAPER)
	button.add_theme_stylebox_override(&"normal", _make_button_style(Color("#4b3a2e"), Color("#947548")))
	button.add_theme_stylebox_override(&"hover", _make_button_style(Color("#66503c"), ACCENT))
	button.add_theme_stylebox_override(&"pressed", _make_button_style(Color("#704638"), Color("#f2d47b")))
	button.pressed.connect(_on_action_pressed.bind(action_id))
	parent.add_child(button)
	_action_buttons[action_id] = button


func _make_button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _on_action_pressed(action_id: StringName) -> void:
	action_requested.emit(action_id)
