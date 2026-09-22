extends Node
## Scene root: registers input, builds the Environment, creates and wires
## every manager, then boots to menu (or straight into a seeded run with
## --autoplay --seed N, which the headless smoke test uses).
## Co-op: owns the NetManager, spawns the partner avatar and entity sync on
## run start, routes net events into game/ui, and hosts the spectate camera.

const PlayerScene := preload("res://scenes/player.tscn")
const EntityScene := preload("res://scenes/entity.tscn")

var env: Environment
var audio: AudioManager
var game: GameManager
var ui: UIManager
var player: Player
var entity: Stalker
var lights: LightManager
var scare: ScareDirector
var net: NetManager

# Co-op runtime state (this machine's view of the OTHER player).
var remote_avatar: Player = null
var remote_downed: bool = false  # dead or escaped — the entity stops targeting
var remote_escaped: bool = false
var remote_gone: bool = false    # disconnected
var pickups: Dictionary = {}     # net_id -> Pickup (identical on both peers)
var glowsticks_alive: Array[Glowstick] = []
var spect_cam: Camera3D = null
var spect_target: Node3D = null

var boot_args: PackedStringArray = []
var mp_test_mode: String = ""  # "" | "host" | "join" (headless two-process test)
var mp_test_ip: String = "127.0.0.1"


func _enter_tree() -> void:
	_register_inputs()


func _ready() -> void:
	if "--verify-entity" in OS.get_cmdline_user_args():
		add_child(preload("res://tools/entity_visual_checks.gd").new())
		return
	_build_environment()
	audio = AudioManager.new()
	audio.name = "Audio"
	add_child(audio)
	net = NetManager.new()
	net.name = "Net"
	add_child(net)
	game = GameManager.new()
	game.name = "Game"
	game.main_ref = self
	game.net = net
	add_child(game)
	ui = UIManager.new()
	ui.name = "UI"
	add_child(ui)
	player = PlayerScene.instantiate() as Player
	player.name = "Player"
	add_child(player)
	entity = EntityScene.instantiate() as Stalker
	entity.name = "Stalker"
	add_child(entity)
	lights = LightManager.new()
	lights.name = "Lights"
	add_child(lights)
	scare = ScareDirector.new()
	scare.name = "Scare"
	add_child(scare)
	game.audio = audio
	game.ui = ui
	game.player = player
	game.entity = entity
	game.lights = lights
	game.scare = scare
	game.net = net
	ui.setup(game, player, entity, net)
	player._net = net
	net.grab_lookup = Callable(self, "_pickup_kind")
	_wire_net_signals()
	apply_graphics_preset(game.preset)
	ui.set_vhs_enabled(game.vhs_enabled)
	game.run_started.connect(_on_run_started)
	game.level_changed.connect(_on_level_changed)
	# Campaign exists before any boot path starts a run; its RPC path is stable.
	var campaign := preload("res://scripts/campaign.gd").new()
	campaign.name = "Campaign"
	add_child(campaign)
	# Boot flow: autoplay (tests / quick runs), headless MP test, or menu.
	boot_args = OS.get_cmdline_user_args()
	var restart_seed: int = GameManager.pending_seed
	var autoplay: bool = "--autoplay" in boot_args or restart_seed != -1
	var seed_value: int = restart_seed
	GameManager.pending_seed = -1
	for i: int in boot_args.size():
		if boot_args[i] == "--seed" and i + 1 < boot_args.size():
			if restart_seed == -1:
				seed_value = int(boot_args[i + 1])
			autoplay = true
		elif boot_args[i] == "--mp-host-test":
			mp_test_mode = "host"
		elif boot_args[i] == "--mp-join-test":
			mp_test_mode = "join"
		elif boot_args[i] == "--mp-ip" and i + 1 < boot_args.size():
			mp_test_ip = boot_args[i + 1]
	if mp_test_mode != "":
		autoplay = false
		var drv := MpDriver.new()
		drv.main = self
		drv.role = mp_test_mode
		add_child(drv)
		ui.show_menu()
		if mp_test_mode == "host":
			if seed_value == -1:
				seed_value = 424242
			var err: String = net.host_game()
			print("MPTEST host_game err=%s ip=%s" % [err, net.local_ip()])
			mp_test_seed = seed_value
		else:
			var jerr: String = net.join_game(mp_test_ip)
			print("MPTEST join_game err=%s" % jerr)
	elif autoplay:
		if seed_value == -1:
			seed_value = 1234
		if "--teleport-exit" in boot_args or "--force-hunt" in boot_args:
			game.run_started.connect(_bind_test_hooks.bind(boot_args), CONNECT_ONE_SHOT)
		game.start_game(seed_value)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		ui.show_menu()


