class_name MainMenu
extends CanvasLayer

signal start_requested

@onready var _menu_root: Control = %MenuRoot
@onready var _handbook_overlay: Control = %HandbookOverlay
@onready var _start_button: Button = %StartButton
@onready var _handbook_button: Button = %HandbookButton
@onready var _close_handbook_button: Button = %CloseBookButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_button.pressed.connect(_on_start_pressed)
	_handbook_button.pressed.connect(_on_handbook_pressed)
	_close_handbook_button.pressed.connect(_on_close_handbook_pressed)
	open()


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
	elif key_event.keycode == KEY_ENTER or key_event.keycode == KEY_SPACE:
		_on_start_pressed()
		get_viewport().set_input_as_handled()


func open() -> void:
	_menu_root.visible = true
	_handbook_overlay.visible = false


func close() -> void:
	_handbook_overlay.visible = false
	_menu_root.visible = false


func _on_start_pressed() -> void:
	start_requested.emit()


func _on_handbook_pressed() -> void:
	_handbook_overlay.visible = true


func _on_close_handbook_pressed() -> void:
	_handbook_overlay.visible = false
