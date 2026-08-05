class_name MainMenu
extends CanvasLayer

signal start_requested

@onready var _menu_root: Control = %MenuRoot
@onready var _handbook_overlay: Control = %HandbookOverlay
@onready var _start_button: Button = %StartButton
@onready var _handbook_button: Button = %HandbookButton
@onready var _close_handbook_button: Button = %CloseBookButton

var _lan_button: Button
var _lan_overlay: Control
var _lan_panel: PanelContainer
var _lan_status: Label
var _lan_room_list: ItemList
var _lan_room_name: LineEdit
var _lan_ip_input: LineEdit
var _lan_create_button: Button
var _lan_join_button: Button
var _lan_start_button: Button
var _lan_leave_button: Button
var _lan_close_button: Button
var _lan_room_title: Label
var _lan_roster_label: Label
var _discovered_room_addresses: Array[String] = []
# 通过根节点获取 Autoload，避免直接依赖脚本测试进程未注册的全局单例符号。
@onready var _network_session: Variant = get_node_or_null("/root/NetworkSession")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_button.pressed.connect(_on_start_pressed)
	_handbook_button.pressed.connect(_on_handbook_pressed)
	_close_handbook_button.pressed.connect(_on_close_handbook_pressed)
	_build_lan_controls()
	_network_session.room_list_changed.connect(_on_room_list_changed)
	_network_session.roster_changed.connect(_on_roster_changed)
	_network_session.connection_state_changed.connect(_on_connection_state_changed)
	_network_session.match_started.connect(_on_match_started)
	_network_session.match_returned_to_lobby.connect(_on_match_returned_to_lobby)
	open()
	if _network_session.consume_reopen_lan_entry():
		_show_lan_overlay()


# 菜单打开时提供桌面调试快捷键，同时让手册页优先消费返回操作。
func _input(event: InputEvent) -> void:
	if not _menu_root.visible or not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.is_echo():
		return
	if key_event.keycode == KEY_ESCAPE and _handbook_overlay.visible:
		_on_close_handbook_pressed()
		get_viewport().set_input_as_handled()
	elif _handbook_overlay.visible:
		return
	elif _lan_overlay != null and _lan_overlay.visible:
		return
	elif key_event.keycode == KEY_ENTER or key_event.keycode == KEY_SPACE:
		_on_start_pressed()
		get_viewport().set_input_as_handled()


func open() -> void:
	_menu_root.visible = true
	_handbook_overlay.visible = false
	if _network_session.is_in_lobby():
		_show_lan_overlay()


func close() -> void:
	_handbook_overlay.visible = false
	if _lan_overlay != null:
		_lan_overlay.visible = false
	_menu_root.visible = false


func _on_start_pressed() -> void:
	start_requested.emit()


func _on_handbook_pressed() -> void:
	_handbook_overlay.visible = true


func _on_close_handbook_pressed() -> void:
	_handbook_overlay.visible = false


func _build_lan_controls() -> void:
	_lan_button = Button.new()
	_lan_button.text = "局域网联机"
	_lan_button.custom_minimum_size = Vector2(0.0, 72.0)
	_lan_button.pressed.connect(_show_lan_overlay)
	var layout: VBoxContainer = get_node("MenuRoot/Board/Body/Layout") as VBoxContainer
	if layout != null:
		layout.add_child(_lan_button)

	_lan_overlay = Control.new()
	_lan_overlay.name = "LanOverlay"
	_lan_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lan_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_lan_overlay.z_index = 20
	_lan_overlay.visible = false
	_menu_root.add_child(_lan_overlay)
	var lan_dim: ColorRect = ColorRect.new()
	lan_dim.name = "Dim"
	lan_dim.color = Color(0.02, 0.016, 0.012, 0.78)
	lan_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lan_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lan_overlay.add_child(lan_dim)

	_lan_panel = PanelContainer.new()
	_lan_panel.name = "LanPanel"
	_lan_panel.set_anchors_preset(Control.PRESET_CENTER)
	_lan_panel.z_index = 1
	_lan_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_lan_panel.add_theme_stylebox_override(&"panel", _make_style(Color("#201b17"), Color("#d6ae55"), 5, 8))
	_lan_overlay.add_child(_lan_panel)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lan_panel.add_child(scroll)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 12)
	body.add_theme_constant_override(&"margin_left", 26)
	body.add_theme_constant_override(&"margin_right", 26)
	body.add_theme_constant_override(&"margin_top", 24)
	body.add_theme_constant_override(&"margin_bottom", 24)
	scroll.add_child(body)

	_lan_room_title = Label.new()
	_lan_room_title.text = "局域网房间"
	_lan_room_title.add_theme_font_size_override(&"font_size", 30)
	body.add_child(_lan_room_title)

	_lan_status = Label.new()
	_lan_status.text = "选择创建或加入"
	_lan_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lan_status.custom_minimum_size = Vector2(0.0, 46.0)
	body.add_child(_lan_status)

	_lan_room_name = LineEdit.new()
	_lan_room_name.placeholder_text = "房间名"
	_lan_room_name.text = "小厨西房间"
	body.add_child(_lan_room_name)

	_lan_create_button = Button.new()
	_lan_create_button.text = "创建房间"
	_lan_create_button.pressed.connect(_on_lan_create_pressed)
	body.add_child(_lan_create_button)

	_lan_room_list = ItemList.new()
	_lan_room_list.custom_minimum_size = Vector2(0.0, 260.0)
	_lan_room_list.item_selected.connect(_on_lan_room_selected)
	body.add_child(_lan_room_list)

	_lan_ip_input = LineEdit.new()
	_lan_ip_input.placeholder_text = "同机填 127.0.0.1；跨设备填房主局域网 IPv4"
	body.add_child(_lan_ip_input)

	_lan_join_button = Button.new()
	_lan_join_button.text = "加入房间"
	_lan_join_button.pressed.connect(_on_lan_join_pressed)
	body.add_child(_lan_join_button)

	_lan_roster_label = Label.new()
	_lan_roster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lan_roster_label.custom_minimum_size = Vector2(0.0, 144.0)
	body.add_child(_lan_roster_label)

	_lan_start_button = Button.new()
	_lan_start_button.text = "房主开始"
	_lan_start_button.pressed.connect(_on_lan_start_pressed)
	body.add_child(_lan_start_button)

	_lan_leave_button = Button.new()
	_lan_leave_button.text = "离开房间"
	_lan_leave_button.pressed.connect(_on_lan_leave_pressed)
	body.add_child(_lan_leave_button)

	_lan_close_button = Button.new()
	_lan_close_button.text = "返回单人菜单"
	_lan_close_button.pressed.connect(_hide_lan_overlay)
	body.add_child(_lan_close_button)
	get_viewport().size_changed.connect(_apply_lan_panel_layout)
	_apply_lan_panel_layout()


