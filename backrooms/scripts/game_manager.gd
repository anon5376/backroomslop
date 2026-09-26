class_name GameManager
extends Node
## Game state machine + save data. MENU -> PLAYING <-> PAUSED -> DEAD/WON.
## Restarts go through scene reload with pending_seed (statics survive reload).

enum GState { MENU, PLAYING, PAUSED, DEAD, WON }

signal run_started
signal level_changed(index: int)

static var pending_seed: int = -1  # -1 = show menu after reload

const SAVE_PATH: String = "user://backrooms.cfg"

var state: int = GState.MENU
var maze: MazeGenerator = null
var player: Player = null
var entity: Stalker = null
var lights: LightManager = null
var scare: ScareDirector = null
var audio: AudioManager = null
var ui: UIManager = null
var world_root: Node3D = null
var main_ref: Node = null

var current_seed: int = 0
var level_index: int = 0
var _descending: bool = false
var elapsed: float = 0.0
var hunger: float = 1.0
var thirst: float = 1.0
var inv_water: int = 0
var inv_bread: int = 0
var net: Node = null  # NetManager when in co-op (set by main)
var mp_dead: bool = false  # local player downed — spectate, run continues
var _down_cause: String = "caught"
var mp_escaped: bool = false  # local player reached the exit — spectate
var _collapse_t: float = 0.0
var _pulse_t: float = 0.0
var _mark_file: FileAccess = null
var _mark_t0: int = 0
var best_time_ms: int = -1
var last_seed: int = 0
var sensitivity: float = 0.0022
var preset: String = "High"
var vhs_enabled: bool = false
var fov: float = 75.0
var glowsticks: int = 0
var _glow_color_i: int = 0


func _ready() -> void:
	# Receive resume keys during a solo tree pause; simulation is gated below.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game")
	_load_save()


func _process(delta: float) -> void:
	if not is_run_active() or get_tree().paused:
		return
	if net != null and net.is_mp():
		_mp_poll_exits()
	if not is_run_active():
		return
	if mp_dead or mp_escaped:
		return  # spectating: my meters stopped when I went down / got out
	elapsed += delta
	# Survival meters: thirst empties in ~4 min, hunger in ~6.
	thirst = maxf(0.0, thirst - delta / 240.0)
	hunger = maxf(0.0, hunger - delta / 360.0)
	# Distress pulse while a meter sits at zero.
	_pulse_t -= delta
	if (thirst <= 0.0 or hunger <= 0.0) and _pulse_t <= 0.0:
		_pulse_t = 15.0
		if ui != null:
			ui.static_burst(0.25)
	# Collapse if both stay empty for a minute.
	if thirst <= 0.0 and hunger <= 0.0:
		_collapse_t += delta
		if _collapse_t >= 60.0:
			game_over("collapsed")
			return
	else:
		_collapse_t = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if state == GState.PLAYING and is_inventory_open():
			ui.toggle_inventory()
		elif state == GState.PLAYING:
			pause()
		elif state == GState.PAUSED:
			resume()
	elif event.is_action_pressed("restart"):
		if state == GState.DEAD or state == GState.WON:
			restart_same_seed()
		elif state == GState.PLAYING and not mp_dead and not mp_escaped:
			# R doubles as the supply-pack key mid-run.
			ui.toggle_inventory()
	elif event.is_action_pressed("drop_glow"):
		if state == GState.PLAYING and not mp_dead and not mp_escaped and player.active:
			drop_glowstick()


func is_playing() -> bool:
	return state == GState.PLAYING


func is_run_active() -> bool:
	return state == GState.PLAYING or (state == GState.PAUSED and net != null and net.is_mp())


func can_exit() -> bool:
	var campaign: Node = main_ref.get_node_or_null("Campaign") if main_ref != null else null
	return campaign == null or not campaign.has_method("can_exit") or bool(campaign.call("can_exit"))


func is_final_level() -> bool:
	return level_index >= MazeGenerator.FINAL_LEVEL


func start_game(seed_value: int) -> void:
	_mark_begin()
	ui.show_loading("Tuning the fluorescents...")
	await get_tree().process_frame
	await get_tree().process_frame
	current_seed = seed_value
	last_seed = seed_value
	level_index = 0
	elapsed = 0.0
	hunger = 1.0
	thirst = 1.0
	inv_water = 0
	inv_bread = 0
	glowsticks = 3
	_glow_color_i = 0
	mp_dead = false
	mp_escaped = false
	player.downed = false
	_collapse_t = 0.0
	_pulse_t = 0.0
	if not await _build_level():
		push_error("GameManager: maze generation failed, aborting start")
		return
	# Go.
	state = GState.PLAYING
	player.active = true
	entity.active = true
	entity._face_player()
	lights.active = true
	scare.active = true
	audio.set_level_ambience(level_index)
	audio.start_ambience()
	ui.show_hud(current_seed)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_save()
	_mark("hud shown - run started")
	_mark_end()
	run_started.emit()


