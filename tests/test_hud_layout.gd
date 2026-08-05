extends SceneTree

var _failures: int = 0


func _init() -> void:
	var hud_scene: PackedScene = load("res://scenes/hud.tscn") as PackedScene
	if hud_scene == null:
		push_error("HUD_LAYOUT_SCENE_MISSING")
		quit(1)
		return
	var hud: Node = hud_scene.instantiate()
	root.add_child(hud)
	call_deferred("_run", hud)


func _run(hud: Node) -> void:
	var players: Array[Dictionary] = []
	for slot: int in range(1, 5):
		players.append({
			"slot": slot,
			"color": "e86b58",
			"current": 100.0,
			"maximum": 100.0,
			"shield": 0.0,
			"ghost": false,
			"respawn": 0.0,
		})
	hud.set_party_health(players, 1)
	var party_root: Control = hud.get_node("Root/PartyHealth") as Control
	var toast: Control = hud.get_node("Root/ToastLabel") as Control
	_check(party_root != null and toast != null, "HUD动态节点存在")
	var hud_root: Control = hud.get_node("Root") as Control
	for viewport_size: Vector2 in [Vector2(720.0, 1280.0), Vector2(405.0, 720.0)]:
		hud_root.size = viewport_size
		hud._apply_safe_area()
		_check(
			party_root.position.x >= 0.0
			and party_root.position.x + party_root.custom_minimum_size.x <= viewport_size.x,
			"队伍血量列在%s竖屏宽度内" % str(viewport_size)
		)
		_check(
			party_root.position.y + 4.0 * 46.0 + 3.0 * 4.0 < viewport_size.y * 0.5,
			"四行队伍血量在%s竖屏上半区内" % str(viewport_size)
		)
	var four_row_bottom: float = party_root.position.y + 4.0 * 46.0 + 3.0 * 4.0
	_check(toast.position.y >= four_row_bottom + 16.0, "四人队伍时提示条移到血量列表下方")
	var one_player: Array[Dictionary] = [players[0]]
	hud.set_party_health(one_player, 1)
	_check(toast.position.y >= party_root.position.y + 46.0 + 16.0, "单行队伍提示保持紧凑位置")
	var empty_players: Array[Dictionary] = []
	hud.set_party_health(empty_players, 1)
	_check(is_equal_approx(toast.position.y, 190.0), "无队伍时提示恢复单人位置")
	players[0]["ghost"] = true
	players[0]["respawn"] = 180.0
	players[1]["current"] = 1234567.0
	players[1]["maximum"] = 2345678.0
	players[1]["shield"] = 9999.0
	hud.set_party_health(players, 1)
	var p1_row: HBoxContainer = party_root.get_node("P1Row") as HBoxContainer
	var p2_row: HBoxContainer = party_root.get_node("P2Row") as HBoxContainer
	var p1_extra: Label = p1_row.get_child(2) as Label
	var p2_health: Label = p2_row.get_child(1) as Label
	var p2_extra: Label = p2_row.get_child(2) as Label
	_check(p1_extra.text.contains("180"), "幽灵行显示180秒复活倒计时")
	_check(p2_health.text == "1234567", "长耐久值完整显示")
	_check(p2_extra.text.contains("9999"), "队伍行显示蓝色护盾附值")
	_check(p2_health.get_minimum_size().x <= 130.0, "长耐久值保持在固定血量列内")
	if _failures == 0:
		print("HUD_LAYOUT_TEST_OK")
		quit(0)
	else:
		push_error("HUD_LAYOUT_TEST_FAILED count=%d" % _failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("TEST FAILED: %s" % message)
