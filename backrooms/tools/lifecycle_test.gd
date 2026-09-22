extends SceneTree
## Headless lifecycle regressions using real managers, input dispatch and signals.

class ExitGate extends Node:
	var unlocked: bool = false
	func can_exit() -> bool:
		return unlocked

var fails: int = 0
var main: Node
var g: GameManager
var net: NetManager
var deaths: int = 0
var ends: int = 0
var grants: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("LIFECYCLE PASS ", label)
	else:
		fails += 1
		printerr("LIFECYCLE FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func _reset() -> void:
	paused = false
	net._reset_run()
	g.state = GameManager.GState.PLAYING
	g.mp_dead = false
	g.mp_escaped = false
	g.player.downed = false
	g.player.active = true
	g.player.position = Vector3.ZERO
	main.remote_downed = false
	main.remote_escaped = false
	main.remote_gone = false
	main.remote_avatar.downed = false
	main.remote_avatar.position = Vector3(10, 0, 0)
	main.remote_avatar._remote_pos = main.remote_avatar.position
	main.entity.active = false
	main.entity.extra_target = main.remote_avatar
	main.entity._game = g
	main.entity.player = g.player
	deaths = 0
	ends = 0

func _run() -> void:
	GameManager.pending_seed = -1
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.ui.set_physics_process(false)
	await process_frame
	g = main.game
	net = main.net
	g.set_process(false)
	main.player.set_physics_process(false)
	main.entity.set_physics_process(false)
	main.lights.set_process(false)
	main.scare.set_process(false)
	g.maze = MazeGenerator.new()
	g.maze.generate_with_validation(424242)
	g.maze.exit_world_pos = g.maze.cell_to_world(g.maze.exit_cell)
	g.best_time_ms = 0 # Avoid updating saved records.
	main.remote_avatar = load("res://scenes/player.tscn").instantiate()
	main.remote_avatar.remote = true
	main.add_child(main.remote_avatar)
	main.remote_avatar.set_process(false)
	main.remote_avatar.set_physics_process(false)
	_reset()
	g.pause()
	var elapsed_before: float = g.elapsed
	var thirst_before: float = g.thirst
	g._process(2.0)
	_check(paused and g.elapsed == elapsed_before and g.thirst == thirst_before, "solo pause freezes meters")
	_check(not main.player.can_process() and not main.entity.can_process(), "solo pause freezes simulation nodes")
	var key := InputEventAction.new()
	key.action = "pause"
	key.pressed = true
	root.push_input(key)
	_check(not paused and g.state == GameManager.GState.PLAYING and g.player.active, "pause key resumes through paused tree")
	_check(net.host_game(0) == "", "test host starts on ephemeral port")
	net.remote_id = 42
	net.peer_died.connect(func(_id: int, _cause: String) -> void: deaths += 1)
	net.run_over.connect(func(_won: bool) -> void: ends += 1)
	net.pickup_despawned.connect(func(_id: int, _kind: String, _who: int) -> void: grants += 1)
	_reset()
	g.pause()
	g._process(1.0)
	_check(not paused and g.elapsed > elapsed_before, "co-op local pause keeps survival ticking")
	g.mp_die_from_network("caught")
	_check(g.mp_dead and g.player.downed and not g.player.active, "network death accepted while locally paused")
	g.pause()
	g.resume()
	_check(not g.player.active and main.spect_cam.current and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "downed spectator resume stays spectating")
	g.mp_die_from_network("caught")
	_check(deaths == 1, "repeated death ignored")
	_reset()
	g.pause()
	g.mp_escape_local()
	g.pause()
	g.resume()
	_check(g.mp_escaped and not g.player.active and main.spect_cam.current, "escaped spectator resume stays spectating")
	g.pause()
	g.mp_run_over(true)
	_check(g.state == GameManager.GState.WON and not main.entity.active, "shared win accepted while locally paused")
	_reset()
	g.pause()
	g.mp_run_over(false)
	_check(g.state == GameManager.GState.DEAD, "shared loss accepted while locally paused")
	_reset()
	main.entity.position = Vector3.ZERO
	g.mp_dead = true
	_check(main.entity._prey() == main.remote_avatar, "dead host excluded from prey")
	g.mp_dead = false
	g.mp_escaped = true
	_check(main.entity._prey() == main.remote_avatar, "escaped host excluded from prey")
	main.remote_avatar.downed = true
	main.entity.velocity = Vector3.ONE
	main.entity._tick_hunt(0.01)
	_check(main.entity._prey() == null and main.entity.velocity == Vector3.ZERO, "no eligible prey stops hunt movement")
	_reset()
	g.player.position = Vector3(20, 0, 0)
	main.remote_avatar.position = Vector3.ZERO
	main.entity.position = Vector3.ZERO
	main.entity.maze = g.maze
	main.entity.astar = GridAStar.new(MazeGenerator.GRID_W, MazeGenerator.GRID_H, g.maze.get_blocked())
	main.entity._tick_hunt(0.01)
	_check(main.remote_downed and deaths == 1, "entity catches partner through net property")
	net.server_catch(42)
	net.server_report_escape(42)
	_check(deaths == 1 and not main.remote_escaped, "catch idempotent and dead partner cannot escape")
	_reset()
	var existing: Node = main.get_node_or_null("Campaign")
	if existing != null:
		existing.name = "CampaignUnderTest"
	var gate := ExitGate.new()
	gate.name = "Campaign"
	main.add_child(gate)
	g.win()
	net.server_report_escape(42)
	_check(g.state == GameManager.GState.PLAYING and not main.remote_escaped, "optional Campaign gate blocks solo and co-op wins")
	gate.unlocked = true
	g.level_index = 2  # exits only resolve on the final level
	for host_escaped: bool in [false, true]:
		_reset()
		g.mp_dead = not host_escaped
		g.mp_escaped = host_escaped
		g.player.downed = true
		main.remote_avatar.position = g.maze.exit_world_pos
		g.pause()
		g._mp_poll_exits()
		_check(main.remote_escaped and g.state == GameManager.GState.WON, "remote exit resolves with paused host out (escaped=%s)" % host_escaped)
		net.server_end_run(true)
		_check(ends == 1, "run end is idempotent")
	gate.free()
	if existing != null:
		existing.name = "Campaign"
	_reset()
	var pickup := Pickup.new()
	pickup.net_id = 900
	main.add_child(pickup)
	main.pickups[900] = pickup
	main.remote_avatar._remote_pos = Vector3(100, 0, 0)
	net._server_grab(42, 900)
	_check(grants == 0 and main.pickups.has(900), "distant pickup request rejected")
	main.remote_avatar._remote_pos = Vector3.ZERO
	main.remote_avatar.downed = true
	net._server_grab(42, 900)
	_check(grants == 0, "downed pickup request rejected")
	main.remote_avatar.downed = false
	main.remote_escaped = true
	main.remote_downed = true
	net._server_grab(42, 900)
	_check(grants == 0, "escaped pickup request rejected")
	main.remote_escaped = false
	main.remote_downed = false
	net._server_grab(99, 900)
	_check(grants == 0, "unknown requester rejected")
	net._server_grab(42, 900)
	net._server_grab(42, 900)
	_check(grants == 1 and not main.pickups.has(900), "nearby alive pickup granted exactly once")
	net.leave()
	main.free()
	print("LIFECYCLE TEST: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	quit(fails)
