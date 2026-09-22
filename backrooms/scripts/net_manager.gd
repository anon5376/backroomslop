class_name NetManager
extends Node
## 2-player direct-IP co-op: host/join lifecycle, seed handshake, teardown,
## and the gameplay RPC surface. World state is seed-based: both peers build
## an identical world from the host's seed, so only actors sync over the wire
## (avatars at ~15 Hz, the entity via MultiplayerSynchronizer, one-shot
## gameplay events as reliable RPCs below). Host is authoritative for grabs,
## escapes and the run end; meters/inventory stay per-player local.

signal peer_joined(id: int)
signal peer_left(id: int)
signal join_failed(reason: String)
signal host_lost
signal begin_received(seed_value: int)
signal lobby_note(text: String)
signal avatar_state_received(peer: int, pos: Vector3, yaw: float, crouched: bool, sprinting: bool, planar: float)
signal pickup_despawned(net_id: int, kind: String, grabber: int)
signal glowstick_spawned(pos: Vector3, color_i: int, dropper: int)
signal peer_died(id: int, cause: String)
signal peer_escaped(id: int)
signal run_over(won: bool)
signal descend_received

const PORT: int = 7777
const GRAB_DISTANCE: float = 4.0

var _out: Dictionary = {}  # peer id -> "dead" / "escaped"; first terminal event wins
var _run_ended: bool = false
var _taken: Dictionary = {}

static var pending: Dictionary = {}  # auto host/join after scene reload
static var last_note: String = ""

var mode: String = "solo"  # solo | host | client
var begin_seed: int = -1
var remote_id: int = 0     # the other player's peer id (0 = none)
var noise_reports: int = 0  # server-side counter, MP test asserts on it

# Set by main.gd: lookup(net_id) -> kind String ("" if already taken).
var grab_lookup: Callable = Callable()


func in_session() -> bool:
	return mode == "host" or mode == "client"


func is_mp() -> bool:
	return mode != "solo"


func am_server() -> bool:
	return mode != "client"  # host or plain solo


func is_host() -> bool:
	return mode == "solo" or mode == "host"


func my_id() -> int:
	return multiplayer.get_unique_id()


func host_game(port: int = PORT) -> String:
	if in_session():
		return ""
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_server(port, 1)
	if err != OK:
		return "Could not host (port %d busy?)" % port
	multiplayer.multiplayer_peer = peer
	mode = "host"
	remote_id = 0
	_wire()
	return ""


func join_game(ip: String) -> String:
	if in_session():
		return ""
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_client(ip.strip_edges(), PORT)
	if err != OK:
		return "Could not reach %s" % ip
	multiplayer.multiplayer_peer = peer
	mode = "client"
	remote_id = 1
	_wire()
	return ""


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = "solo"
	remote_id = 0
	begin_seed = -1
	noise_reports = 0
	_reset_run()


func local_ip() -> String:
	for a: String in IP.get_local_addresses():
		if a.find(".") >= 0 and not a.begins_with("127."):
			return a
	return "127.0.0.1"


# ------------------------------------------------------------------ run begin

func begin_run(seed_value: int) -> void:
	# Host only: start the run on both machines from one seed.
	if mode != "host":
		return
	_reset_run()
	begin_seed = seed_value
	begin_received.emit(seed_value)
	_rpc_begin.rpc(seed_value)


@rpc("authority", "call_remote", "reliable")
func _rpc_begin(seed_value: int) -> void:
	_reset_run()
	begin_seed = seed_value
	begin_received.emit(seed_value)


# ------------------------------------------------------------------ avatar sync

func send_avatar_state(pos: Vector3, yaw: float, crouched: bool, sprinting: bool, planar: float) -> void:
	if mode == "client" and remote_id != 0:
		_rpc_avatar_state.rpc_id(1, pos, yaw, crouched, sprinting, planar)
	elif mode == "host" and remote_id != 0:
		_rpc_avatar_state.rpc_id(remote_id, pos, yaw, crouched, sprinting, planar)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_avatar_state(pos: Vector3, yaw: float, crouched: bool, sprinting: bool, planar: float) -> void:
	avatar_state_received.emit(multiplayer.get_remote_sender_id(), pos, yaw, crouched, sprinting, planar)


