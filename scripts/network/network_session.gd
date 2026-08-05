extends Node

## 房间与局域网会话的唯一所有者；不持有场景节点，只在菜单和单局之间保存网络状态。

signal room_list_changed(rooms: Array[Dictionary])
signal roster_changed(roster: Array[Dictionary])
signal connection_state_changed(state: StringName, message: String)
signal match_started(seed: int, player_count: int, roster: Array[Dictionary])
signal match_returned_to_lobby
signal remote_input_received(slot: int, target_x: float, target_z: float, sequence: int)
signal pause_changed(paused: bool, owner_slot: int)
signal network_event_received(event: Dictionary)
signal choice_received(slot: int, choice_id: StringName)

const GAME_PORT: int = 28960
const DISCOVERY_PORT: int = 28961
const MAX_PLAYERS: int = 4
const PROTOCOL_VERSION: int = 1
const DISCOVERY_INTERVAL_SECONDS: float = 1.0
const DISCOVERY_EXPIRY_SECONDS: float = 3.0
# 首次加载工作簿和移动端资源可能占用数秒，给 ENet 握手留出完整启动窗口。
const CONNECTION_TIMEOUT_SECONDS: float = 30.0

enum Mode {
	OFFLINE,
	HOST,
	CLIENT,
}

enum RoomState {
	IDLE,
	LOBBY,
	IN_GAME,
}

var mode: Mode = Mode.OFFLINE
var room_state: RoomState = RoomState.IDLE
var room_name: String = "小厨西房间"
var room_id: String = ""
var local_slot: int = 0
var match_player_count: int = 1
var match_seed: int = 0
var protocol_fingerprint: String = ""
# 房主断线后让下一次主菜单打开直接落到联机入口。
var reopen_lan_entry_on_menu: bool = false
# 仅供固定种子烟雾测试使用；未提供参数时仍使用每局随机种子。
var _has_network_seed_override: bool = false
var _network_seed_override: int = 0
# 仅在命令行显式启用的本地网络扰动，默认均为零，不影响正式局域网手感。
var _simulation_delay_seconds: float = 0.0
var _simulation_loss_probability: float = 0.0
var _simulation_clock: float = 0.0
var _simulation_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _unreliable_queue: Array[Dictionary] = []

var _roster: Dictionary[int, Dictionary] = {}
var _rooms: Dictionary[String, Dictionary] = {}
var _discovery_socket: PacketPeerUDP
# 菜单/客户端使用临时源端口，避免本机多开时抢占房主的固定发现端口。
var _discovery_uses_ephemeral_port: bool = false
var _discovery_port: int = DISCOVERY_PORT
var _discovery_elapsed: float = 0.0
var _input_sequence: int = 0
var _pending_input: Vector2 = Vector2.ZERO
var _has_pending_input: bool = false
var _input_send_elapsed: float = 0.0
var _connection_wait_elapsed: float = 0.0
var _local_paused: bool = false
var _pause_owner_slot: int = 0
var _pending_rejected_peers: Dictionary[int, float] = {}
# 仅在自动发现验收参数下记录 UDP 绑定、查询和响应，正式运行不刷屏。
var _network_discovery_debug: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_read_network_test_options()
	_network_discovery_debug = OS.get_cmdline_user_args().has("--network-discovery-test")
	protocol_fingerprint = _build_protocol_fingerprint()
	_start_discovery_socket(false)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	_simulation_clock += maxf(0.0, delta)
	_flush_unreliable_queue()
	_tick_rejected_peers(delta)
	_poll_discovery()
	_input_send_elapsed += delta
	if _has_pending_input and _input_send_elapsed >= 1.0 / 30.0:
		_input_send_elapsed = 0.0
		_has_pending_input = false
		send_input(_pending_input.x, _pending_input.y)
	if mode == Mode.CLIENT and room_state == RoomState.IDLE and multiplayer.multiplayer_peer != null:
		_connection_wait_elapsed += maxf(0.0, delta)
		if _connection_wait_elapsed >= CONNECTION_TIMEOUT_SECONDS:
			leave_room()
			connection_state_changed.emit(&"error", "加入房间超时，请检查房主 IPv4 和防火墙")
	else:
		_connection_wait_elapsed = 0.0
	_discovery_elapsed += delta
	if _discovery_elapsed < DISCOVERY_INTERVAL_SECONDS:
		return
	_discovery_elapsed = 0.0
	if not is_host():
		_send_discovery_query()
	if mode == Mode.HOST and room_state != RoomState.IDLE:
		_broadcast_room()
	_prune_rooms()


