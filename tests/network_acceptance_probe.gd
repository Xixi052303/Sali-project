extends Node

## 多进程局域网验收探针；只通过公开网络/运行控制入口观察，不替代正式游戏规则。

var _session: Node
var _run: Node
var _role: String = "client"
var _client_index: int = 0
var _probe_dir: String = ""
var _elapsed: float = 0.0
var _match_elapsed: float = 0.0
var _joined: bool = false
var _match_started: bool = false
var _damage_batch_sent: bool = false
var _respawn_checkpoint_logged: bool = false
var _second_damage_sent: bool = false
var _pause_sent: bool = false
var _resume_sent: bool = false
var _return_requested: bool = false
var _returned_ready: bool = false
var _cycle_elapsed: float = 0.0
var _network_smoke_test: bool = false
var _network_fail_test: bool = false
var _network_hold_lobby: bool = false
var _network_expect_join_rejection: bool = false
var _network_disconnect_choice_test: bool = false
var _network_discovery_test: bool = false
var _network_host_disconnect_test: bool = false
var _expected_players: int = 4
var _projectile_burst_events: int = 0
var _failure_logged: bool = false
var _choice_disconnect_sent: bool = false
var _choice_disconnect_choice_sent: bool = false
var _choice_disconnect_return_requested: bool = false
var _choice_disconnect_resume_sent: bool = false
var _discovery_join_requested: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session = get_node_or_null("/root/NetworkSession")
	_run = get_node_or_null("Run3D")
	_read_arguments()
	_log("ACCEPT_PROBE_DIR path=%s role=%s index=%d" % [_probe_dir, _role, _client_index])
	if _session == null or _run == null:
		push_error("ACCEPTANCE_PROBE_SETUP_MISSING")
		get_tree().quit(1)
		return
	_session.connection_state_changed.connect(_on_connection_state_changed)
	_session.match_started.connect(_on_match_started)
	_session.match_returned_to_lobby.connect(_on_match_returned_to_lobby)
	_session.pause_changed.connect(_on_pause_changed)
	_session.room_list_changed.connect(_on_room_list_changed)
	_session.network_event_received.connect(_on_network_event_received)
	if _file_exists("return_requested"):
		_returned_ready = true
		_write_marker("returned_ready_%s" % _role_marker())
		_log("ACCEPT_RETURN_READY roster=%d" % _session.get_roster().size())
		return
	if _role == "host":
		var host_error: Error = _session.host_room("验收房间")
		_log("ACCEPT_HOST_ROOM result=%s options=%s" % [error_string(host_error), _session.get_network_test_options()])
		_write_marker("host_ready")
	elif _network_discovery_test:
		_log("ACCEPT_CLIENT_DISCOVERY_WAIT")
		_write_marker("client_%d_started" % _client_index)
	else:
		var join_error: Error = _session.join_room("127.0.0.1")
		_log("ACCEPT_CLIENT_JOIN index=%d result=%s options=%s" % [
			_client_index,
			error_string(join_error),
			_session.get_network_test_options(),
		])
		_write_marker("client_%d_started" % _client_index)


