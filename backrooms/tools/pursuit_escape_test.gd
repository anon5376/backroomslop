extends SceneTree
## Run with --headless --fixed-fps 60 --script res://tools/pursuit_escape_test.gd
## Production scenes/controllers; only input and yaw are driven after initial placement.
## Fixed seed/ticks, bounded loops, and an independent watchdog. The runner must also
## reject ERROR / SCRIPT ERROR output: Godot can print script errors and still exit 0.

const TICKS := 60
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENTITY_SCENE := preload("res://scenes/entity.tscn")
const ACTIONS := ["move_left", "move_right", "move_forward", "move_back", "sprint",
	"crouch", "toggle_view", "flash", "interact", "eat_bread"]

class CatchRecorder extends Node:
	var mp_dead := false
	var mp_escaped := false
	var catches := 0
	func is_run_active() -> bool:
		return true
	func game_over(reason: String) -> void:
		if reason == "caught":
			catches += 1

var failures := 0
var fixture: Node3D
var player: Player
var entity: Stalker
var recorder: CatchRecorder
var tick_count := 0
var player_distance := 0.0
var entity_distance := 0.0
var player_contacts := 0
var entity_contacts := 0
var motion_ok := true
var floor_ok := true
var clock_ok := true

func _initialize() -> void:
	seed(17092026)
	Engine.physics_ticks_per_second = TICKS
	Engine.max_physics_steps_per_frame = 1
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("PURSUIT ESCAPE TEST: WATCHDOG TIMEOUT")
		quit(2))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1

func _box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	fixture.add_child(body)

func _fixture(cells: Array[Vector2i], p_start: Vector3, e_start: Vector3) -> void:
	fixture = Node3D.new()
	root.add_child(fixture)
	var maze := MazeGenerator.new()
	maze.grid.resize(MazeGenerator.GRID_W * MazeGenerator.GRID_H)
	maze.grid.fill(1)
	var borders: Dictionary = {}
	for cell: Vector2i in cells:
		maze.grid[cell.y * MazeGenerator.GRID_W + cell.x] = 0
		for x: int in range(-1, 2):
			for z: int in range(-1, 2):
				borders[cell + Vector2i(x, z)] = true
	for cell: Vector2i in cells:
		borders.erase(cell)
	for cell: Vector2i in borders:
		_box(maze.cell_to_world(cell) + Vector3(0, 1.5, 0), Vector3(3, 3, 3))
	_box(Vector3(0, -0.25, -60), Vector3(44, 0.5, 132))
	player = PLAYER_SCENE.instantiate() as Player
	entity = ENTITY_SCENE.instantiate() as Stalker
	recorder = CatchRecorder.new()
	fixture.add_child(recorder)
	# These are the ONLY actor position assignments in the test.
	player.position = p_start
	entity.position = e_start
	fixture.add_child(player)
	fixture.add_child(entity)
	player.active = true
	entity.player = player
	entity.maze = maze
	entity.astar = GridAStar.new(MazeGenerator.GRID_W, MazeGenerator.GRID_H, maze.get_blocked())
	entity._game = recorder
	entity.state = Stalker.State.STALK
	entity.active = true
	tick_count = 0
	player_distance = 0.0
	entity_distance = 0.0
	player_contacts = 0
	entity_contacts = 0
	motion_ok = true
	floor_ok = true
	clock_ok = true

func _step() -> void:
	var old_p := player.position
	var old_e := entity.position
	var old_tick := Engine.get_physics_frames()
	await physics_frame
	await process_frame # physics_frame is emitted BEFORE the controllers run.
	tick_count += 1
	clock_ok = clock_ok and Engine.get_physics_frames() == old_tick + 1
	var pd := player.position.distance_to(old_p)
	var ed := entity.position.distance_to(old_e)
	player_distance += pd
	entity_distance += ed
	# Detect teleports, bypasses, and accidental double stepping; never correct motion.
	motion_ok = motion_ok and pd <= Player.SPRINT_SPEED / TICKS + 0.015
	motion_ok = motion_ok and ed <= Stalker.HUNT_SPEED / TICKS + 0.015
	if tick_count > 5:
		floor_ok = floor_ok and player.is_on_floor() and entity.is_on_floor()
	player_contacts += player.get_slide_collision_count()
	entity_contacts += entity.get_slide_collision_count()

func _release() -> void:
	for action: String in ACTIONS:
		Input.action_release(action)