func is_networked() -> bool:
	return mode != Mode.OFFLINE and multiplayer.multiplayer_peer != null


func is_host() -> bool:
	return mode == Mode.HOST and multiplayer.is_server()


func is_client() -> bool:
	return mode == Mode.CLIENT


# 断线回调到达前也不向已失联的房主发送输入或可靠请求。
func _has_connected_server_peer() -> bool:
	if not is_client() or multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_in_lobby() -> bool:
	return room_state == RoomState.LOBBY


func is_in_match() -> bool:
	return room_state == RoomState.IN_GAME


func get_roster() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: int in range(1, MAX_PLAYERS + 1):
		if not _roster.has(slot):
			continue
		result.append((_roster[slot] as Dictionary).duplicate(true))
	return result


func get_local_ipv4_addresses() -> PackedStringArray:
	var addresses: PackedStringArray = []
	for address: String in IP.get_local_addresses():
		if (
			address.contains(":")
			or address.begins_with("127.")
			or address.begins_with("169.254.")
		):
			continue
		addresses.append(address)
	return addresses


func player_color(slot: int) -> Color:
	return _player_color(slot)


func get_room_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room: Dictionary in _rooms.values():
		result.append(room.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("room_name", "")) < str(b.get("room_name", ""))
	)
	return result


func consume_reopen_lan_entry() -> bool:
	var should_reopen: bool = reopen_lan_entry_on_menu
	reopen_lan_entry_on_menu = false
	return should_reopen


func host_room(requested_name: String = "") -> Error:
	leave_room()
	_start_discovery_socket(true)
	var peer := ENetMultiplayerPeer.new()
	# 多留一个 ENet 握手位，让第5位玩家收到明确的“房间已满”，而不是在底层只看到连接失败。
	var error: Error = peer.create_server(GAME_PORT, MAX_PLAYERS)
	if error != OK:
		_start_discovery_socket(false)
		connection_state_changed.emit(&"error", "无法创建房间：端口 %d 不可用" % GAME_PORT)
		return error
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	room_state = RoomState.LOBBY
	room_name = requested_name.strip_edges()
	if room_name.is_empty():
		room_name = "小厨西房间"
	room_id = "%s-%s" % [str(Time.get_ticks_msec()), str(randi())]
	local_slot = 1
	match_player_count = 1
	_connection_wait_elapsed = 0.0
	_roster.clear()
	_roster[1] = _make_player_record(1, 1)
	connection_state_changed.emit(&"hosting", "房间已创建")
	roster_changed.emit(get_roster())
	return OK