var mp_test_seed: int = 424242


func _bind_test_hooks(args: PackedStringArray) -> void:
	# Headless test hooks (no effect on normal play).
	if "--teleport-exit" in args:
		player.global_position = game.maze.exit_world_pos + Vector3(0, 0.5, 0)
	if "--force-hunt" in args:
		entity.global_position = player.global_position + Vector3(2.5, 0, 0)
		entity._start_hunt()


func apply_graphics_preset(p: String) -> void:
	if p == "Low":
		env.sdfgi_enabled = false
		env.volumetric_fog_enabled = false
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.glow_enabled = false
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if _supports_forward_effects() else Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = 0.67
	else:
		env.sdfgi_enabled = _supports_forward_effects()
		env.volumetric_fog_enabled = _supports_forward_effects()
		env.ssao_enabled = _supports_forward_effects()
		env.ssil_enabled = _supports_forward_effects()
		env.glow_enabled = true
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = 1.0


func _supports_forward_effects() -> bool:
	return DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "forward_plus"


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.01)
	env.background_energy_multiplier = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.fog_light_energy = 0.8
	apply_level_env(0)
	env.glow_enabled = true
	env.sdfgi_enabled = _supports_forward_effects()
	env.volumetric_fog_enabled = _supports_forward_effects()
	env.ssao_enabled = _supports_forward_effects()
	env.ssao_intensity = 0.6
	env.ssao_radius = 0.8
	env.ssil_enabled = _supports_forward_effects()
	env.ssil_intensity = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.15
	env.glow_intensity = 0.55
	env.glow_strength = 0.85
	env.glow_bloom = 0.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func apply_level_env(level: int) -> void:
	# Each level breathes different air: warm hum, damp concrete, cold machine.
	match clampi(level, 0, 2):
		0:
			env.ambient_light_color = Color(0.40, 0.38, 0.31)
			env.ambient_light_energy = 0.32
			env.fog_light_color = Color(0.55, 0.52, 0.38)
			env.fog_light_energy = 0.8
			env.fog_density = 0.028
			env.tonemap_exposure = 0.85
		1:
			env.ambient_light_color = Color(0.36, 0.38, 0.32)
			env.ambient_light_energy = 0.32
			env.fog_light_color = Color(0.32, 0.36, 0.28)
			env.fog_light_energy = 0.5
			env.fog_density = 0.030
			env.tonemap_exposure = 0.85
		_:
			env.ambient_light_color = Color(0.22, 0.26, 0.34)
			env.ambient_light_energy = 0.25
			env.fog_light_color = Color(0.20, 0.26, 0.38)
			env.fog_light_energy = 0.8
			env.fog_density = 0.055
			env.tonemap_exposure = 0.80


func _register_inputs() -> void:
	_key_action("move_forward", [KEY_W, KEY_UP])
	_key_action("move_back", [KEY_S, KEY_DOWN])
	_key_action("move_left", [KEY_A, KEY_LEFT])
	_key_action("move_right", [KEY_D, KEY_RIGHT])
	_key_action("sprint", [KEY_SHIFT])
	_key_action("crouch", [KEY_CTRL, KEY_C])
	_key_action("flash", [KEY_F])
	_key_action("interact", [KEY_E])
	_key_action("pause", [KEY_ESCAPE, KEY_P])
	_key_action("restart", [KEY_R])
	_key_action("toggle_view", [KEY_V])
	_key_action("eat_bread", [KEY_Q])
	_key_action("drop_glow", [KEY_G])