func _process(delta: float) -> void:
	_elapsed += maxf(0.0, delta)
	if _returned_ready:
		_cycle_elapsed += maxf(0.0, delta)
		if _role == "host" and _cycle_elapsed >= 5.0:
			_log("ACCEPT_HOST_RETURN_ROSTER count=%d" % _session.get_roster().size())
			_session.leave_room()
			_write_marker("host_done")
			get_tree().quit(0)
		return
	if _match_started:
		_match_elapsed += maxf(0.0, delta)
		if _role == "host":
			if _network_fail_test:
				_run_host_failure_lifecycle()
			elif _network_host_disconnect_test:
				_run_host_disconnect_lifecycle()
			elif _network_disconnect_choice_test:
				_run_choice_disconnect_lifecycle()
			elif _network_smoke_test:
				_auto_submit_special_choices()
				_run_host_lifecycle()
			else:
				_run_host_lifecycle()
	if _role == "host" and not _match_started and _elapsed >= 1.0 and not _network_hold_lobby:
		var roster_count: int = _session.get_roster().size()
		if roster_count == _expected_players:
			var start_result: bool = _session.start_match()
			_log("ACCEPT_HOST_START result=%s roster=%d" % [start_result, roster_count])
		elif _elapsed >= 80.0:
			_log("ACCEPT_HOST_FAIL_ROSTER count=%d" % roster_count)
			get_tree().quit(1)
	var client_timeout: float = 1000.0 if _network_smoke_test else 100.0
	if _role == "client" and _elapsed >= client_timeout:
		_log("ACCEPT_CLIENT_TIMEOUT joined=%s match=%s" % [_joined, _match_started])
		get_tree().quit(1)


func _run_host_lifecycle() -> void:
	if not _damage_batch_sent and _match_elapsed >= 1.0:
		_damage_batch_sent = true
		var batch: Dictionary[int, float] = {2: 1000000.0, 3: 1000000.0}
		_run.damage_carts(batch, "验收同批伤害")
		_log_life_state("ACCEPT_AFTER_BATCH_DAMAGE")
	if not _respawn_checkpoint_logged and _match_elapsed >= 16.5:
		_respawn_checkpoint_logged = true
		_log_life_state("ACCEPT_AFTER_FIRST_RESPAWN")
	# 先避开复活后的2秒保护，再验证下一次死亡档位从45秒开始。
	if not _second_damage_sent and _match_elapsed >= 20.5:
		_second_damage_sent = true
		_run.damage_cart(1000000.0, "验收第二档伤害", 2)
		_log_life_state("ACCEPT_AFTER_SECOND_DAMAGE")
	if not _pause_sent and _match_elapsed >= 21.0:
		_pause_sent = true
		_session.request_pause()
	if not _resume_sent and _match_elapsed >= 22.5:
		_resume_sent = true
		_session.request_resume()
	if not _return_requested and _match_elapsed >= 28.0:
		_return_requested = true
		_write_marker("return_requested")
		_log("ACCEPT_HOST_RETURN_REQUEST")
		_session.return_to_lobby()


# 失败验收让同一伤害批次击倒全部槽位，验证不会先进入复活等待。
func _run_host_failure_lifecycle() -> void:
	if not _failure_logged and _match_elapsed >= 1.0:
		_failure_logged = true
		var contexts: Dictionary = _run.get("_player_contexts")
		var damages: Dictionary[int, float] = {}
		for slot: int in contexts:
			damages[slot] = 1000000.0
		_run.damage_carts(damages, "验收全灭")
		_log("ACCEPT_AFTER_ALL_DEAD phase=%d" % int(_run.get("phase")))
		_write_marker("failure_observed")


# 主机在开局后主动离开，验证客户端回到联机入口且断线窗口不继续发包。
func _run_host_disconnect_lifecycle() -> void:
	if _match_elapsed < 1.0:
		return
	_write_marker("host_disconnect_requested")
	_log("ACCEPT_HOST_DISCONNECT_REQUEST")
	_session.leave_room()
	get_tree().quit(0)