func _level_seed() -> int:
	# Deterministic per run: both co-op peers rebuild identical levels.
	return current_seed + level_index * 977


func _build_level() -> bool:
	maze = MazeGenerator.new()
	maze.level_index = level_index
	var used: int = maze.generate_with_validation(_level_seed())
	if used == -1:
		return false
	_mark("generated L%d (seed %d)" % [level_index, used])
	ui.set_loading_stage("Pouring the carpet...")
	await get_tree().process_frame
	var fresh_root := Node3D.new()
	fresh_root.name = "WorldBuilding"
	main_ref.add_child(fresh_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = used
	var mats: Dictionary = TextureFactory.load_materials(rng, level_index)
	_mark("materials ready")
	ui.set_loading_stage("Raising the walls...")
	await get_tree().process_frame
	maze.build_world(fresh_root, mats)
	_mark("static world built")
	ui.set_loading_stage("Sinking the chairs...")
	await get_tree().process_frame
	var info: Dictionary = maze.build_dressing(fresh_root, mats, audio)
	_mark("dressing placed")
	# Swap worlds only once the new one stands: nobody ever falls through.
	if world_root != null and is_instance_valid(world_root):
		main_ref.remove_child(world_root)
		world_root.queue_free()
	world_root = fresh_root
	world_root.name = "World"
	# Spawn player.
	player.global_position = (info["spawn_pos"] as Vector3) + Vector3(0, 0.1, 0)
	player.rotation.y = float(info["spawn_yaw"])
	player.velocity = Vector3.ZERO
	player.mouse_sens = sensitivity
	player.audio = audio
	player.game = self
	# Spawn entity.
	entity.setup(maze, player, audio.screech_stream, audio.drag_stream, audio.creak_stream, self)
	# Wire managers.
	if lights.maze == null:
		lights.setup(maze, player, audio.hum_stream)
		lights.flicker_event.connect(entity.on_flicker_event)
	else:
		lights.retarget_maze(maze)
	scare.setup(self, lights, maze, player, entity, ui, info["panel_materials"], audio.screech_stream)
	if is_final_level():
		(info["exit_area"] as Area3D).body_entered.connect(_on_exit_entered)
	else:
		(info["stairs_area"] as Area3D).body_entered.connect(_on_stairs_entered)
	var campaign: Node = main_ref.get_node_or_null("Campaign")
	if campaign != null and bool(campaign.get("started")):
		campaign.call("_build_level_stations")
		campaign.call("_update_visuals")
	_mark("actors spawned")
	return true


func descend() -> void:
	# One way down. Meters, inventory and campaign progress carry over.
	if _descending or not is_run_active() or is_final_level():
		return
	_descending = true
	var campaign: Node = main_ref.get_node_or_null("Campaign")
	if campaign != null and bool(campaign.get("_read_open")):
		campaign.call("_close_reader")
	player.active = false
	ui.show_loading("Descending to %s..." % MazeGenerator.LEVEL_NAMES[level_index + 1])
	level_index += 1
	if not await _build_level():
		push_error("GameManager: level build failed, aborting descend")
		_descending = false
		return
	if net != null and net.has_method("reset_level"):
		net.call("reset_level")
	player.active = not (mp_dead or mp_escaped)
	audio.set_level_ambience(level_index)
	ui.show_hud(current_seed)
	ui.show_level_banner(MazeGenerator.LEVEL_NAMES[level_index])
	level_changed.emit(level_index)
	_descending = false


func _mark_begin() -> void:
	_mark_t0 = Time.get_ticks_msec()
	_mark_file = FileAccess.open("user://startup.log", FileAccess.WRITE)
	_mark("start pressed")


func _mark(stage: String) -> void:
	if _mark_file != null:
		_mark_file.store_line("%d ms: %s" % [Time.get_ticks_msec() - _mark_t0, stage])
		_mark_file.flush()


func _mark_end() -> void:
	if _mark_file != null:
		_mark_file.close()
		_mark_file = null


func restart_same_seed() -> void:
	if net != null and net.is_mp():
		quit_to_menu()  # no mid-session restart in co-op
		return
	pending_seed = current_seed
	get_tree().paused = false
	get_tree().reload_current_scene()


func restart_new_seed() -> void:
	if net != null and net.is_mp():
		quit_to_menu()
		return
	pending_seed = randi()
	get_tree().paused = false
	get_tree().reload_current_scene()


func quit_to_menu() -> void:
	if net != null and net.is_mp():
		NetManager.last_note = "Left the session."
		net.leave()
	pending_seed = -1
	get_tree().paused = false
	get_tree().reload_current_scene()


func pause() -> void:
	if state != GState.PLAYING:
		return
	state = GState.PAUSED
	player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_pause()
	if net == null or not net.is_mp():
		get_tree().paused = true
	# In co-op the world never freezes: pausing just drops your guard.


func resume() -> void:
	if state != GState.PAUSED:
		return
	state = GState.PLAYING
	if net == null or not net.is_mp():
		get_tree().paused = false
	player.active = not (mp_dead or mp_escaped)
	if mp_dead or mp_escaped:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		main_ref.begin_spectate()
		if mp_dead:
			ui.show_mp_down(_down_cause, current_seed, elapsed)
		else:
			ui.show_mp_escaped()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		ui.show_hud(current_seed)


func game_over(cause: String) -> void:
	if not is_run_active():
		return
	if net != null and net.is_mp():
		_mp_local_down(cause)
		return
	state = GState.DEAD
	player.active = false
	entity.active = false
	lights.active = false
	scare.active = false
	audio.play_death()
	ui.static_burst(1.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_death(cause, current_seed, elapsed)


func _mp_local_down(cause: String) -> void:
	# Set flags before reporting: signals may synchronously resolve the run.
	if not is_run_active() or mp_dead or mp_escaped:
		return
	state = GState.PLAYING
	_down_cause = cause
	mp_dead = true
	player.downed = true
	player.active = false
	audio.play_death()
	ui.static_burst(1.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main_ref.begin_spectate()
	ui.show_mp_down(cause, current_seed, elapsed)
	net.report_death(cause)


func mp_die_from_network(cause: String) -> void:
	# The host's entity touched my avatar before I saw it happen.
	if not is_run_active() or mp_dead or mp_escaped:
		return
	_mp_local_down(cause)


func mp_escape_local() -> void:
	# I reached the exit; wait (spectating) until the run resolves.
	if not is_run_active() or mp_dead or mp_escaped:
		return
	state = GState.PLAYING
	mp_escaped = true
	player.downed = true
	player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main_ref.begin_spectate()
	ui.show_mp_escaped()


func mp_run_over(won: bool) -> void:
	# Host decided the run is over (everyone out, or everyone down).
	if not is_run_active():
		return
	state = GState.WON if won else GState.DEAD
	player.active = false
	entity.active = false
	lights.active = false
	scare.active = false
	main_ref.end_spectate()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if won:
		audio.play_win()
		if not mp_dead:
			var ms: int = int(elapsed * 1000.0)
			if best_time_ms < 0 or ms < best_time_ms:
				best_time_ms = ms
				_save()
		ui.show_mp_win(mp_dead, current_seed, elapsed)
	else:
		audio.play_death()
		ui.show_mp_loss(current_seed, elapsed)


func _mp_poll_exits() -> void:
	# Host-side distance check backing up the exit/stairs Area3Ds: synced
	# avatars ease into place and can slip past contact detection, and the
	# run must not hang if a body stops a hair from the trigger.
	if net == null or not net.is_mp() or not multiplayer.is_server():
		return
	if not is_run_active() or maze == null:
		return
	if not is_final_level():
		if _descending:
			return
		if not mp_dead and not mp_escaped and player != null and is_instance_valid(player) \
				and player.global_position.distance_to(maze.exit_world_pos) < 1.2:
			net.server_descend()
			return
		var av2: Node3D = main_ref.get("remote_avatar")
		if av2 != null and is_instance_valid(av2) and not bool(main_ref.get("remote_downed")) and not bool(main_ref.get("remote_gone")) \
				and av2.global_position.distance_to(maze.exit_world_pos) < 1.2:
			net.server_descend()
		return
	if not can_exit():
		return
	if not mp_dead and not mp_escaped and player != null and is_instance_valid(player) \
			and player.global_position.distance_to(maze.exit_world_pos) < 1.2:
		net.server_report_escape(net.my_id())
	var av: Node3D = main_ref.get("remote_avatar")
	if av != null and is_instance_valid(av) and not bool(main_ref.get("remote_downed")) and not bool(main_ref.get("remote_gone")) \
			and av.global_position.distance_to(maze.exit_world_pos) < 1.2:
		net.server_report_escape(net.remote_id)
	_server_check_run_end()


func _server_check_run_end() -> void:
	if not is_run_active():
		return
	# Host only: run ends when every player is down/out. Won if anyone got out.
	if net == null or not net.is_mp() or not multiplayer.is_server():
		return
	var states: Dictionary = main_ref.call("remote_out_state")
	var me_out: bool = mp_dead or mp_escaped
	var them_out: bool = bool(states["down"]) or bool(states["gone"])
	if not (me_out and them_out):
		return
	var won: bool = mp_escaped or bool(states["escaped"])
	net.server_end_run(won)


func win() -> void:
	if state != GState.PLAYING or not can_exit():
		return
	state = GState.WON
	player.active = false
	entity.active = false
	lights.active = false
	scare.active = false
	audio.play_win()
	var ms: int = int(elapsed * 1000.0)
	if best_time_ms < 0 or ms < best_time_ms:
		best_time_ms = ms
	_save()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_win(ms, current_seed)


func on_hunt_started() -> void:
	# Fired on the host sim and on client puppets (both hear the screech).
	if ui != null:
		ui.hunt_flash()
		ui.static_burst(0.6)


func drop_glowstick() -> void:
	if glowsticks <= 0 or player == null or main_ref == null:
		return
	var fwd: Vector3 = -player.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(0, 0, 1)
	var pos: Vector3 = player.global_position + fwd.normalized() * 0.8
	pos.y = 0.12
	var color_i: int = _glow_color_i
	_glow_color_i = (_glow_color_i + 1) % 3
	glowsticks -= 1
	if net != null and net.is_mp():
		net.request_glowstick(pos, color_i)
	else:
		main_ref.spawn_glowstick(pos, color_i)


func apply_settings(p_sens: float, p_preset: String, p_vhs: bool, p_fov: float = -1.0) -> void:
	sensitivity = p_sens
	preset = p_preset
	vhs_enabled = p_vhs
	if p_fov > 0.0:
		fov = clampf(p_fov, 60.0, 90.0)
	if player != null:
		player.mouse_sens = p_sens
	if main_ref != null and main_ref.has_method("apply_graphics_preset"):
		main_ref.apply_graphics_preset(p_preset)
	if ui != null:
		ui.set_vhs_enabled(p_vhs)
	_save()


func drink(amount: float) -> void:
	thirst = clampf(thirst + amount, 0.0, 1.0)


func eat(amount: float) -> void:
	hunger = clampf(hunger + amount, 0.0, 1.0)


func add_pickup(kind: String) -> void:
	if kind == "water":
		inv_water += 1
	else:
		inv_bread += 1


func drink_inv() -> bool:
	if inv_water <= 0 or thirst >= 0.95:
		return false
	inv_water -= 1
	drink(0.5)
	if ui != null:
		ui.refresh_inventory()
	return true


func eat_inv() -> bool:
	if inv_bread <= 0 or hunger >= 0.95:
		return false
	inv_bread -= 1
	eat(0.4)
	if ui != null:
		ui.refresh_inventory()
	return true


func is_inventory_open() -> bool:
	return ui != null and ui.is_inventory_open()


func get_move_factor() -> float:
	return 0.85 if hunger <= 0.0 else 1.0


func get_stamina_drain_mul() -> float:
	return 2.0 if thirst <= 0.0 else 1.0


func get_stamina_regen_mul() -> float:
	return 0.5 if hunger <= 0.0 else 1.0


func _on_exit_entered(body: Node3D) -> void:
	if not is_run_active() or not can_exit():
		return
	if net != null and net.is_mp():
		# Host validates exits: its area sees both real bodies.
		if not multiplayer.is_server():
			return
		if body == player:
			net.server_report_escape(net.my_id())
		elif body == main_ref.get("remote_avatar"):
			net.server_report_escape(net.remote_id)
		_server_check_run_end()
		return
	if body == player:
		win()


func _on_stairs_entered(body: Node3D) -> void:
	if not is_run_active() or is_final_level() or _descending:
		return
	if net != null and net.is_mp():
		# Host validates descents: its area sees both real bodies.
		if not multiplayer.is_server():
			return
		if body == player or body == main_ref.get("remote_avatar"):
			net.server_descend()
		return
	if body == player:
		descend()


func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best_time_ms = int(cfg.get_value("stats", "best_time_ms", -1))
	last_seed = int(cfg.get_value("stats", "last_seed", 0))
	sensitivity = float(cfg.get_value("settings", "sensitivity", 0.0022))
	preset = str(cfg.get_value("settings", "preset", "High"))
	vhs_enabled = bool(cfg.get_value("settings", "vhs", false))
	fov = clampf(float(cfg.get_value("settings", "fov", 75.0)), 60.0, 90.0)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "best_time_ms", best_time_ms)
	cfg.set_value("stats", "last_seed", last_seed)
	cfg.set_value("settings", "sensitivity", sensitivity)
	cfg.set_value("settings", "preset", preset)
	cfg.set_value("settings", "vhs", vhs_enabled)
	cfg.set_value("settings", "fov", fov)
	cfg.save(SAVE_PATH)