func _cleanup() -> void:
	_release()
	fixture.queue_free()
	await process_frame

func _physics_checks(label: String) -> void:
	check(clock_ok, label + ": exactly one physics tick per sample")
	check(motion_ok, label + ": speed-bounded continuous movement, no teleports")
	check(floor_ok, label + ": both production capsules remain on physical floor")

func _close_catch(with_wall: bool) -> void:
	var cells: Array[Vector2i] = []
	for x: int in range(95, 98):
		for z: int in range(95, 98):
			cells.append(Vector2i(x, z))
	_fixture(cells, Vector3(0.45, 0, 0), Vector3(-0.45, 0, 0))
	if with_wall:
		# Thin collider inside an open grid cell deliberately forces move_and_slide
		# to enforce the wall, rather than relying on the pathfinder to avoid it.
		_box(Vector3(0, 1.5, 0), Vector3(0.1, 3, 9))
	entity._start_hunt() # Initial state only; no AI calls/state writes after this.
	player.rotation.y = PI / 2.0 # Forward pushes left, directly into the wall.
	Input.action_press("move_forward")
	var stayed_close := true
	var stayed_separated := true
	var occluded := true
	for tick: int in range(120 if with_wall else 10):
		await _step()
		stayed_close = stayed_close and player.position.distance_to(entity.position) < Stalker.CATCH_DIST
		stayed_separated = stayed_separated and player.position.x >= 0.399 and entity.position.x <= -0.349
		occluded = occluded and not entity._can_see(player)
	if with_wall:
		check(stayed_close and occluded, "wall: within catch range but occluded for 120 physical ticks")
		check(stayed_separated and player_contacts > 0 and entity_contacts > 0,
			"wall: both capsules collide, neither crosses the thin wall")
		check(recorder.catches == 0, "wall: no game_over catch through wall")
	else:
		check(recorder.catches > 0, "open control: actual game_over catch callback fires")
	_physics_checks("wall" if with_wall else "open control")
	await _cleanup()