# 选择界面中断开P2，验证房主移除等待集合后仍能继续并回房。
func _run_choice_disconnect_lifecycle() -> void:
	var phase_value: int = int(_run.get("phase"))
	if not _choice_disconnect_sent:
		if phase_value != 2:
			return
		var target_peer_id: int = 0
		for record: Dictionary in _session.get_roster():
			if int(record.get("slot", 0)) == 2:
				target_peer_id = int(record.get("peer_id", 0))
				break
		if target_peer_id <= 0:
			return
		_session.multiplayer.multiplayer_peer.disconnect_peer(target_peer_id)
		_choice_disconnect_sent = true
		_log("ACCEPT_CHOICE_DISCONNECT_SENT")
		_write_marker("choice_disconnect_sent")
		return
	if not _choice_disconnect_resume_sent:
		_choice_disconnect_resume_sent = true
		_session.request_resume()
		_log("ACCEPT_CHOICE_RESUME_REQUESTED tree_paused=%s" % get_tree().paused)
		_write_marker("choice_resume_requested")
		if not get_tree().paused:
			_write_marker("choice_resume_bypassed")
			get_tree().quit(1)
		return
	if not _choice_disconnect_choice_sent and _session.get_roster().size() == 1:
		if not get_tree().paused:
			_write_marker("choice_resume_bypassed")
			get_tree().quit(1)
			return
		var choices_by_slot: Dictionary = _run.get("_active_special_choices_by_slot")
		var choices: Array = choices_by_slot.get(1, [])
		if choices.is_empty():
			return
		_run.call("_on_network_choice_received", 1, StringName(str(choices[0])))
		_choice_disconnect_choice_sent = true
		_log("ACCEPT_CHOICE_DISCONNECT_P1_SELECTED")
		return
	if _choice_disconnect_choice_sent and phase_value == 1 and not _choice_disconnect_return_requested:
		_choice_disconnect_return_requested = true
		_write_marker("choice_disconnect_progressed")
		_write_marker("return_requested")
		_session.return_to_lobby()


func _on_connection_state_changed(state: StringName, message: String) -> void:
	_log("ACCEPT_%s_STATE state=%s message=%s roster=%d" % [
		_role_marker(),
		str(state),
		message,
		_session.get_roster().size(),
	])
	if state == &"joined":
		_joined = true
		_write_marker("client_%d_joined" % _client_index)
	if state == &"server_disconnected":
		_write_marker("client_%d_disconnected" % _client_index)
		get_tree().quit(0)
	if state == &"error" and _network_expect_join_rejection:
		_write_marker("join_rejected_%d" % _client_index)
		get_tree().quit(0)


func _on_match_started(seed: int, player_count: int, roster: Array[Dictionary]) -> void:
	_match_started = true
	_match_elapsed = 0.0
	if _network_smoke_test:
		Engine.time_scale = 4.0
		if _role == "host":
			_run.set("_debug_invincible", true)
	_log("ACCEPT_%s_MATCH seed=%d count=%d roster=%d contexts=%d" % [
		_role_marker(),
		seed,
		player_count,
		roster.size(),
		_run.get("_player_contexts").size(),
	])
	_write_marker("%s_match" % _role_marker())
	if _network_disconnect_choice_test and _role == "host":
		# 只在验收探针中注入合法选择阶段，避免等待完整时间轴才覆盖断线等待集合。
		_run.call_deferred(
			"_show_special_choices",
			StringName("probe_disconnect"),
			"验收断线选择"
		)


func _on_match_returned_to_lobby() -> void:
	if _network_smoke_test or _network_fail_test or _network_disconnect_choice_test:
		Engine.time_scale = 1.0
		_write_marker("return_requested")
	_write_marker("returned_signal_%s" % _role_marker())
	_log("ACCEPT_%s_RETURN_SIGNAL roster=%d bursts=%d" % [
		_role_marker(),
		_session.get_roster().size(),
		_projectile_burst_events,
	])


func _on_pause_changed(paused: bool, owner_slot: int) -> void:
	_log("ACCEPT_%s_PAUSE paused=%s owner=%d tree_paused=%s" % [
		_role_marker(),
		paused,
		owner_slot,
		get_tree().paused,
	])


