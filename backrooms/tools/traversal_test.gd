extends SceneTree
## Navigation isolation only, NOT whole-game acceptance. Run with:
## godot --headless --path <project> --fixed-fps 60 --disable-render-loop \
##   --script res://tools/traversal_test.gd -- --traversal-seed 1234
## Fixed FPS removes wall-clock pacing, not collision substeps (still 1/60s).
## No position writes: the production start_game supplies the sole spawn.

const WALL_LIMIT_MS: int = 170000
const START_LIMIT_MS: int = 60000
const STUCK_SECONDS: float = 2.0
const ARRIVAL: float = 0.035

class PhysicsClock extends Node:
	signal step(delta: float)
	func _physics_process(delta: float) -> void:
		step.emit(delta)

var boot_ms: int = Time.get_ticks_msec()
var finished: bool = false
var player: Player
var maze: MazeGenerator
var game: GameManager
var campaign: Node
var clock: PhysicsClock
var planner: GridAStar
var route_label: String = "startup"
var route_index: int = -1
var route_from := Vector2i.ZERO
var route_to := Vector2i.ZERO
var target := Vector3.ZERO
var distance_walked: float = 0.0
var sim_seconds: float = 0.0
var movement_ticks: int = 0
var reached_cells: int = 0
var original_layer: int
var original_mask: int
var original_shape: Shape3D
var original_shape_transform: Transform3D
var last_contacts: Array[String] = []
var live_threats: bool = false
var step_distance: float = 0.0

func _initialize() -> void:
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() - boot_ms > WALL_LIMIT_MS:
		_fail("global wall deadline exceeded")
	return false

func _fail(reason: String) -> bool:
	if finished:
		return false
	finished = true
	var location: String = "not spawned"
	if is_instance_valid(player) and maze != null:
		location = "position=%s cell=%s target=%s remaining=%.3fm" % [
			player.global_position, maze.world_to_cell(player.global_position), target,
			_planar(player.global_position, target)]
	printerr("TRAVERSAL FAIL seed=%s leg=%s waypoint=%d edge=%s->%s %s reason=%s contacts=%s" % [
		game.current_seed if game != null else -1, route_label, route_index,
		route_from, route_to, location, reason, last_contacts])
	quit(1)
	return false

func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _body_intact() -> bool:
	return player.collision_layer == original_layer and player.collision_mask == original_mask \
		and not player.collision.disabled and player.collision.shape == original_shape \
		and player.collision.transform == original_shape_transform \
		and is_equal_approx((player.collision.shape as CapsuleShape3D).radius, 0.35) \
		and is_equal_approx((player.collision.shape as CapsuleShape3D).height, 1.8)

func _walk_to(point: Vector3) -> bool:
	target = point
	var initial_distance: float = _planar(player.global_position, target)
	var best: float = initial_distance
	var stalled: float = 0.0
	var travel: float = 0.0
	var budget: float = initial_distance / (Player.WALK_SPEED * 0.85) * 3.0 + 3.0
	while _planar(player.global_position, target) > ARRIVAL:
		var delta: float = await clock.step
		if finished:
			return false
		if game.state == GameManager.GState.WON:
			_on_state_changed(game.state)
			return false
		if game.state != GameManager.GState.PLAYING:
			return _fail("game left PLAYING during travel (state=%d)" % game.state)
		if not _body_intact() or not player.active or campaign._read_open:
			return _fail("body collision changed or movement/reader state invalid")
		if delta <= 0.0 or delta > 1.0 / 59.0:
			return _fail("unsafe physics step %.6f; use --fixed-fps 60" % delta)
		var before: Vector3 = player.global_position
		var wish: Vector3 = target - before
		wish.y = 0.0
		var speed: float = minf(Player.WALK_SPEED * player._move_factor(), wish.length() / delta)
		wish = wish.normalized() * speed
		player.velocity.x = wish.x
		player.velocity.z = wish.z
		player.velocity.y = -0.5 if player.is_on_floor() else player.velocity.y - 20.0 * delta
		player.move_and_slide()
		movement_ticks += 1
		sim_seconds += delta
		travel += delta
		distance_walked += _planar(before, player.global_position)
		if live_threats:
			player.rotation.y = atan2(-wish.x, -wish.z)
			player.camera.rotation = Vector3.ZERO
			step_distance += _planar(before, player.global_position)
			if step_distance >= Player.STEP_DIST_WALK:
				step_distance -= Player.STEP_DIST_WALK
				player._footstep()
		last_contacts.clear()
		for index: int in player.get_slide_collision_count():
			var collision: KinematicCollision3D = player.get_slide_collision(index)
			var collider: Object = collision.get_collider()
			last_contacts.append("%s script=%s point=%s normal=%s" % [
				collider.get_path() if collider is Node else str(collider),
				collider.get_script().resource_path if collider.get_script() != null else "none",
				collision.get_position(), collision.get_normal()])
		var remaining: float = _planar(player.global_position, target)
		if remaining < best - 0.01:
			best = remaining
			stalled = 0.0
		else:
			stalled += delta
		if player.global_position.y < -0.5 or player.global_position.y > 0.5:
			return _fail("left floor-level walking envelope")
		if stalled >= STUCK_SECONDS:
			return _fail("no 1cm forward progress for %.2fs" % stalled)
		if travel > budget:
			return _fail("waypoint travel deadline %.2fs exceeded" % budget)
	player.velocity = Vector3.ZERO
	return true