func join_room(address: String) -> Error:
	var host_address: String = address.strip_edges()
	if host_address.is_empty():
		connection_state_changed.emit(&"error", "请输入房主 IPv4 地址")
		return ERR_INVALID_PARAMETER
	leave_room()
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(host_address, GAME_PORT)
	if error != OK:
		connection_state_changed.emit(&"error", "无法连接房主：%s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	room_state = RoomState.IDLE
	local_slot = 0
	_connection_wait_elapsed = 0.0
	connection_state_changed.emit(&"connecting", "正在加入房间")
	return OK


func leave_room() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	room_state = RoomState.IDLE
	local_slot = 0
	match_player_count = 1
	match_seed = 0
	room_id = ""
	room_name = "小厨西房间"
	_roster.clear()
	_pause_owner_slot = 0
	_local_paused = false
	_connection_wait_elapsed = 0.0
	_pending_rejected_peers.clear()
	_unreliable_queue.clear()
	_start_discovery_socket(false)
	roster_changed.emit(get_roster())
	connection_state_changed.emit(&"offline", "已离开房间")


func start_match() -> bool:
	if not is_host() or room_state != RoomState.LOBBY:
		return false
	match_player_count = _roster.size()
	if match_player_count < 1 or match_player_count > MAX_PLAYERS:
		return false
	match_seed = _network_seed_override if _has_network_seed_override else randi()
	room_state = RoomState.IN_GAME
	_match_started.rpc(match_seed, match_player_count, get_roster())
	_broadcast_room()
	return true


func return_to_lobby() -> void:
	if not is_host() or room_state != RoomState.IN_GAME:
		return
	room_state = RoomState.LOBBY
	match_seed = 0
	match_player_count = _roster.size()
	_match_returned_to_lobby.rpc()
	_broadcast_roster.rpc(get_roster())
	_broadcast_room()


func send_input(target_x: float, target_z: float) -> void:
	if not is_networked() or room_state != RoomState.IN_GAME:
		return
	_input_sequence += 1
	var payload: Dictionary = {
		"slot": local_slot,
		"x": target_x,
		"z": target_z,
		"sequence": _input_sequence,
	}
	if is_host():
		remote_input_received.emit(local_slot, target_x, target_z, _input_sequence)
		_queue_unreliable(&"input_broadcast", payload)
	else:
		_queue_unreliable(&"input_to_host", payload)


func queue_input(target_x: float, target_z: float) -> void:
	_pending_input = Vector2(target_x, target_z)
	_has_pending_input = true


func request_pause() -> void:
	if not is_networked() or room_state != RoomState.IN_GAME:
		return
	if is_host():
		_set_pause_state(true, local_slot)
	elif _has_connected_server_peer():
		_request_pause.rpc_id(1)


func request_resume() -> void:
	if not is_networked() or room_state != RoomState.IN_GAME:
		return
	if is_host():
		if _pause_owner_slot == local_slot or local_slot == 1:
			_set_pause_state(false, 0)
	elif _has_connected_server_peer():
		_request_resume.rpc_id(1)


func send_game_event(event: Dictionary) -> void:
	if not is_host() or room_state != RoomState.IN_GAME or not _has_connected_remote_peer():
		return
	_broadcast_game_event.rpc(event)


func submit_choice(choice_id: StringName) -> void:
	if not is_networked() or room_state != RoomState.IN_GAME:
		return
	if is_host():
		choice_received.emit(local_slot, choice_id)
	elif _has_connected_server_peer():
		_submit_choice.rpc_id(1, str(choice_id))


func send_snapshot(snapshot: Dictionary) -> void:
	if not is_host() or room_state != RoomState.IN_GAME:
		return
	_queue_unreliable(&"snapshot", snapshot)


# 单独发送世界动态包，避免玩家状态包和对象数组共同超过局域网单包 MTU。
func send_world_snapshot(snapshot: Dictionary) -> void:
	if not is_host() or room_state != RoomState.IN_GAME:
		return
	_queue_unreliable(&"world_snapshot", snapshot)


# 食客数组按周期切成小片；每片仍有序且不超过常见移动端MTU。
func send_world_customers_snapshot(cycle: int, customers: Array[Dictionary]) -> void:
	if not is_host() or room_state != RoomState.IN_GAME:
		return
	var chunk: Array[Dictionary] = []
	for record: Dictionary in customers:
		chunk.append(record)
		if chunk.size() < 3:
			continue
		_queue_unreliable(&"world_customers_fragment", {
			"cycle": cycle,
			"records": chunk,
			"complete": false,
		})
		chunk = []
	if not chunk.is_empty() or customers.is_empty():
		_queue_unreliable(&"world_customers_fragment", {
			"cycle": cycle,
			"records": chunk,
			"complete": true,
		})
	else:
		_queue_unreliable(&"world_customers_fragment", {
			"cycle": cycle,
			"records": [],
			"complete": true,
		})


# 门、奖励门和Boss另走独立通道；对象数组增长时不会拖大食客位置包。
func send_world_structures_snapshot(snapshot: Dictionary) -> void:
	if not is_host() or room_state != RoomState.IN_GAME:
		return
	_queue_unreliable(&"world_structures", snapshot)


# 奖励门数量较多时继续拆包，保持每个不可靠包都低于移动端常见MTU。
func send_world_drops_snapshot(snapshot: Dictionary) -> void:
	if not is_host() or room_state != RoomState.IN_GAME:
		return
	_queue_unreliable(&"world_drops", snapshot)


# 统计包按玩家拆分，避免四人局把计数器和满足明细挤进位置快照而超过ENet MTU。
func send_player_stats(player_slot: int, stats: Dictionary) -> void:
	if not is_host() or room_state != RoomState.IN_GAME:
		return
	_queue_unreliable(&"player_stats", {
		"slot": player_slot,
		"stats": stats,
	})


# 自动攻击按一次发射批量同步；远端只重放视觉，命中仍由房主裁决。
func send_projectile_burst(payload: Dictionary) -> void:
	if not is_host() or room_state != RoomState.IN_GAME:
		return
	_queue_unreliable(&"projectile_burst", payload)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_input(target_x: float, target_z: float, sequence: int) -> void:
	if not is_host() or room_state != RoomState.IN_GAME:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var sender_slot: int = _slot_for_peer(sender_id)
	if sender_slot <= 0:
		return
	remote_input_received.emit(sender_slot, clampf(target_x, -10.0, 10.0), clampf(target_z, -10.0, 20.0), sequence)
	_broadcast_input.rpc(sender_slot, target_x, target_z, sequence)


@rpc("authority", "call_local", "unreliable_ordered", 1)
func _broadcast_input(slot: int, target_x: float, target_z: float, sequence: int) -> void:
	remote_input_received.emit(slot, target_x, target_z, sequence)


@rpc("any_peer", "reliable")
func _request_pause() -> void:
	if not is_host() or room_state != RoomState.IN_GAME:
		return
	var slot: int = _slot_for_peer(multiplayer.get_remote_sender_id())
	if slot > 0:
		_set_pause_state(true, slot)


@rpc("any_peer", "reliable")
func _request_resume() -> void:
	if not is_host() or room_state != RoomState.IN_GAME:
		return
	var slot: int = _slot_for_peer(multiplayer.get_remote_sender_id())
	if slot == _pause_owner_slot or slot == 1:
		_set_pause_state(false, 0)


@rpc("any_peer", "reliable")
func _submit_choice(choice_text: String) -> void:
	if not is_host() or room_state != RoomState.IN_GAME:
		return
	var slot: int = _slot_for_peer(multiplayer.get_remote_sender_id())
	if slot > 0:
		choice_received.emit(slot, StringName(choice_text))


func _set_pause_state(paused: bool, owner_slot: int) -> void:
	_local_paused = paused
	_pause_owner_slot = owner_slot
	if _has_connected_remote_peer():
		_broadcast_pause.rpc(paused, owner_slot)
	else:
		# 断线竞态下保留房主本地状态，避免对已进入断开态的 ENet peer 发可靠包。
		_broadcast_pause(paused, owner_slot)


@rpc("authority", "call_local", "reliable")
func _broadcast_pause(paused: bool, owner_slot: int) -> void:
	_local_paused = paused
	_pause_owner_slot = owner_slot
	pause_changed.emit(paused, owner_slot)


@rpc("authority", "call_local", "reliable")
func _match_started(seed: int, player_count: int, roster: Array[Dictionary]) -> void:
	match_seed = seed
	match_player_count = player_count
	room_state = RoomState.IN_GAME
	_apply_roster(roster)
	match_started.emit(seed, player_count, get_roster())


@rpc("authority", "call_local", "reliable")
func _match_returned_to_lobby() -> void:
	room_state = RoomState.LOBBY
	match_seed = 0
	_apply_roster(get_roster())
	match_returned_to_lobby.emit()


@rpc("authority", "call_local", "reliable")
func _broadcast_roster(roster: Array[Dictionary]) -> void:
	_apply_roster(roster)
	roster_changed.emit(get_roster())


@rpc("authority", "call_remote", "reliable")
func _broadcast_game_event(event: Dictionary) -> void:
	network_event_received.emit(event)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _broadcast_snapshot(snapshot: Dictionary) -> void:
	network_event_received.emit({"type": "snapshot", "data": snapshot})


@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _broadcast_world_snapshot(snapshot: Dictionary) -> void:
	network_event_received.emit({"type": "world_snapshot", "data": snapshot})


@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _broadcast_world_customers_fragment(fragment: Dictionary) -> void:
	network_event_received.emit({"type": "world_customers_fragment", "data": fragment})


@rpc("authority", "call_remote", "unreliable_ordered", 5)
func _broadcast_world_structures(snapshot: Dictionary) -> void:
	network_event_received.emit({"type": "world_structures", "data": snapshot})


@rpc("authority", "call_remote", "unreliable_ordered", 6)
func _broadcast_world_drops(snapshot: Dictionary) -> void:
	network_event_received.emit({"type": "world_drops", "data": snapshot})


@rpc("authority", "call_remote", "unreliable_ordered", 4)
func _broadcast_player_stats(player_slot: int, stats: Dictionary) -> void:
	network_event_received.emit({
		"type": "player_stats",
		"slot": player_slot,
		"stats": stats,
	})


@rpc("authority", "call_remote", "unreliable_ordered", 7)
func _broadcast_projectile_burst(payload: Dictionary) -> void:
	network_event_received.emit({"type": "projectile_burst", "data": payload})


func _on_peer_connected(peer_id: int) -> void:
	if not is_host():
		return
	if room_state != RoomState.LOBBY:
		_reject_peer(peer_id, "本局已经开始，暂不接受中途加入")
		return
	# 先下发版本信息，真正入房由客户端显式请求，避免半连接占用槽位。
	_send_join_challenge.rpc_id(peer_id, PROTOCOL_VERSION, protocol_fingerprint, room_name)


@rpc("authority", "reliable")
func _send_join_challenge(version: int, fingerprint: String, host_room_name: String) -> void:
	if is_host() or mode != Mode.CLIENT:
		return
	if version != PROTOCOL_VERSION or fingerprint != protocol_fingerprint:
		leave_room()
		connection_state_changed.emit(&"error", "房间版本或数据不一致")
		return
	room_name = host_room_name
	_submit_join_request.rpc_id(1, PROTOCOL_VERSION, protocol_fingerprint)


@rpc("any_peer", "reliable")
func _submit_join_request(version: int, fingerprint: String) -> void:
	if not is_host():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if room_state != RoomState.LOBBY:
		_reject_peer(peer_id, "本局已经开始，暂不接受中途加入")
		return
	if version != PROTOCOL_VERSION or fingerprint != protocol_fingerprint:
		_reject_peer(peer_id, "房间版本或数据不一致")
		return
	if _roster.size() >= MAX_PLAYERS:
		_reject_peer(peer_id, "房间已满")
		return
	var slot: int = _first_free_slot()
	_roster[slot] = _make_player_record(slot, peer_id)
	_accept_join.rpc_id(peer_id, room_id, room_name, slot, get_roster())
	_broadcast_roster.rpc(get_roster())
	_broadcast_room()


@rpc("authority", "reliable")
func _accept_join(
	accepted_room_id: String,
	accepted_room_name: String,
	accepted_slot: int,
	roster: Array[Dictionary]
) -> void:
	if is_host() or mode != Mode.CLIENT:
		return
	room_id = accepted_room_id
	room_name = accepted_room_name
	local_slot = accepted_slot
	room_state = RoomState.LOBBY
	_apply_roster(roster)
	connection_state_changed.emit(&"joined", "已加入房间")
	roster_changed.emit(get_roster())


@rpc("authority", "reliable")
func _reject_join(message: String) -> void:
	leave_room()
	connection_state_changed.emit(&"error", message)


# 拒绝未入房的临时握手连接，避免满员或版本错误的客户端长期占用ENet连接位。
func _reject_peer(peer_id: int, message: String) -> void:
	_reject_join.rpc_id(peer_id, message)
	_pending_rejected_peers[peer_id] = 0.25


# 给可靠拒绝 RPC 留出一小段发送窗口，再释放未入房的临时连接。
func _tick_rejected_peers(delta: float) -> void:
	if _pending_rejected_peers.is_empty():
		return
	for peer_id: int in _pending_rejected_peers.keys().duplicate():
		var remaining: float = float(_pending_rejected_peers[peer_id]) - maxf(0.0, delta)
		if remaining > 0.0:
			_pending_rejected_peers[peer_id] = remaining
			continue
		_pending_rejected_peers.erase(peer_id)
		_disconnect_rejected_peer(peer_id)


func _disconnect_rejected_peer(peer_id: int) -> void:
	if not is_host() or multiplayer.multiplayer_peer == null:
		return
	multiplayer.multiplayer_peer.disconnect_peer(peer_id)


func _on_connected_to_server() -> void:
	connection_state_changed.emit(&"connected", "已连接房主，等待房间确认")


func _on_connection_failed() -> void:
	leave_room()
	connection_state_changed.emit(&"error", "加入房间失败")


func _on_server_disconnected() -> void:
	if mode == Mode.CLIENT:
		reopen_lan_entry_on_menu = true
		leave_room()
		connection_state_changed.emit(&"server_disconnected", "房主已离开房间")


func _on_peer_disconnected(peer_id: int) -> void:
	_pending_rejected_peers.erase(peer_id)
	if not is_host():
		return
	var slot: int = _slot_for_peer(peer_id)
	if slot <= 0:
		return
	_roster.erase(slot)
	_broadcast_roster.rpc(get_roster())
	_broadcast_room()
	if room_state == RoomState.IN_GAME:
		_broadcast_game_event.rpc({"type": "player_left", "slot": slot})


func _apply_roster(roster: Array[Dictionary]) -> void:
	_roster.clear()
	for record: Dictionary in roster:
		var slot: int = int(record.get("slot", 0))
		if slot >= 1 and slot <= MAX_PLAYERS:
			_roster[slot] = record.duplicate(true)
	if local_slot > 0 and not _roster.has(local_slot) and mode == Mode.CLIENT:
		local_slot = 0
	match_player_count = _roster.size()


func _make_player_record(slot: int, peer_id: int) -> Dictionary:
	return {
		"slot": slot,
		"peer_id": peer_id,
		"label": "P%d" % slot,
		"color": _player_color(slot).to_html(false),
	}


func _first_free_slot() -> int:
	for slot: int in range(1, MAX_PLAYERS + 1):
		if not _roster.has(slot):
			return slot
	return 0


func _slot_for_peer(peer_id: int) -> int:
	for slot: int in _roster:
		if int(_roster[slot].get("peer_id", 0)) == peer_id:
			return slot
	return 0


func _player_color(slot: int) -> Color:
	match slot:
		1:
			return Color("#e86b58")
		2:
			return Color("#e0b84f")
		3:
			return Color("#69b878")
		4:
			return Color("#64a9d8")
	return Color.WHITE


# 解析只用于验收的命令行参数；正式启动没有这些参数时保持原有随机和即时网络路径。
func _read_network_test_options() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--network-seed="):
			var seed_text: String = argument.trim_prefix("--network-seed=").strip_edges()
			if not seed_text.is_empty():
				_network_seed_override = seed_text.to_int()
				_has_network_seed_override = true
		elif argument.begins_with("--net-delay-ms="):
			var delay_text: String = argument.trim_prefix("--net-delay-ms=").strip_edges()
			_simulation_delay_seconds = clampf(delay_text.to_float() / 1000.0, 0.0, 2.0)
		elif argument.begins_with("--net-loss-percent="):
			var loss_text: String = argument.trim_prefix("--net-loss-percent=").strip_edges()
			_simulation_loss_probability = clampf(loss_text.to_float() / 100.0, 0.0, 0.25)
		elif argument.begins_with("--network-discovery-port="):
			var port_text: String = argument.trim_prefix("--network-discovery-port=").strip_edges()
			_discovery_port = clampi(port_text.to_int(), 1024, 65535)
	if _has_network_seed_override:
		_simulation_rng.seed = absi(_network_seed_override) + 104729
	else:
		_simulation_rng.randomize()


func get_network_test_options() -> Dictionary:
	return {
		"seed_override": _network_seed_override if _has_network_seed_override else null,
		"delay_ms": _simulation_delay_seconds * 1000.0,
		"loss_percent": _simulation_loss_probability * 100.0,
	}


# 在不改动可靠事件的前提下，对位置、输入和世界快照做可控延迟/丢包模拟。
func _queue_unreliable(kind: StringName, payload: Dictionary) -> void:
	if _simulation_loss_probability > 0.0 and _simulation_rng.randf() < _simulation_loss_probability:
		return
	var queued_payload: Dictionary = payload.duplicate(true)
	if _simulation_delay_seconds <= 0.0:
		_deliver_unreliable(kind, queued_payload)
		return
	_unreliable_queue.append({
		"due": _simulation_clock + _simulation_delay_seconds,
		"kind": kind,
		"payload": queued_payload,
	})


# Avoid emitting packets while ENet is already tearing down the last remote peer.
func _has_connected_remote_peer() -> bool:
	if not is_host() or multiplayer.multiplayer_peer == null:
		return false
	var enet_peer: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet_peer == null:
		return false
	for peer_id: int in multiplayer.get_peers():
		var packet_peer: ENetPacketPeer = enet_peer.get_peer(peer_id)
		if packet_peer != null and packet_peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
			return true
	return false


func _flush_unreliable_queue() -> void:
	if _unreliable_queue.is_empty():
		return
	var pending: Array[Dictionary] = []
	for entry: Dictionary in _unreliable_queue:
		if float(entry.get("due", 0.0)) > _simulation_clock:
			pending.append(entry)
			continue
		_deliver_unreliable(
			StringName(str(entry.get("kind", ""))),
			entry.get("payload", {}) as Dictionary
		)
	_unreliable_queue = pending


func _deliver_unreliable(kind: StringName, payload: Dictionary) -> void:
	if is_host() and not _has_connected_remote_peer():
		return
	if is_client() and not _has_connected_server_peer():
		return
	match kind:
		&"input_to_host":
			if is_client() and room_state == RoomState.IN_GAME:
				_submit_input.rpc_id(
					1,
					float(payload.get("x", 0.0)),
					float(payload.get("z", 0.0)),
					int(payload.get("sequence", 0))
				)
		&"input_broadcast":
			if is_host() and room_state == RoomState.IN_GAME:
				_broadcast_input.rpc(
					int(payload.get("slot", local_slot)),
					float(payload.get("x", 0.0)),
					float(payload.get("z", 0.0)),
					int(payload.get("sequence", 0))
				)
		&"snapshot":
			if is_host() and room_state == RoomState.IN_GAME:
				_broadcast_snapshot.rpc(payload)
		&"world_snapshot":
			if is_host() and room_state == RoomState.IN_GAME:
				_broadcast_world_snapshot.rpc(payload)
		&"world_customers_fragment":
			if is_host() and room_state == RoomState.IN_GAME:
				_broadcast_world_customers_fragment.rpc(payload)
		&"world_structures":
			if is_host() and room_state == RoomState.IN_GAME:
				_broadcast_world_structures.rpc(payload)
		&"world_drops":
			if is_host() and room_state == RoomState.IN_GAME:
				_broadcast_world_drops.rpc(payload)
		&"player_stats":
			if is_host() and room_state == RoomState.IN_GAME:
				_broadcast_player_stats.rpc(
					int(payload.get("slot", 0)),
					payload.get("stats", {}) as Dictionary
				)
		&"projectile_burst":
			if is_host() and room_state == RoomState.IN_GAME:
				_broadcast_projectile_burst.rpc(payload)


# 只有主机争取固定端口；其他实例使用临时源端口，通过查询回包发现房间。
func _start_discovery_socket(prefer_fixed_port: bool) -> void:
	if _discovery_socket != null:
		_discovery_socket.close()
	_discovery_socket = PacketPeerUDP.new()
	_discovery_uses_ephemeral_port = not prefer_fixed_port
	var bind_port: int = _discovery_port if prefer_fixed_port else 0
	var error: Error = _discovery_socket.bind(bind_port, "*")
	if error != OK:
		if _network_discovery_debug:
			print("NETWORK_DISCOVERY_BIND_ERROR port=%d error=%s" % [bind_port, error_string(error)])
		if not prefer_fixed_port:
			_discovery_socket = null
			return
		# 固定端口被其他程序占用时仍保留手输 IP；自动发现继续尝试查询回包。
		_discovery_socket = PacketPeerUDP.new()
		error = _discovery_socket.bind(0, "*")
		if error != OK:
			if _network_discovery_debug:
				print("NETWORK_DISCOVERY_FALLBACK_ERROR error=%s" % error_string(error))
			_discovery_socket = null
			return
		_discovery_uses_ephemeral_port = true
	_discovery_socket.set_broadcast_enabled(true)
	if _network_discovery_debug:
		print("NETWORK_DISCOVERY_SOCKET_READY ephemeral=%s" % _discovery_uses_ephemeral_port)


func _send_discovery_query() -> void:
	if _discovery_socket == null:
		return
	var payload: Dictionary = {
		"type": "query",
		"protocol": PROTOCOL_VERSION,
		"fingerprint": protocol_fingerprint,
	}
	var packet: PackedByteArray = JSON.stringify(payload).to_utf8_buffer()
	_discovery_socket.set_dest_address("255.255.255.255", _discovery_port)
	_discovery_socket.put_packet(packet)
	# 广播受限时，同机房主仍可从回环地址收到查询。
	_discovery_socket.set_dest_address("127.0.0.1", _discovery_port)
	_discovery_socket.put_packet(packet)
	if _network_discovery_debug:
		print("NETWORK_DISCOVERY_QUERY_SENT ephemeral=%s" % _discovery_uses_ephemeral_port)


func _poll_discovery() -> void:
	if _discovery_socket == null:
		return
	var changed: bool = false
	while _discovery_socket.get_available_packet_count() > 0:
		var packet: PackedByteArray = _discovery_socket.get_packet()
		var packet_ip: String = _discovery_socket.get_packet_ip()
		var packet_port: int = _discovery_socket.get_packet_port()
		var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if not parsed is Dictionary:
			continue
		var payload: Dictionary = parsed as Dictionary
		if str(payload.get("type", "")) == "query":
			if is_host() and room_state != RoomState.IDLE:
				if _network_discovery_debug:
					print("NETWORK_DISCOVERY_QUERY_RECEIVED ip=%s port=%d" % [packet_ip, packet_port])
				_send_room_response(packet_ip, packet_port)
			continue
		if int(payload.get("protocol", -1)) != PROTOCOL_VERSION:
			continue
		if str(payload.get("fingerprint", "")) != protocol_fingerprint:
			continue
		var id: String = str(payload.get("room_id", ""))
		if id.is_empty():
			continue
		if is_host() and id == room_id:
			# 房主自己的广播回环不应出现在房间列表，也不应覆盖真实客户端地址。
			continue
		payload["address"] = packet_ip
		payload["last_seen"] = Time.get_ticks_msec()
		if _network_discovery_debug:
			print("NETWORK_DISCOVERY_ROOM_RECEIVED room=%s address=%s" % [id, packet_ip])
		var previous_room: Dictionary = _rooms.get(id, {})
		if previous_room.is_empty() or (
			str(previous_room.get("room_name", "")) != str(payload.get("room_name", ""))
			or int(previous_room.get("players", 0)) != int(payload.get("players", 0))
			or str(previous_room.get("state", "")) != str(payload.get("state", ""))
			or str(previous_room.get("address", "")) != str(payload.get("address", ""))
		):
			changed = true
		_rooms[id] = payload
	if changed:
		room_list_changed.emit(get_room_list())


func _prune_rooms() -> void:
	var now: int = Time.get_ticks_msec()
	var changed: bool = false
	for id: String in _rooms.keys():
		var room: Dictionary = _rooms[id]
		if float(now - int(room.get("last_seen", 0))) / 1000.0 > DISCOVERY_EXPIRY_SECONDS:
			_rooms.erase(id)
			changed = true
	if changed:
		room_list_changed.emit(get_room_list())


func _broadcast_room() -> void:
	if _discovery_socket == null or room_id.is_empty():
		return
	var payload: Dictionary = _room_broadcast_payload()
	var packet: PackedByteArray = JSON.stringify(payload).to_utf8_buffer()
	_discovery_socket.set_dest_address("255.255.255.255", _discovery_port)
	_discovery_socket.put_packet(packet)
	# 同机多开时补发回环包，避免本机广播被系统或防火墙过滤。
	_discovery_socket.set_dest_address("127.0.0.1", _discovery_port)
	_discovery_socket.put_packet(packet)


func _send_room_response(address: String, port: int) -> void:
	if _discovery_socket == null or room_id.is_empty() or address.is_empty() or port <= 0:
		return
	_discovery_socket.set_dest_address(address, port)
	_discovery_socket.put_packet(JSON.stringify(_room_broadcast_payload()).to_utf8_buffer())


func _room_broadcast_payload() -> Dictionary:
	return {
		"protocol": PROTOCOL_VERSION,
	"fingerprint": protocol_fingerprint,
	"room_id": room_id,
	"room_name": room_name,
	"port": GAME_PORT,
	"discovery_port": _discovery_port,
		"players": _roster.size(),
		"max_players": MAX_PLAYERS,
		"state": "lobby" if room_state == RoomState.LOBBY else "in_game",
	}


func _build_protocol_fingerprint() -> String:
	var parts: PackedStringArray = ["protocol:%d" % PROTOCOL_VERSION]
	for path: String in [
		"res://balance_tables/时间轴.xlsx",
		"res://balance_tables/战斗规则.xlsx",
		"res://balance_tables/食客.xlsx",
		"res://balance_tables/武器.xlsx",
		"res://balance_tables/普通强化.xlsx",
		"res://balance_tables/特殊强化.xlsx",
	]:
		if not FileAccess.file_exists(path):
			parts.append("missing:%s" % path)
			continue
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		parts.append("%s:%s" % [path, str(_hash_bytes(bytes))])
	return str(_hash_bytes("|".join(parts).to_utf8_buffer()))


# 不依赖引擎类型 hash；限制中间值后生成跨设备稳定的工作簿指纹。
func _hash_bytes(bytes: PackedByteArray) -> int:
	var hash_value: int = 17
	for byte_value: int in bytes:
		hash_value = (hash_value * 31 + byte_value) % 2147483647
	return hash_value
