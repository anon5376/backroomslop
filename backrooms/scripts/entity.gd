class_name Stalker
extends CharacterBody3D
## The entity. DORMANT (looms far away) -> STALK (teleports closer on
## flicker events) -> HUNT (A* chase). Catch the player => SIGNAL LOST.

enum State { DORMANT, STALK, HUNT }

const HUNT_SPEED: float = 4.8
const CATCH_DIST: float = 1.2
const STARE_LIMIT: float = 3.0
const STARE_ANGLE: float = 0.13  # ~7 degrees
const LOSE_DIST: float = 45.0
const LOSE_TIME: float = 6.0
const REPLAN_TIME: float = 0.5

var state: int = State.DORMANT
var active: bool = false
var puppet: bool = false  # client-side replica: AI off, anim + sounds run locally
var maze: MazeGenerator = null
var player: Player = null
var extra_target: Node3D = null  # the partner avatar (host only), may be null
var astar: GridAStar = null
var _prev_hunt: bool = false  # puppet: screech on synced HUNT transitions

var _path: Array[Vector2i] = []
var _path_i: int = 0
var _replan_t: float = 0.0
var _stare_t: float = 0.0
var _lose_t: float = 0.0
var _suspicion: float = 0.0
var _last_known: Vector3 = Vector3.ZERO
var _heard_recently: float = 0.0

const EntityVisual := preload("res://scripts/entity_visual.gd")

var _visual: EntityVisual
var _screech: AudioStreamPlayer3D
var _steps: AudioStreamPlayer3D
var _voice: AudioStreamPlayer3D
var _creak_t: float = 10.0
var _game: Node = null


func _ready() -> void:
	add_to_group("entity")
	_build_body()


func setup(p_maze: MazeGenerator, p_player: Player, screech: AudioStream, drag: AudioStream, voice: AudioStream, game: Node) -> void:
	maze = p_maze
	player = p_player
	_game = game
	astar = GridAStar.new(MazeGenerator.GRID_W, MazeGenerator.GRID_H, maze.get_blocked())
	_screech.stream = screech
	_steps.stream = drag
	_voice.stream = voice
	state = State.DORMANT
	_path.clear()
	_path_i = 0
	_replan_t = 0.0
	_stare_t = 0.0
	_lose_t = 0.0
	_suspicion = 0.0
	_heard_recently = 0.0
	_prev_hunt = false
	velocity = Vector3.ZERO
	var cell: Vector2i = maze.random_entity_spawn()
	global_position = maze.cell_to_world(cell)


func _physics_process(delta: float) -> void:
	if puppet:
		if not active:
			return
		# Client replica: the host simulates; I just animate from synced state
		# (position/rotation/state arrive via MultiplayerSynchronizer).
		velocity = Vector3.ZERO
		if state == State.HUNT and not _prev_hunt and not _screech.playing:
			_screech.play()
			if _game != null and _game.has_method("on_hunt_started"):
				_game.on_hunt_started()
		_prev_hunt = state == State.HUNT
		_tick_anim(delta)
		return
	if not active or player == null or maze == null:
		return
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -0.5
	match state:
		State.DORMANT:
			_tick_dormant(delta)
		State.STALK:
			_tick_stalk(delta)
		State.HUNT:
			_tick_hunt(delta)
	_tick_stare(delta)
	_tick_anim(delta)
	move_and_slide()