func send_noise(pos: Vector3, radius: float) -> void:
	# Client footsteps so the host-side entity hears the far player too.
	if mode == "client" and remote_id != 0:
		_rpc_noise.rpc_id(1, pos, radius)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_noise(pos: Vector3, radius: float) -> void:
	if not multiplayer.is_server():
		return
	noise_reports += 1
	get_tree().call_group("entity", "hear_noise", pos, radius)


# ------------------------------------------------------------------ pickups

func _reset_run() -> void:
	_out.clear()
	_taken.clear()
	_run_ended = false


func reset_level() -> void:
	# Pickup net ids restart at 0 on every level; deaths/escapes persist.
	_taken.clear()


func _game() -> GameManager:
	return get_tree().get_first_node_in_group("game") as GameManager


func _known_peer(id: int) -> bool:
	return id > 0 and (id == my_id() or id == remote_id)


func peer_is_alive(id: int) -> bool:
	if not _known_peer(id) or _run_ended or _out.has(id):
		return false
	var g := _game()
	if g == null or not g.is_run_active():
		return false
	if id == my_id():
		return not g.mp_dead and not g.mp_escaped and is_instance_valid(g.player) and not g.player.downed
	var main: Node = g.main_ref
	var avatar: Player = main.get("remote_avatar") as Player
	return is_instance_valid(avatar) and not avatar.downed and not bool(main.get("remote_downed")) and not bool(main.get("remote_gone"))


func request_grab(net_id: int) -> void:
	# Local player grabbed a pickup. Solo/host validates immediately,
	# a client asks the host (which validates against its own world).
	if not peer_is_alive(my_id()):
		return
	if mode == "client" and remote_id != 0:
		# Flush the current pose before the request (normal pose sync is 15 Hz).
		var p: Player = _game().player
		send_avatar_state(p.global_position, p.rotation.y, p.crouched, p.sprinting, 0.0)
		_rpc_grab_request.rpc_id(1, net_id)
	else:
		_server_grab(my_id(), net_id)


func request_glowstick(pos: Vector3, color_i: int) -> void:
	# Path markers are cosmetic and trusted: the host just rebroadcasts.
	if not peer_is_alive(my_id()) or not pos.is_finite():
		return
	if mode == "client" and remote_id != 0:
		_rpc_glow_request.rpc_id(1, pos, color_i)
	else:
		_server_glow(my_id(), pos, color_i)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_glow_request(pos: Vector3, color_i: int) -> void:
	if multiplayer.is_server():
		_server_glow(multiplayer.get_remote_sender_id(), pos, color_i)


func _server_glow(requester: int, pos: Vector3, color_i: int) -> void:
	if not multiplayer.is_server() or not peer_is_alive(requester) or not pos.is_finite():
		return
	glowstick_spawned.emit(pos, posmod(color_i, 3), requester)
	if mode == "host":
		_rpc_glow_spawn.rpc(pos, posmod(color_i, 3), requester)


@rpc("authority", "call_remote", "reliable")
func _rpc_glow_spawn(pos: Vector3, color_i: int, dropper: int) -> void:
	glowstick_spawned.emit(pos, color_i, dropper)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_grab_request(net_id: int) -> void:
	if multiplayer.is_server():
		_server_grab(multiplayer.get_remote_sender_id(), net_id)


func _server_grab(requester: int, net_id: int) -> void:
	if not multiplayer.is_server() or not peer_is_alive(requester) or _taken.has(net_id) or not grab_lookup.is_valid():
		return
	var g := _game()
	var pickups: Dictionary = g.main_ref.get("pickups")
	var pickup: Node3D = pickups.get(net_id) as Node3D
	if not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
		return
	var pos: Vector3 = g.player.global_position
	if requester != my_id():
		# Validate against the latest received pose, not the interpolated visual.
		var avatar: Player = g.main_ref.get("remote_avatar") as Player
		pos = avatar._remote_pos
	if not pos.is_finite() or pos.distance_to(pickup.global_position) > GRAB_DISTANCE:
		return
	var kind: String = grab_lookup.call(net_id)
	if kind == "":
		return  # already gone (or unknown id) — host wins, requester re-syncs
	_apply_despawn(net_id, kind, requester)
	if mode == "host":
		_rpc_despawn_pickup.rpc(net_id, kind, requester)