func _on_room_list_changed(rooms: Array[Dictionary]) -> void:
	if rooms.is_empty():
		return
	_log("ACCEPT_%s_DISCOVERY rooms=%d" % [_role_marker(), rooms.size()])
	_write_marker("%s_discovery" % _role_marker())
	if _role == "client" and _network_discovery_test and not _joined and not _discovery_join_requested:
		var address: String = str(rooms[0].get("address", ""))
		if address.is_empty():
			return
		_discovery_join_requested = true
		var join_error: Error = _session.join_room(address)
		_log("ACCEPT_CLIENT_DISCOVERY_JOIN address=%s result=%s" % [address, error_string(join_error)])
		_write_marker("discovery_join_requested_%d" % _client_index)


func _on_network_event_received(event: Dictionary) -> void:
	if event.get("type", "") == "projectile_burst":
		_projectile_burst_events += 1
	elif event.get("type", "") == "match_failed":
		_write_marker("match_failed_%s" % _role_marker())
		_log("ACCEPT_%s_MATCH_FAILED" % _role_marker())


func _log_life_state(label: String) -> void:
	var contexts: Dictionary = _run.get("_player_contexts")
	var rows: PackedStringArray = []
	for slot: int in [2, 3]:
		var context: Variant = contexts.get(slot)
		if context == null:
			rows.append("P%d=missing" % slot)
			continue
		rows.append("P%d ghost=%s respawn=%.1f deaths=%d team=%d" % [
			slot,
			context.is_ghost(),
			context.respawn_remaining,
			context.death_count,
			_run.get("_team_death_count"),
		])
	_log("%s %s" % [label, " | ".join(rows)])


func _read_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--network-role="):
			_role = argument.trim_prefix("--network-role=").strip_edges().to_lower()
		elif argument.begins_with("--network-index="):
			_client_index = argument.trim_prefix("--network-index=").to_int()
		elif argument.begins_with("--probe-dir="):
			_probe_dir = argument.trim_prefix("--probe-dir=").strip_edges()
		elif argument == "--network-smoke-test":
			_network_smoke_test = true
		elif argument == "--network-fail-test":
			_network_fail_test = true
		elif argument == "--network-hold-lobby":
			_network_hold_lobby = true
		elif argument == "--network-expect-join-rejection":
			_network_expect_join_rejection = true
		elif argument == "--network-disconnect-choice-test":
			_network_disconnect_choice_test = true
		elif argument == "--network-discovery-test":
			_network_discovery_test = true
		elif argument == "--network-host-disconnect-test":
			_network_host_disconnect_test = true
		elif argument.begins_with("--expected-players="):
			_expected_players = clampi(
				argument.trim_prefix("--expected-players=").to_int(),
				1,
				4
			)
	if _probe_dir.is_empty():
		_probe_dir = "tmp/network_acceptance_default"
	DirAccess.make_dir_recursive_absolute(_probe_dir)


# 加速完整跑局时替每个槽位提交当前三选一的第一项，验证正式流程能跨过所有选择节点。
func _auto_submit_special_choices() -> void:
	if _run == null or _run.get("phase") != 2:
		return
	var choices_by_slot: Dictionary = _run.get("_active_special_choices_by_slot")
	var selected_by_slot: Dictionary = _run.get("_selected_special_choices_by_slot")
	for slot: int in choices_by_slot:
		if selected_by_slot.has(slot):
			continue
		var choices: Array = choices_by_slot[slot]
		if choices.is_empty():
			continue
		_run.call(
			"_on_network_choice_received",
			slot,
			StringName(str(choices[0]))
		)


func _role_marker() -> String:
	return "host" if _role == "host" else "client_%d" % _client_index


func _file_exists(name: String) -> bool:
	return FileAccess.file_exists(_probe_dir.path_join(name))


func _write_marker(name: String) -> void:
	var file: FileAccess = FileAccess.open(_probe_dir.path_join(name), FileAccess.WRITE)
	if file != null:
		file.store_string("1")
		file.close()


func _log(message: String) -> void:
	print(message)
	var file: FileAccess = FileAccess.open(_probe_dir.path_join("events.log"), FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(_probe_dir.path_join("events.log"), FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(message)
	file.close()