func _follow(goal: Vector2i, label_text: String) -> bool:
	route_label = label_text
	var start: Vector2i = maze.world_to_cell(player.global_position)
	var path: Array[Vector2i] = planner.find_path(start, goal)
	if path.is_empty():
		route_from = start
		route_to = goal
		return _fail("GridAStar found no route to accessible front/exit")
	print("TRAVERSAL ROUTE %s from=%s to=%s cells=%d" % [route_label, start, goal, path.size()])
	for index: int in path.size():
		route_index = index
		route_from = path[maxi(0, index - 1)]
		route_to = path[index]
		if index > 0 and absi(route_to.x - route_from.x) + absi(route_to.y - route_from.y) != 1:
			return _fail("non-cardinal GridAStar edge")
		if not await _walk_to(maze.cell_to_world(route_to)):
			return false
		if maze.world_to_cell(player.global_position) != route_to:
			return _fail("did not physically reach route cell")
		reached_cells += 1
	return true

func _run() -> void:
	var seed_value: int = 1234
	var args: PackedStringArray = OS.get_cmdline_user_args()
	live_threats = "--live-threats" in args
	for index: int in args.size():
		if args[index] == "--traversal-seed" and index + 1 < args.size():
			seed_value = int(args[index + 1])
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	GameManager.pending_seed = seed_value
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.game.state != GameManager.GState.PLAYING:
		await process_frame
		if finished:
			return
		if Time.get_ticks_msec() - boot_ms > START_LIMIT_MS:
			_fail("startup deadline exceeded")
			return
	game = current_scene.game
	maze = game.maze
	player = current_scene.player
	campaign = current_scene.get_node("Campaign")
	# Freeze threats only; retain their bodies, every prop and every world collider.
	if not live_threats:
		current_scene.entity.active = false
		current_scene.entity.set_physics_process(false)
		current_scene.entity.set_process(false)
		current_scene.scare.active = false
		current_scene.scare.set_process(false)
	player.set_physics_process(false)
	original_layer = player.collision_layer
	original_mask = player.collision_mask
	original_shape = player.collision.shape
	original_shape_transform = player.collision.transform
	clock = PhysicsClock.new()
	root.add_child(clock)
	await clock.step
	if campaign.stage != 0 or not campaign.started or maze.world_to_cell(player.global_position) != maze.spawn_cell:
		_fail("expected fresh campaign at production spawn")
		return
	# Equipment occupies the rear of its cell and faces +Z. Route to the south
	# neighbor, then walk north to its front. Reserve station cells in the local
	# planner only, so approach routes never cross through equipment from behind.
	# This does not modify maze.grid or world geometry; no replanning on blockage.
	var blocked: PackedByteArray = maze.get_blocked()
	for cell: Vector2i in campaign.CELLS:
		blocked[cell.y * MazeGenerator.GRID_W + cell.x] = 1
	planner = GridAStar.new(MazeGenerator.GRID_W, MazeGenerator.GRID_H, blocked)
	print("TRAVERSAL START seed=%d spawn=%s capsule=0.35x1.8 physics=60Hz time_scale=1 threats=%s" % [game.current_seed, player.global_position, "live" if live_threats else "frozen"])
	for id: int in 3:
		var cell: Vector2i = campaign.CELLS[id]
		var front_cell: Vector2i = cell + Vector2i(0, 1)
		if not await _follow(front_cell, "station_%d" % id):
			return
		route_from = front_cell
		route_to = cell
		if not await _walk_to(maze.cell_to_world(cell)):
			return
		var station: StaticBody3D = campaign.stations[id]
		if station.to_local(player.global_position).z < 0.65:
			_fail("station was not approached on accessible +Z front")
			return
		player.camera.look_at(station.global_position + Vector3(0, 1.35, 0.2))
		var origin: Vector3 = player.camera.global_position
		var query := PhysicsRayQueryParameters3D.create(origin, origin - player.camera.global_basis.z * 3.2)
		query.collide_with_areas = false
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider != station or campaign.focused_interactable() != station:
			_fail("production interaction ray missed station; hit=%s" % hit)
			return
		player._try_interact()
		if campaign.stage != id + 1 or not campaign._read_open:
			_fail("_try_interact did not advance stage/open reader; stage=%d" % campaign.stage)
			return
		campaign._close_reader()
		if campaign._read_open or not player.active:
			_fail("reader did not close/restore movement")
			return
		print("TRAVERSAL STATION PASS id=%d stage=%d position=%s ray=%s reader=closed" % [id, campaign.stage, player.global_position, station.get_path()])
		# Physically back out along the same clear approach before the next A* leg.
		route_from = cell
		route_to = front_cell
		if not await _walk_to(maze.cell_to_world(front_cell)):
			return
	if not campaign.can_exit():
		_fail("exit did not unlock")
		return
	# The exit Area3D may win before reaching its cell center; route movement
	# handles that separately by stopping on the actual body_entered signal.
	if not await _follow(maze.exit_cell, "exit"):
		return
	for tick: int in 10:
		await clock.step
		if finished:
			return
	_fail("reached exit cell but real exit Area3D did not win")

func _on_state_changed(state: int) -> void:
	if state != GameManager.GState.WON or finished:
		return
	if route_label != "exit" or not campaign.can_exit() or not _body_intact() \
		or player.global_position.distance_to(maze.exit_world_pos) > 2.5:
		_fail("unexpected win outside unlocked exit traversal")
		return
	finished = true
	print("TRAVERSAL PASS seed=%d stations=3 exit=WON distance=%.2fm cells=%d physics_ticks=%d simulated=%.2fs wall=%.2fs position=%s; threats=%s, scripted route NOT whole-game acceptance" % [
		game.current_seed, distance_walked, reached_cells, movement_ticks, sim_seconds,
		(Time.get_ticks_msec() - boot_ms) / 1000.0, player.global_position, "live" if live_threats else "frozen"])
	quit(0)