func _target_alive(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	if target is Player and (target as Player).downed:
		return false
	if _game != null:
		if not _game.is_run_active():
			return false
		if target == player:
			return not _game.mp_dead and not _game.mp_escaped
		var net: Node = _game.get("net")
		if net != null and net.is_mp():
			return net.peer_is_alive(net.remote_id)
	return true


func _prey() -> Node3D:
	var local_alive: bool = _target_alive(player)
	var remote_alive: bool = _target_alive(extra_target)
	if not local_alive:
		return extra_target if remote_alive else null
	if remote_alive and global_position.distance_squared_to(extra_target.global_position) < global_position.distance_squared_to(player.global_position):
		return extra_target
	return player

func hear_noise(pos: Vector3, radius: float) -> void:
	if puppet or not active:
		return
	var d: float = global_position.distance_to(pos)
	if d > radius:
		return
	if state == State.HUNT:
		_last_known = pos
		_heard_recently = 1.0
		return
	# Closer = more suspicious. Two close noises (or one very close) => HUNT.
	_suspicion += clampf(1.2 - d / radius, 0.15, 1.0)
	if _suspicion >= 1.0:
		_start_hunt()
	elif state == State.STALK and d < radius * 0.6:
		_teleport_near(pos, 10.0, 20.0)


func on_flicker_event(cell: Vector2i) -> void:
	"""LightManager calls this when a fixture near the player dips."""
	if puppet or not active or state == State.HUNT:
		return
	if state == State.DORMANT:
		state = State.STALK
		return
	# STALK: 25% chance to reappear 15-25m from the player, in view.
	if randf() > 0.25:
		return
	_teleport_ring_player(15.0, 25.0, true)


func _tick_dormant(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_suspicion = maxf(0.0, _suspicion - 0.1 * _delta)
	var prey := _prey()
	if prey == null:
		return
	var d: float = global_position.distance_to(prey.global_position)
	if d < 12.0:
		# Seen too close: vanish far away.
		global_position = maze.cell_to_world(maze.random_entity_spawn(60, 200))
	elif d < 30.0:
		state = State.STALK


func _tick_stalk(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_suspicion = maxf(0.0, _suspicion - 0.08 * delta)
	var prey := _prey()
	if prey == null:
		return
	# Crouched prey is harder to notice: the sight trigger halves.
	var trigger: float = 5.0 if prey.get("crouched") == true else 10.0
	if global_position.distance_to(prey.global_position) < trigger and _can_see(prey):
		_start_hunt()


func _start_hunt() -> void:
	if state == State.HUNT:
		return
	state = State.HUNT
	var prey := _prey()
	if prey != null:
		_last_known = prey.global_position
	_heard_recently = 0.0
	_lose_t = 0.0
	_replan_t = 0.0
	_path.clear()
	_path_i = 0
	if not _screech.playing:
		_screech.play()
	if _game != null and _game.has_method("on_hunt_started"):
		_game.on_hunt_started()


func _tick_hunt(delta: float) -> void:
	var prey := _prey()
	if prey == null:
		velocity = Vector3.ZERO
		_path.clear()
		return
	var visible: bool = _can_see(prey)
	_heard_recently = maxf(0.0, _heard_recently - delta)
	if visible:
		_last_known = prey.global_position
	_replan_t -= delta
	if _replan_t <= 0.0:
		_replan_t = REPLAN_TIME
		_path = astar.find_path(maze.world_to_cell(global_position), maze.world_to_cell(_last_known))
		_path_i = 0
	var pp: Vector3 = prey.global_position
	var dist: float = global_position.distance_to(pp)
	if dist < CATCH_DIST and visible:
		velocity = Vector3.ZERO
		if prey == player:
			# It caught the local (host) player.
			if _game != null and _game.has_method("game_over"):
				_game.game_over("caught")
		elif _game != null:
			# It caught the partner's avatar — tell their machine; the run
			# continues for whoever is still alive.
			var net: Node = _game.get("net")
			if net != null and net.is_mp():
				net.server_catch(net.remote_id)
		return
	# Follow waypoints (skip the ones we're already on top of).
	while _path_i < _path.size():
		var wp: Vector3 = maze.cell_to_world(_path[_path_i])
		var flat := Vector2(wp.x - global_position.x, wp.z - global_position.z)
		if flat.length() < 1.0:
			_path_i += 1
		else:
			break
	var dir := Vector3.ZERO
	if _path_i < _path.size():
		var wp: Vector3 = maze.cell_to_world(_path[_path_i])
		dir = Vector3(wp.x - global_position.x, 0, wp.z - global_position.z).normalized()
	else:
		var remaining := Vector3(_last_known.x - global_position.x, 0, _last_known.z - global_position.z)
		if remaining.length() > 0.3:
			dir = remaining.normalized()
	velocity.x = dir.x * HUNT_SPEED
	velocity.z = dir.z * HUNT_SPEED
	if dist > 0.5:
		var target_yaw: float = atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(delta * 6.0, 1.0))
	if dist > LOSE_DIST or (not visible and _heard_recently <= 0.0):
		_lose_t += delta * (2.0 if prey.get("crouched") == true else 1.0)
		if _lose_t >= LOSE_TIME:
			state = State.STALK
			_suspicion = 0.0
			_path.clear()
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		_lose_t = 0.0


func _tick_stare(delta: float) -> void:
	if not _target_alive(player) or player.camera == null:
		_stare_t = 0.0
		return
	var eye: Vector3 = player.camera.global_position
	var target: Vector3 = global_position + Vector3(0, 1.4, 0)
	var to_e: Vector3 = target - eye
	var staring: bool = false
	if to_e.length() < 35.0:
		var fwd: Vector3 = -player.camera.global_transform.basis.z
		if fwd.angle_to(to_e.normalized()) < STARE_ANGLE and _has_los(eye, target):
			staring = true
	if staring:
		_stare_t += delta
	else:
		_stare_t = maxf(0.0, _stare_t - delta * 2.0)
	if _stare_t >= STARE_LIMIT and state != State.HUNT:
		_start_hunt()


func _can_see(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	var from: Vector3 = global_position + Vector3(0, 1.4, 0)
	var to: Vector3 = target.global_position + Vector3(0, 1.4, 0)
	var excluded: Array[RID] = [get_rid()]
	if target is CollisionObject3D:
		excluded.append(target.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, excluded)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _has_los(a: Vector3, b: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(a, b, 1, [get_rid(), player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _random_reachable_in_ring(center: Vector3, rmin: float, rmax: float, in_view: bool) -> Vector2i:
	var fallback := Vector2i(-1, -1)
	var cam_pos: Vector3 = player.camera.global_position
	var cam_fwd: Vector3 = -player.camera.global_transform.basis.z
	for attempt: int in 28:
		var ang: float = randf_range(0.0, TAU)
		var r: float = randf_range(rmin, rmax)
		var p := Vector3(center.x + cos(ang) * r, 0, center.z + sin(ang) * r)
		var cell: Vector2i = maze.world_to_cell(p)
		if cell.x < 1 or cell.y < 1 or cell.x >= MazeGenerator.GRID_W - 1 or cell.y >= MazeGenerator.GRID_H - 1:
			continue
		if maze.grid[cell.y * MazeGenerator.GRID_W + cell.x] != 0:
			continue
		if maze.dist_map[cell.y * MazeGenerator.GRID_W + cell.x] == -1:
			continue
		var spot: Vector3 = maze.cell_to_world(cell)
		if fallback.x == -1:
			fallback = cell
		if in_view:
			var to_spot: Vector3 = (spot + Vector3(0, 1.4, 0)) - cam_pos
			if cam_fwd.angle_to(to_spot.normalized()) > 1.0:
				continue
			if not _has_los(cam_pos, spot + Vector3(0, 1.4, 0)):
				continue
		return cell
	if fallback.x != -1:
		return fallback
	return maze.random_entity_spawn()


func _teleport_near(pos: Vector3, rmin: float, rmax: float) -> void:
	global_position = maze.cell_to_world(_random_reachable_in_ring(pos, rmin, rmax, false))


func _teleport_ring_player(rmin: float, rmax: float, in_view: bool) -> void:
	var prey := _prey()
	if prey == null:
		return
	global_position = maze.cell_to_world(_random_reachable_in_ring(prey.global_position, rmin, rmax, in_view and prey == player))
	_face_player()


func _face_player() -> void:
	var prey := _prey()
	if prey == null:
		return
	var d: Vector3 = prey.global_position - global_position
	rotation.y = atan2(d.x, d.z)


func _tick_anim(delta: float) -> void:
	# Derive anticipation from existing movement/target information only. Never
	# turn the body or choose a new target from presentation code.
	var direction: Vector3 = velocity
	if direction.length_squared() < 0.01 or state != State.HUNT:
		if is_instance_valid(player):
			direction = player.global_position - global_position
	direction = global_basis.inverse() * direction
	var contact: bool = _visual.animate(delta, state, velocity, puppet, direction)
	if contact and state == State.HUNT and is_instance_valid(player):
		if global_position.distance_to(player.global_position) < 30.0:
			_steps.pitch_scale = randf_range(0.9, 1.1)
			_steps.play()
	# Preserve the existing stalk-only creak cadence and hearing range.
	if state == State.STALK and is_instance_valid(player):
		_creak_t -= delta
		if _creak_t <= 0.0:
			_creak_t = randf_range(8.0, 20.0)
			if global_position.distance_to(player.global_position) < 25.0:
				_voice.pitch_scale = randf_range(0.7, 0.9)
				_voice.play()


func _build_body() -> void:
	_visual = EntityVisual.new()
	_visual.name = "Rig"
	add_child(_visual)
	_visual.build()
	_screech = AudioStreamPlayer3D.new()
	_screech.max_distance = 60.0
	_screech.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	_visual.add_child(_screech)
	_steps = AudioStreamPlayer3D.new()
	_steps.max_distance = 30.0
	_visual.add_child(_steps)
	_voice = AudioStreamPlayer3D.new()
	_voice.max_distance = 25.0
	_voice.volume_db = -6.0
	_visual.add_child(_voice)