func _key_action(action_name: String, keys: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for k: int in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k as Key
		InputMap.action_add_event(action_name, ev)


func _wire_net_signals() -> void:
	net.begin_received.connect(_on_mp_begin)
	net.peer_joined.connect(_on_peer_joined)
	net.peer_left.connect(_on_peer_left)
	net.join_failed.connect(func(r: String) -> void: ui.set_mp_status(r))
	net.host_lost.connect(_on_host_lost)
	net.lobby_note.connect(func(_t: String) -> void: ui.set_mp_status("Connected. Waiting for the host to start..."))
	net.avatar_state_received.connect(_on_avatar_state)
	net.pickup_despawned.connect(_on_pickup_despawned)
	net.glowstick_spawned.connect(func(pos: Vector3, color_i: int, _dropper: int) -> void: spawn_glowstick(pos, color_i))
	net.peer_died.connect(_on_peer_died)
	net.peer_escaped.connect(_on_peer_escaped)
	net.run_over.connect(func(won: bool) -> void: game.mp_run_over(won))
	net.descend_received.connect(func() -> void: game.descend())


func _process(delta: float) -> void:
	if spect_cam == null or not spect_cam.current:
		return
	if spect_target == null or not is_instance_valid(spect_target):
		return
	var want: Vector3 = spect_target.global_position + Vector3(2.2, 2.6, 2.2)
	spect_cam.global_position = spect_cam.global_position.lerp(want, minf(delta * 4.0, 1.0))
	spect_cam.look_at(spect_target.global_position + Vector3(0, 1.2, 0))


# ------------------------------------------------------------------ co-op flow

func _on_mp_begin(seed_value: int) -> void:
	if game.state != GameManager.GState.MENU:
		return
	entity.puppet = not net.am_server()
	if net.is_mp():
		_setup_entity_sync()
	game.start_game(seed_value)


func _on_peer_joined(_id: int) -> void:
	ui.set_mp_status("Partner connected! Press ENTER THE BACKROOMS to start.")
	if mp_test_mode == "host":
		print("MPTEST partner joined - beginning run seed=%d" % mp_test_seed)
		net.begin_run(mp_test_seed)


func _on_peer_left(_id: int) -> void:
	if game.state == GameManager.GState.MENU:
		ui.set_mp_status("Partner left.")
		return
	# Mid-run (or post-run) departure: this machine plays on.
	remote_gone = true
	remote_downed = true
	if remote_avatar != null and is_instance_valid(remote_avatar):
		remote_avatar.downed = true
		remote_avatar.queue_free()
		remote_avatar = null
	if entity != null:
		entity.extra_target = null
	if game.state == GameManager.GState.PLAYING and not game.mp_dead and not game.mp_escaped:
		ui.coop_note("Partner disconnected — you continue alone.")
	if net.mode == "host":
		game._server_check_run_end()


func _on_host_lost() -> void:
	if game.state == GameManager.GState.MENU:
		NetManager.last_note = "Host disconnected."
		ui.set_mp_status("Host disconnected.")
		return
	NetManager.last_note = "Host disconnected."
	game.quit_to_menu()


func _on_avatar_state(peer: int, pos: Vector3, yaw: float, crouched: bool, sprinting: bool, planar: float) -> void:
	if remote_avatar != null and is_instance_valid(remote_avatar) and peer == net.remote_id:
		remote_avatar.apply_remote_state(pos, yaw, crouched, sprinting, planar)


func _pickup_kind(net_id: int) -> String:
	var p: Pickup = pickups.get(net_id)
	if p == null or not is_instance_valid(p):
		return ""
	return p.kind


func _on_pickup_despawned(net_id: int, kind: String, grabber: int) -> void:
	var p: Pickup = pickups.get(net_id)
	if p != null and is_instance_valid(p):
		p.queue_free()
	pickups.erase(net_id)
	if grabber == net.my_id():
		game.add_pickup(kind)
		ui.refresh_inventory()


func spawn_glowstick(pos: Vector3, color_i: int) -> void:
	if game.world_root == null:
		return
	while glowsticks_alive.size() >= 12:
		var old: Glowstick = glowsticks_alive.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var g := Glowstick.build(color_i)
	g.position = pos
	game.world_root.add_child(g)
	glowsticks_alive.append(g)


func _on_peer_died(id: int, cause: String) -> void:
	if not net.is_mp():
		return
	if id == net.remote_id and remote_avatar != null and is_instance_valid(remote_avatar):
		remote_downed = true
		remote_avatar.downed = true
		if game.state == GameManager.GState.PLAYING and not game.mp_dead and not game.mp_escaped:
			ui.coop_note("Your partner was taken. The run continues.")
	elif id == net.my_id():
		# My body was caught on the host before my machine saw it.
		game.mp_die_from_network(cause)
	if net.mode == "host":
		game._server_check_run_end()


func _on_peer_escaped(id: int) -> void:
	if not net.is_mp():
		return
	if id == net.remote_id and remote_avatar != null and is_instance_valid(remote_avatar):
		remote_escaped = true
		remote_downed = true
		remote_avatar.downed = true
		if game.state == GameManager.GState.PLAYING and not game.mp_dead and not game.mp_escaped:
			ui.coop_note("Your partner made it out. Don't get caught.")
	elif id == net.my_id():
		game.mp_escape_local()  # host saw my body reach the exit
	if net.mode == "host":
		game._server_check_run_end()


func remote_out_state() -> Dictionary:
	return {"down": remote_downed, "escaped": remote_escaped, "gone": remote_gone}


func _on_run_started() -> void:
	if net != null and net.is_mp():
		_spawn_mp_actors()


func _on_level_changed(index: int) -> void:
	_collect_pickups()
	glowsticks_alive.clear()  # old markers went down with the old world
	if remote_avatar != null and is_instance_valid(remote_avatar):
		var spawn_pos: Vector3 = game.maze.cell_to_world(game.maze.spawn_cell)
		remote_avatar.position = spawn_pos + Vector3(0.9, 0.1, 0)
		remote_avatar._remote_pos = remote_avatar.position
		remote_avatar.velocity = Vector3.ZERO
	apply_level_env(index)


func _spawn_mp_actors() -> void:
	_collect_pickups()
	remote_downed = false
	remote_escaped = false
	remote_gone = false
	remote_avatar = PlayerScene.instantiate() as Player
	remote_avatar.name = "RemotePlayer"
	remote_avatar.remote = true
	remote_avatar.game = game
	var spawn_pos: Vector3 = game.maze.cell_to_world(game.maze.spawn_cell)
	remote_avatar.position = spawn_pos + Vector3(0.9, 0.1, 0)
	add_child(remote_avatar)
	remote_avatar._net = net
	if net.am_server():
		entity.extra_target = remote_avatar
	print("MPTEST actors spawned role=%s pickups=%d" % [mp_test_mode if mp_test_mode != "" else net.mode, pickups.size()])


func _collect_pickups() -> void:
	pickups.clear()
	if game.world_root == null:
		return
	for p: Node in game.world_root.find_children("*", "Pickup", true, false):
		pickups[(p as Pickup).net_id] = p


func _setup_entity_sync() -> void:
	if entity == null or entity.get_node_or_null("EntitySync") != null:
		return
	var cfg := SceneReplicationConfig.new()
	cfg.add_property(^".:global_position")
	cfg.add_property(^".:rotation")
	cfg.add_property(^".:state")
	var sync := MultiplayerSynchronizer.new()
	sync.name = "EntitySync"
	sync.replication_config = cfg
	entity.add_child(sync)


# ------------------------------------------------------------------ spectate

func begin_spectate() -> void:
	if spect_cam == null:
		spect_cam = Camera3D.new()
		spect_cam.fov = 65.0
		spect_cam.far = 600.0
		add_child(spect_cam)
	if remote_avatar != null and is_instance_valid(remote_avatar) and not remote_gone:
		spect_target = remote_avatar
	else:
		spect_target = entity
	if spect_target != null and spect_target is Node3D:
		spect_cam.global_position = spect_target.global_position + Vector3(2.2, 2.6, 2.2)
		spect_cam.look_at(spect_target.global_position + Vector3(0, 1.2, 0))
	spect_cam.current = true
	ui.show_spectate(true)


func end_spectate() -> void:
	if spect_cam != null:
		spect_cam.current = false
	if player != null and is_instance_valid(player):
		player.camera.current = true
	ui.show_spectate(false)


# ------------------------------------------------------------------ test driver

class MpDriver extends Node:
	## Automated two-process co-op acceptance run. Host and client drive real
	## netcode over localhost: sync both ways, entity sync, host-validated
	## grab, host-validated escape, shared win, then client disconnect.
	## Every step is a one-shot window: fires once, never repeats.
	var main: Node
	var role: String = ""
	var t: float = 0.0
	var started: bool = false
	var fails: int = 0
	var passes: int = 0
	var avatar_pos0: Vector3 = Vector3.ZERO
	var entity_pos0: Vector3 = Vector3.ZERO
	var fired: Dictionary = {}

	func _check(cond: bool, label: String) -> void:
		if cond:
			passes += 1
			print("MPTEST PASS [%s] %s" % [role, label])
		else:
			fails += 1
			printerr("MPTEST FAIL [%s] %s" % [role, label])

	func _once(key: String, lo: float) -> bool:
		if t >= lo and not fired.has(key):
			fired[key] = true
			return true
		return false

	func _process(delta: float) -> void:
		t += delta
		if not started:
			if main.game != null and main.game.is_playing():
				started = true
				t = 0.0
			return
		if role == "host":
			_host_tick()
		else:
			_client_tick()

	func _host_tick() -> void:
		if _once("avatar", 0.5):
			avatar_pos0 = main.remote_avatar.global_position
			_check(main.remote_avatar != null, "host sees partner avatar")
		elif _once("park", 2.5):
			# Park the entity 13m east of the partner so its synced state
			# changes; spawn faces north, so no stare-triggered hunt.
			main.entity.global_position = main.remote_avatar.global_position + Vector3(13, 0, 0)
			main.entity._face_player()
			# Freeze its AI for the rest of the run — otherwise flicker events
			# legitimately wake it and it hunts us mid-test. Position/state
			# still replicate, which is what the client asserts on.
			main.entity.active = false
		elif _once("noise", 6.0):
			_check(main.net.noise_reports >= 1, "host heard client footsteps (%d)" % main.net.noise_reports)
		elif _once("moved", 8.0):
			var d: float = main.remote_avatar.global_position.distance_to(avatar_pos0)
			_check(d > 4.0, "client avatar state synced (moved %.1fm)" % d)
			_check(not main.pickups.has(0), "grab of net_id 0 synced host-side")
		elif _once("descended1", 19.0):
			_check(main.game.level_index == 1, "host followed client down to level 1")
		elif _once("descended2", 26.5):
			_check(main.game.level_index == 2, "host followed client down to level 2")
		elif _once("campaign", 28.5):
			_check(main.get_node("Campaign").can_exit(), "client objectives replicated to host")
		elif _once("esc_seen", 33.5):
			_check(main.remote_escaped, "client escape seen host-side")
		elif _once("exit", 34.5):
			main.player.global_position = main.game.maze.exit_world_pos + Vector3(0, 0.5, 0)
		elif _once("won", 38.0):
			_check(main.game.state == GameManager.GState.WON, "host run over, won")
		elif _once("gone", 41.0):
			_check(main.remote_gone, "client disconnect handled")
			print("MPTEST host done passes=%d fails=%d" % [passes, fails])
			main.get_tree().quit(fails)

	func _move_to_station(id: int) -> void:
		var campaign: Node = main.get_node("Campaign")
		if campaign._read_open:
			campaign._close_reader()
		main.player.global_position = main.game.maze.cell_to_world(campaign.CELLS[id]) + Vector3(0, 0.1, 1.0)
		main.player.velocity = Vector3.ZERO

	func _move_to_stairs() -> void:
		var campaign: Node = main.get_node("Campaign")
		if campaign._read_open:
			campaign._close_reader()
		main.player.global_position = main.game.maze.exit_world_pos + Vector3(0, 0.5, 0)
		main.player.velocity = Vector3.ZERO

	func _client_tick() -> void:
		if _once("seed", 0.5):
			_check(main.game.current_seed == main.net.begin_seed, "client run started from host seed")
		elif _once("noise", 2.0):
			main.net.send_noise(main.player.global_position, 20.0)
		elif _once("noise_retry", 4.0):
			main.net.send_noise(main.player.global_position, 20.0)
		elif _once("ent0", 3.0):
			entity_pos0 = main.entity.global_position
		elif _once("grab", 5.0):
			var p: Pickup = main.pickups.get(0)
			_check(p != null, "client has pickup net_id 0")
			if p != null and is_instance_valid(p):
				main.player.global_position = p.global_position + Vector3(0, 0.5, 0)
		elif _once("grab_request", 6.0):
			var p: Pickup = main.pickups.get(0)
			if is_instance_valid(p):
				p.interact()
		elif _once("granted", 7.0):
			_check(main.game.inv_water == 1, "grab granted to client (inv_water=%d)" % main.game.inv_water)
		elif _once("despawned", 8.0):
			_check(not main.pickups.has(0), "despawn synced client-side")
		elif _once("esync", 9.5):
			var esync: bool = main.entity.state != Stalker.State.DORMANT or main.entity.global_position.distance_to(entity_pos0) > 5.0
			_check(esync, "entity state synced from host")
		elif _once("station0_move", 10.0):
			_move_to_station(0)
		elif _once("station0_use", 11.0):
			main.get_node("Campaign").request_interaction(0)
		elif _once("stairs0", 13.0):
			_check(main.get_node("Campaign").stage == 1, "first reference host-approved")
			_move_to_stairs()
		elif _once("descended1", 17.0):
			_check(main.game.level_index == 1, "stairwell descends to level 1")
			_move_to_station(1)
		elif _once("station1_use", 19.0):
			main.get_node("Campaign").request_interaction(1)
		elif _once("stairs1", 21.0):
			_check(main.get_node("Campaign").stage == 2, "listening circuit host-approved")
			_move_to_stairs()
		elif _once("descended2", 24.5):
			_check(main.game.level_index == 2, "stairwell descends to level 2")
			_move_to_station(2)
		elif _once("station2_use", 26.0):
			main.get_node("Campaign").request_interaction(2)
		elif _once("campaign", 28.0):
			_check(main.get_node("Campaign").can_exit(), "release pulse unlocks client exit")
			main.get_node("Campaign")._close_reader()
		elif _once("exit", 30.0):
			main.player.global_position = main.game.maze.exit_world_pos + Vector3(0, 0.5, 0)
		elif _once("esc", 33.0):
			_check(main.game.mp_escaped, "client escape validated by host")
		elif _once("won", 37.0):
			_check(main.game.state == GameManager.GState.WON, "client run over, won")
			print("MPTEST client done passes=%d fails=%d" % [passes, fails])
			main.get_tree().quit(fails)