func _show_lan_overlay() -> void:
	if _lan_overlay == null:
		return
	_handbook_overlay.visible = false
	_lan_overlay.visible = true
	_lan_overlay.move_to_front()
	_apply_lan_panel_layout()
	_refresh_lan_controls()


func _hide_lan_overlay() -> void:
	if _network_session.is_in_lobby():
		_network_session.leave_room()
	if _lan_overlay != null:
		_lan_overlay.visible = false


func _apply_lan_panel_layout() -> void:
	if _lan_panel == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_size: Vector2 = Vector2(
		minf(600.0, maxf(320.0, viewport_size.x - 32.0)),
		minf(800.0, maxf(480.0, viewport_size.y - 32.0))
	)
	# 中心锚点配合四个明确偏移，避免竖屏拉伸后把动态面板推到可视区外。
	_lan_panel.offset_left = -panel_size.x * 0.5
	_lan_panel.offset_top = -panel_size.y * 0.5
	_lan_panel.offset_right = panel_size.x * 0.5
	_lan_panel.offset_bottom = panel_size.y * 0.5


func _refresh_lan_controls() -> void:
	var in_lobby: bool = _network_session.is_in_lobby()
	_lan_create_button.disabled = in_lobby
	_lan_join_button.disabled = in_lobby
	_lan_room_name.editable = not in_lobby
	_lan_start_button.visible = in_lobby
	_lan_start_button.disabled = not _network_session.is_host()
	_lan_leave_button.visible = in_lobby
	_lan_room_title.text = (
		"房间：%s" % _network_session.room_name
		if in_lobby
		else "局域网房间"
	)
	if in_lobby:
		var rows: PackedStringArray = []
		var roster_by_slot: Dictionary[int, Dictionary] = {}
		for record: Dictionary in _network_session.get_roster():
			roster_by_slot[int(record.get("slot", 0))] = record
		for slot: int in range(1, _network_session.MAX_PLAYERS + 1):
			if roster_by_slot.has(slot):
				rows.append("P%d%s" % [slot, "（房主）" if slot == 1 else ""])
			else:
				rows.append("P%d（空位）" % slot)
		var host_addresses: PackedStringArray = _network_session.get_local_ipv4_addresses()
		var address_text: String = (
			"\n本机 IPv4（同机填 127.0.0.1）：%s" % "、".join(host_addresses)
			if _network_session.is_host() and not host_addresses.is_empty()
			else ""
		)
		_lan_roster_label.text = "成员：%s\n等待房主开始%s" % ["、".join(rows), address_text]
	else:
		_lan_roster_label.text = ""


func _on_room_list_changed(rooms: Array[Dictionary]) -> void:
	if _lan_room_list == null:
		return
	_discovered_room_addresses.clear()
	_lan_room_list.clear()
	for room: Dictionary in rooms:
		var address: String = str(room.get("address", ""))
		_discovered_room_addresses.append(address)
		_lan_room_list.add_item(
			"%s  ·  %d/%d  ·  %s" % [
				str(room.get("room_name", "小厨西房间")),
				int(room.get("players", 0)),
				int(room.get("max_players", _network_session.MAX_PLAYERS)),
				"进行中" if str(room.get("state", "lobby")) == "in_game" else address,
			]
		)


func _on_lan_room_selected(index: int) -> void:
	if index < 0 or index >= _discovered_room_addresses.size():
		return
	_lan_ip_input.text = _discovered_room_addresses[index]


func _on_roster_changed(_roster: Array[Dictionary]) -> void:
	if _network_session.is_in_lobby():
		_show_lan_overlay()
	_refresh_lan_controls()


func _on_connection_state_changed(state: StringName, message: String) -> void:
	if _lan_status != null:
		_lan_status.text = message
	if state in [&"offline", &"error", &"server_disconnected"]:
		_refresh_lan_controls()
	if state == &"server_disconnected":
		_show_lan_overlay()


func _on_match_started(_seed: int, _player_count: int, _roster: Array[Dictionary]) -> void:
	close()


func _on_match_returned_to_lobby() -> void:
	open()


func _on_lan_create_pressed() -> void:
	var error: Error = _network_session.host_room(_lan_room_name.text)
	if error == OK:
		_show_lan_overlay()


func _on_lan_join_pressed() -> void:
	_network_session.join_room(_lan_ip_input.text)


func _on_lan_start_pressed() -> void:
	if _network_session.start_match():
		close()


func _on_lan_leave_pressed() -> void:
	_network_session.leave_room()
	_show_lan_overlay()


func _make_style(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	return style