@rpc("authority", "call_remote", "reliable")
func _rpc_despawn_pickup(net_id: int, kind: String, grabber: int) -> void:
	_apply_despawn(net_id, kind, grabber)


func _apply_despawn(net_id: int, kind: String, grabber: int) -> void:
	if _taken.has(net_id):
		return
	_taken[net_id] = true
	pickup_despawned.emit(net_id, kind, grabber)


# ------------------------------------------------------------------ death / escape / end

func report_death(cause: String) -> void:
	# The local player went down (caught or collapsed).
	if _out.has(my_id()) or _run_ended:
		return
	if mode == "client" and remote_id != 0:
		_out[my_id()] = "dead"
		_rpc_i_died.rpc_id(1, cause)
	else:
		_apply_death(my_id(), cause)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_i_died(cause: String) -> void:
	if multiplayer.is_server():
		_apply_death(multiplayer.get_remote_sender_id(), cause)


func server_catch(id: int) -> void:
	# Host only: the entity touched that player's body.
	if mode != "host" or not peer_is_alive(id):
		return
	_apply_death(id, "caught")


func _apply_death(id: int, cause: String) -> void:
	if not _known_peer(id) or _out.has(id) or _run_ended:
		return
	_out[id] = "dead"
	# Send before emitting: listeners may synchronously end the run.
	if mode == "host":
		_rpc_peer_died.rpc(id, cause)
	peer_died.emit(id, cause)


@rpc("authority", "call_remote", "reliable")
func _rpc_peer_died(id: int, cause: String) -> void:
	_apply_death(id, cause)


func server_report_escape(id: int) -> void:
	# Host only: that player's body reached the exit area on the host.
	if mode != "host" or not peer_is_alive(id) or not _game().can_exit():
		return
	_out[id] = "escaped"
	_rpc_peer_escaped.rpc(id)
	peer_escaped.emit(id)


@rpc("authority", "call_remote", "reliable")
func _rpc_peer_escaped(id: int) -> void:
	if not _known_peer(id) or _out.has(id) or _run_ended:
		return
	_out[id] = "escaped"
	peer_escaped.emit(id)


func server_end_run(won: bool) -> void:
	if mode != "host" or _run_ended:
		return
	_run_ended = true
	_rpc_run_over.rpc(won)
	run_over.emit(won)


@rpc("authority", "call_remote", "reliable")
func _rpc_run_over(won: bool) -> void:
	if _run_ended:
		return
	_run_ended = true
	run_over.emit(won)


func server_descend() -> void:
	# Host only: a living body reached the stairs. The whole run goes down.
	if mode != "host":
		return
	var g: GameManager = _game()
	if g == null or not g.is_run_active() or g.is_final_level():
		return
	_rpc_descend.rpc()
	descend_received.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_descend() -> void:
	descend_received.emit()


# ------------------------------------------------------------------ plumbing

static func arm_rejoin(p_mode: String, p_ip: String, p_seed: int) -> void:
	pending = {"mode": p_mode, "ip": p_ip, "seed": p_seed}


static func take_pending() -> Dictionary:
	var p: Dictionary = pending
	pending = {}
	return p


func _wire() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(id: int) -> void:
	print("Net: peer %d connected" % id)
	remote_id = id
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("Net: peer %d left" % id)
	remote_id = 0
	peer_left.emit(id)


func _on_connected_to_server() -> void:
	print("Net: connected to server as %d" % multiplayer.get_unique_id())
	lobby_note.emit("connected")


func _on_connection_failed() -> void:
	print("Net: connection failed")
	leave()
	join_failed.emit("Connection failed (wrong IP? host offline?)")


func _on_server_disconnected() -> void:
	print("Net: server disconnected")
	leave()
	host_lost.emit()