func _escape() -> void:
	var cells: Array[Vector2i] = []
	# Dogleg with a silent final leg: sprint the first three legs, then walk
	# (7m noise) around two more corners. Memory freezes at the last sprint
	# step; the hide sits 24m+ beyond, occluded and outside the sweep ring.
	for z: int in range(71, 98):  # leg A: world x=0, z=-75..3
		cells.append(Vector2i(96, z))
	for x: int in range(97, 100):  # leg B: world z=-75, x=3..9
		cells.append(Vector2i(x, 71))
	for z: int in range(67, 71):  # leg C: world x=9, z=-87..-78
		cells.append(Vector2i(99, z))
	for x: int in range(97, 99):  # leg D: world (3..9, -84), 6m
		cells.append(Vector2i(x, 68))
	for z: int in range(66, 68):  # leg E: world (3, -90..-84), 6m
		cells.append(Vector2i(97, z))
	for x: int in range(95, 97):  # leg F: world (-3..3, -90), 6m
		cells.append(Vector2i(x, 66))
	for z: int in range(62, 66):  # leg G: world (-3, -102..-90), 12m
		cells.append(Vector2i(95, z))
	_fixture(cells, Vector3(0, 0, -45), Vector3(0, 0, -30))
	player.rotation.y = PI # Look at the entity: production stare triggers HUNT.
	for tick: int in range(240):
		await _step()
		if entity.state == Stalker.State.HUNT:
			break
	check(entity.state == Stalker.State.HUNT, "escape: hunt acquired naturally by staring")
	print("TRACE acquired tick=%d separation=%.3f" % [tick_count, player.position.distance_to(entity.position)])
	# Sprint the first three legs, then walk (7m noise) through four corners.
	# Memory freezes at corner3; the hide sits 24m beyond, occluded from the
	# whole sweep ring by inner-corner walls. Walk clears 19m before SEARCH
	# starts, so the sweep never gets line of sight.
	var points: Array[Vector3] = [Vector3(0, 0, -75), Vector3(9, 0, -75), Vector3(9, 0, -84),
		Vector3(3, 0, -84), Vector3(3, 0, -90), Vector3(-3, 0, -90), Vector3(-3, 0, -102)]
	var waypoint := 0
	var sprint_ticks := 0
	var heard_ticks := 0
	var min_stamina := player.stamina
	var reached := false
	var max_separation := player.position.distance_to(entity.position)
	check(not entity.astar.find_path(entity.maze.world_to_cell(entity.position),
		entity.maze.world_to_cell(points.back())).is_empty(), "escape: hiding destination is path-reachable")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for tick: int in range(1600):
		if waypoint == 3 and Input.is_action_pressed("sprint"):
			Input.action_release("sprint")  # corner3: go quiet, memory freezes here
		var direction := points[waypoint] - player.position
		direction.y = 0
		if direction.length() < 0.3:
			print("TRACE corner=%d tick=%d player=%s entity=%s memory=%s stamina=%.3f" %
				[waypoint, tick_count, player.position, entity.position, entity._last_known, player.stamina])
			waypoint += 1
			if waypoint == points.size():
				reached = true
				break
			direction = points[waypoint] - player.position
		player.rotation.y = atan2(-direction.x, -direction.z)
		await _step()
		if player.sprinting:
			sprint_ticks += 1
		if entity._heard_recently > 0.0:
			heard_ticks += 1
		min_stamina = minf(min_stamina, player.stamina)
		max_separation = maxf(max_separation, player.position.distance_to(entity.position))
		if recorder.catches > 0:
			break
	_release() # Deceleration, residual footsteps and stamina are still production code.
	check(reached, "escape: reaches hiding place by movement around the corners")
	check(sprint_ticks > 60 and heard_ticks > 0 and min_stamina < 0.9,
		"escape: real sprint/stamina and audible production footsteps exercised")
	check(entity.state == Stalker.State.HUNT or entity.state == Stalker.State.SEARCH, "escape: still pursued when hiding begins")
	var hide_start := player.position
	var memory_at_hide := entity._last_known
	var memory_stable := true
	var silent_ticks := 0
	var lost_tick := -1
	var seen_hiding := 0
	var stable_stalk := 0
	var search_seen := false
	for tick: int in range(1800): # Thirty seconds: HUNT loss + full sweep + STALK settle.
		await _step()
		max_separation = maxf(max_separation, player.position.distance_to(entity.position))
		memory_stable = memory_stable and entity._last_known.is_equal_approx(memory_at_hide)
		if entity._heard_recently <= 0.0:
			silent_ticks += 1
		if entity._can_see(player):
			seen_hiding += 1
		if entity.state == Stalker.State.SEARCH:
			search_seen = true
		if entity.state == Stalker.State.STALK:
			if lost_tick < 0:
				lost_tick = tick
			stable_stalk += 1
		else:
			stable_stalk = 0
		if tick % 300 == 0:
			print("TRACE hide=%.2f player=%s entity=%s memory=%s state=%d lose=%.3f heard=%.3f catches=%d" %
				[float(tick) / TICKS, player.position, entity.position, entity._last_known,
				entity.state, entity._lose_t, entity._heard_recently, recorder.catches])
		if recorder.catches > 0:
			break
	check(recorder.catches == 0, "escape: never caught during sprint or hiding")
	check(player.position.distance_to(hide_start) < 0.6 and player.velocity.length() < 0.01,
		"escape: hiding is stationary after natural deceleration")
	check(seen_hiding == 0, "escape: hiding place stays occluded")
	check(max_separation < Stalker.LOSE_DIST, "escape: never uses distance-based hunt loss (max %.3fm)" % max_separation)
	check(memory_stable and silent_ticks == 1800, "escape: silent hiding never refreshes last-known position")
	check(entity_distance > 20.0 and player_distance > 60.0,
		"escape: both actors physically traverse the corridor, not a frozen-AI timeout")
	check(lost_tick >= 0 and stable_stalk >= 120,
		"escape: pursuit expires and remains STALK for at least two seconds")
	check(search_seen, "escape: entity swept the last-known area before giving up")
	print("RESULT escape: distance player=%.3f entity=%.3f sprint_ticks=%d heard_ticks=%d min_stamina=%.3f lost_hide_tick=%d stable_stalk_ticks=%d" %
		[player_distance, entity_distance, sprint_ticks, heard_ticks, min_stamina, lost_tick, stable_stalk])
	_physics_checks("escape")
	await _cleanup()

func _run() -> void:
	await _close_catch(true)
	await _close_catch(false)
	await _escape()
	print("PURSUIT ESCAPE TEST: %s" % ("ALL PASS" if failures == 0 else "FAILED (%d)" % failures))
	quit(0 if failures == 0 else 1)
