extends SceneTree
## Headless campaign exercise, not visual or human-player acceptance.
## godot --headless --fixed-fps 60 --disable-render-loop --script \
##   res://tools/survival_campaign_test.gd -- --survival-attempt 1
## Run in an isolated HOME; refuses to touch normal production save data.
## Knows the full grid, station fronts, threat position/state and LOS (oracle bot).
## No actor position/velocity/state writes, manual physics/footsteps, or meter edits.
## Native STALK/DORMANT teleports are production behavior, reported separately.
## Crouch collider blending is performed exclusively by the production controller.

const ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "interact"]
const DIRS := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
const MAX_SIM := 420.0
const MAX_WALL_MS := 180000

class NoiseRecorder extends Node:
	var steps := 0
	var sprint_steps := 0
	var crouch_steps := 0
	var audible_steps := 0
	var threat: Stalker
	func hear_noise(pos: Vector3, radius: float) -> void:
		steps += 1
		if is_equal_approx(radius, Player.NOISE_SPRINT):
			sprint_steps += 1
		if is_equal_approx(radius, Player.NOISE_CROUCH):
			crouch_steps += 1
		var audible := threat.global_position.distance_to(pos) <= radius
		if audible:
			audible_steps += 1
		if threat.state == Stalker.State.HUNT:
			print("SURVIVAL NOISE t=%.2f radius=%.1f audible=%s position=%s heard_recently=%.3f lose_timer=%.3f" % [float(get_tree().get("ticks")) / 60.0, radius, audible, pos, threat._heard_recently, threat._lose_t])

var boot_ms := Time.get_ticks_msec()
var finished := false
var attempt := 1
var player: Player
var entity: Stalker
var game: GameManager
var maze: MazeGenerator
var campaign: Node
var planner: GridAStar
var noise: NoiseRecorder
var ticks := 0
var distance := 0.0
var threat_distance := 0.0
var native_jumps := 0
var sprint_ticks := 0
var crouch_ticks := 0
var hide_ticks := 0
var concealed_ticks := 0
var hunt_ticks := 0
var hunts := 0
var escapes := 0
var sight_breaks := 0
var min_stamina := 1.0
var min_separation := INF
var interaction_tries := 0
var interactions: Array[Dictionary] = []
var mode := "objective"
var leg := "station_0"
var path: Array[Vector2i] = []
var goal := Vector2i.ZERO
var target := Vector3.ZERO
var stalled := 0.0
var best_remaining := INF
var hide_elapsed := 0.0
var hide_cooldown := 0.0
var evade_cooldown := 0.0
var phase := "route"
var exit_entries := 0
var previous_state := Stalker.State.DORMANT
var previous_visible := false
var original_player_layer := 0
var original_player_mask := 0
var original_entity_layer := 0
var original_entity_mask := 0
var player_shape: Shape3D
var entity_shape: Shape3D
var entity_shape_height := 0.0
var entity_shape_radius := 0.0
var contacts: Array[String] = []
var exit_area: Area3D
var exit_commit := false
var exit_trace_tick := -60
var exit_decisions: Array[Dictionary] = []
var sight_start := -1
var sight_noise_start := 0
var sight_audible_start := 0
var sight_intervals: Array[Dictionary] = []
var hunt_start := -1
var hunt_intervals: Array[Dictionary] = []
var hide_start := -1
var hide_steps_start := 0
var hide_audible_start := 0
var hide_intervals: Array[Dictionary] = []
var hide_diagnostic_tick := 0
var conceal_retry_tick := 0
var escape_memory := Vector3.ZERO
var exit_route_dist: PackedInt32Array = []

# Passive exit diagnostic only: never used to select inputs, goals or modes.
var diagnostic_door: Node3D
var diagnostic_trigger: CollisionShape3D
var diagnostic_closest: Dictionary = {}
var diagnostic_hunts: Array[Dictionary] = []
var diagnostic_near_ticks := 0
var diagnostic_controller_key := ""
var diagnostic_stop_key := ""

func _diagnostic_position() -> Dictionary:
	var pos := player.global_position
	var local := diagnostic_trigger.to_local(player.collision.global_position)
	var half := (diagnostic_trigger.shape as BoxShape3D).size * 0.5
	var gap := Vector2(maxf(absf(local.x) - half.x, 0.0), maxf(absf(local.z) - half.z, 0.0)).length()
	return {"tick": ticks, "physics_frame": Engine.get_physics_frames(), "seconds": ticks / 60.0,
		"player_position": str(pos), "capsule_center": str(player.collision.global_position),
		"door_root_distance_xz_m": _flat(pos, diagnostic_door.global_position),
		"door_root_distance_3d_m": pos.distance_to(diagnostic_door.global_position),
		"trigger_center_distance_3d_m": pos.distance_to(diagnostic_trigger.global_position),
		"trigger_center_distance_xz_m": _flat(pos, diagnostic_trigger.global_position),
		"capsule_to_trigger_xz_gap_m": gap - player_shape.radius,
		"trigger_overlap_reported": exit_area.overlaps_body(player),
		"stamina": player.stamina, "state": entity.state, "stage": campaign.stage,
		"can_exit": campaign.can_exit(), "mode": mode, "phase": phase, "leg": leg,
		"goal_cell": str(goal), "goal_world": str(maze.cell_to_world(goal)),
		"waypoint_world": str(target), "waypoint_distance_xz_m": _flat(pos, target),
		"path_cells_remaining": path.size(), "stalled_s": stalled,
		"entity_position": str(entity.global_position), "visible": entity._can_see(player)}

func _diagnostic_startup() -> void:
	diagnostic_door = game.world_root.get_node("ExitDoor")
	for node: Node in exit_area.get_children():
		if node is CollisionShape3D:
			diagnostic_trigger = node
	var geometry: Array[Dictionary] = []
	var solid_shapes := 0
	for node: Node in diagnostic_door.find_children("*", "Node3D", true, false):
		if node is CollisionShape3D:
			var shape_node := node as CollisionShape3D
			if shape_node.get_parent() is PhysicsBody3D:
				solid_shapes += 1
			geometry.append({"path": str(node.get_path()), "kind": "collision_shape", "parent_type": node.get_parent().get_class(),
				"world_transform": str(shape_node.global_transform), "local_transform": str(shape_node.transform),
				"size": str((shape_node.shape as BoxShape3D).size) if shape_node.shape is BoxShape3D else str(shape_node.shape), "disabled": shape_node.disabled})
		elif node is MeshInstance3D and node.mesh is BoxMesh:
			geometry.append({"path": str(node.get_path()), "kind": "visual_box_not_collider",
				"world_transform": str(node.global_transform), "size": str(node.mesh.size)})
	var route := planner.find_path(maze.spawn_cell, maze.exit_cell)
	var world_route: Array[String] = []
	for cell: Vector2i in route:
		world_route.append(str(maze.cell_to_world(cell)))
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player_shape
	query.transform = Transform3D(Basis.IDENTITY, maze.cell_to_world(maze.exit_cell) + player.collision.position)
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid(), entity.get_rid()]
	query.collide_with_areas = true
	var goal_hits: Array[String] = []
	for hit: Dictionary in player.get_world_3d().direct_space_state.intersect_shape(query, 64):
		goal_hits.append(str(hit.collider.get_path()))
	print("EXIT_DIAGNOSTIC STARTUP " + JSON.stringify({"seed": game.current_seed,
		"exit_cell": str(maze.exit_cell), "maze_exit_world": str(maze.exit_world_pos),
		"door_root_world_transform": str(diagnostic_door.global_transform), "solid_door_collider_count": solid_shapes,
		"trigger_area_world_transform": str(exit_area.global_transform), "trigger_shape_center": str(diagnostic_trigger.global_position),
		"trigger_layer": exit_area.collision_layer, "trigger_mask": exit_area.collision_mask, "trigger_monitoring": exit_area.monitoring,
		"player_layer": player.collision_layer, "player_mask": player.collision_mask,
		"capsule_radius": player_shape.radius, "capsule_height": player_shape.height, "capsule_local_transform": str(player.collision.transform),
		"planner": "GridAStar, four-directional cell centers; walls/pillars/stations blocked; no navmesh",
		"exit_goal_walkable": planner.is_walkable(maze.exit_cell), "exit_goal_world": str(maze.cell_to_world(maze.exit_cell)),
		"startup_exit_route_world": world_route, "goal_capsule_query_hits": goal_hits, "geometry": geometry,
		"required_win": "production ExitArea.body_entered(player), active game and campaign stage 3; shape overlap, not door-root distance",
		"sampling": "startup plus every post-physics tick; near if door-root XZ <=2m; hunt transitions observed before next controller decision"}))
	_diagnostic_tick()

func _diagnostic_tick() -> void:
	if diagnostic_trigger == null:
		return
	var record := _diagnostic_position()
	if diagnostic_closest.is_empty() or record.door_root_distance_xz_m < diagnostic_closest.door_root_distance_xz_m:
		diagnostic_closest = record
	if record.door_root_distance_xz_m <= 2.0:
		diagnostic_near_ticks += 1
		print("EXIT_DIAGNOSTIC NEAR_TICK " + JSON.stringify(record))
	if previous_state != entity.state and entity.state == Stalker.State.HUNT:
		record["from_state"] = previous_state
		record["transition"] = "STALK->HUNT" if previous_state == Stalker.State.STALK else "DORMANT->HUNT"
		diagnostic_hunts.append(record)
		print("EXIT_DIAGNOSTIC HUNT_START " + JSON.stringify(record))

func _diagnostic_controller(reason: String = "decision_changed") -> void:
	if diagnostic_trigger == null:
		return
	var key := "%s|%s|%s|%s|%s|%d" % [mode, phase, leg, goal, target, path.size()]
	if key != diagnostic_controller_key or reason != "decision_changed":
		diagnostic_controller_key = key
		var record := _diagnostic_position()
		record["reason"] = reason
		print("EXIT_DIAGNOSTIC PLANNER " + JSON.stringify(record))

func _hide_diagnostic() -> Dictionary:
	return {"seconds": ticks / 60.0, "hide_seconds": hide_elapsed,
		"hunt_seconds": (ticks - hunt_start) / 60.0 if hunt_start >= 0 else 0.0,
		"visible": entity._can_see(player), "separation_m": _flat(player.global_position, entity.global_position),
		"last_known": str(entity._last_known), "memory_distance_m": _flat(player.global_position, entity._last_known),
		"heard_recently_s": entity._heard_recently, "lose_timer_s": entity._lose_t,
		"player_position": str(player.global_position), "threat_position": str(entity.global_position),
		"footsteps": noise.steps - hide_steps_start, "audible_footsteps": noise.audible_steps - hide_audible_start}

func _begin_hide(reason: String) -> void:
	mode = "hide"
	hide_start = ticks
	hide_elapsed = 0.0
	hide_steps_start = noise.steps
	hide_audible_start = noise.audible_steps
	hide_diagnostic_tick = ticks + 1501
	_release()
	_crouch(true)
	print("SURVIVAL HIDE_BEGIN reason=%s %s" % [reason, JSON.stringify(_hide_diagnostic())])

func _close_hide(reason: String) -> void:
	if hide_start < 0:
		return
	var record := _hide_diagnostic()
	record.merge({"start_s": hide_start / 60.0, "end_s": ticks / 60.0,
		"duration_s": (ticks - hide_start) / 60.0, "end_reason": reason})
	hide_intervals.append(record)
	print("SURVIVAL HIDE_END " + JSON.stringify(record))
	hide_start = -1

func _conceal() -> bool:
	# End the hunt, not just the sight line: hide where the hunter can neither
	# see us now nor see us from its remembered destination, then hold still.
	var here := maze.world_to_cell(player.global_position)
	# Never crouch-walk while the hunter holds LOS: the 1.6 m/s approach loses
	# ground at 3.2 m/s net and is overrun before reaching any branch.
	if _occluded(player.global_position) and _occluded_from(entity._last_known, player.global_position) \
		and _flat(player.global_position, entity.global_position) > 9.0:
		_begin_hide("in_place_cover")
		return true
	var separation := _flat(player.global_position, entity.global_position)
	var queue: Array[Vector2i] = [here]
	var depth: Dictionary = {here: 0}
	var pursuit := entity.astar.find_path(maze.world_to_cell(entity.global_position), maze.world_to_cell(entity._last_known))
	var best := here
	var score := INF
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		var steps: int = depth[cell]
		var point := maze.cell_to_world(cell)
		if steps > 0 and not path.has(cell) and not pursuit.has(cell) and _flat(point, entity.global_position) > Player.NOISE_WALK + 1.0 and _flat(point, entity._last_known) > Player.NOISE_CROUCH + 1.0 and _occluded(point):
			var ray := PhysicsRayQueryParameters3D.create(entity._last_known + Vector3(0, 1.4, 0), point + Vector3(0, 1.4, 0), 1, [entity.get_rid(), player.get_rid()])
			if not player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				var route := planner.find_path(here, cell)
				var clearance := INF
				for waypoint: Vector2i in route:
					clearance = minf(clearance, _flat(maze.cell_to_world(waypoint), entity.global_position))
				var value := steps * 3.0 - minf(clearance, 18.0) * 0.1
				if clearance > Player.NOISE_WALK and value < score:
					score = value
					best = cell
		if steps < 3:
			for direction: Vector2i in DIRS:
				var next := cell + direction
				if planner.is_walkable(next) and not depth.has(next):
					depth[next] = steps + 1
					queue.append(next)
	if best == here:
		return false
	mode = "conceal"
	print("SURVIVAL CONCEAL_SELECT t=%.2f separation=%.2f last_known=%s cell=%s" % [ticks / 60.0, _flat(player.global_position, entity.global_position), entity._last_known, best])
	return _plan(best, "quiet_side_branch")

# Evaluate the actual remaining polyline, not just straight-line exit proximity.
# The threat oracle estimates interception via its navigable corridors, allowing
# corner cutting; it does not assume a sight break stops pursuit or hearing.
func _exit_arbitration() -> bool:
	var old_commit := exit_commit
	exit_commit = false
	if campaign.stage != 3 or not campaign.can_exit() or phase != "route" or exit_area == null:
		return false
	var route: Array[Vector2i] = path.duplicate() if leg == "exit" else planner.find_path(maze.world_to_cell(player.global_position), maze.exit_cell)
	var from := player.global_position
	var route_m := 0.0
	for cell: Vector2i in route:
		var to := maze.cell_to_world(cell)
		route_m += _flat(from, to)
		from = to
	var budget_s := maxf(0.0, player.stamina - 0.12) * 14.0 / player._stamina_drain_mul()
	var speed := Player.SPRINT_SPEED * player._move_factor()
	var travel_m := 0.0
	var eta := 0.1 # acceleration allowance
	var clearance := INF
	var margin := INF
	var blocked := false
	var entered := false
	var exit_shape: CollisionShape3D
	for child: Node in exit_area.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			exit_shape = child
			break
	if exit_shape == null:
		_finish("INVALID", "exit Area has no box collision shape")
		return false
	var box := exit_shape.shape as BoxShape3D
	from = player.global_position
	for cell: Vector2i in route:
		var to := maze.cell_to_world(cell)
		var length := _flat(from, to)
		var samples := maxi(1, ceili(length / 0.25))
		for i: int in range(1, samples + 1):
			var point := from.lerp(to, float(i) / samples)
			travel_m += length / samples
			eta += length / samples / speed
			# Use a swept production-sized capsule, lifted off the floor. No
			# collision object or actor transform is changed by this query.
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = player_shape
			query.transform = Transform3D(Basis.IDENTITY, from.lerp(to, float(i - 1) / samples) + Vector3(0, 0.93, 0))
			query.motion = (to - from) / samples
			query.collision_mask = player.collision_mask
			query.exclude = [player.get_rid(), entity.get_rid()]
			var sweep := player.get_world_3d().direct_space_state.cast_motion(query)
			if sweep[0] < 0.999 or not player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
				blocked = true
			var direct := _flat(entity.global_position, point)
			clearance = minf(clearance, direct)
			var threat_m := direct
			if _occluded(point):
				var threat_route := entity.astar.find_path(maze.world_to_cell(entity.global_position), maze.world_to_cell(point))
				if not threat_route.is_empty():
					var corridor := 0.0
					var last := entity.global_position
					var turns := 0
					for j: int in threat_route.size():
						var wp := maze.cell_to_world(threat_route[j])
						corridor += _flat(last, wp)
						last = wp
						if j > 1 and threat_route[j] - threat_route[j - 1] != threat_route[j - 1] - threat_route[j - 2]:
							turns += 1
					# Endpoint centering and 1m waypoint skipping can shorten chase.
					corridor -= _flat(entity.global_position, maze.cell_to_world(threat_route[0])) * 2.0
					corridor -= _flat(point, last) + turns * 1.0
					threat_m = maxf(direct, corridor)
			margin = minf(margin, (threat_m - Stalker.CATCH_DIST) / Stalker.HUNT_SPEED - eta)
			# Conservative entry: the center must enter the real Area box;
			# production capsule overlap may win earlier, but is not assumed.
			var local := exit_shape.to_local(point + Vector3(0, 0.9, 0))
			if absf(local.x) < box.size.x * 0.5 - 0.05 and absf(local.z) < box.size.z * 0.5 - 0.05:
				entered = true
				break
		if entered:
			break
		eta += 0.3 # analog waypoint braking/turn allowance
		from = to
	var reason := "supported_terminal_route"
	if route.is_empty() or not entered:
		reason = "no_entry_route"
	elif blocked:
		reason = "physical_route_blocked"
	elif eta > budget_s:
		reason = "insufficient_sprint_budget"
	elif clearance < Stalker.CATCH_DIST + 0.5 or margin < 0.15:
		reason = "interception_margin"
	else:
		exit_commit = true
	if ticks - exit_trace_tick >= 30 or old_commit != exit_commit:
		exit_trace_tick = ticks
		var record := {"seconds": ticks / 60.0, "commit": exit_commit, "reason": reason,
			"route_m": route_m, "entry_route_m": travel_m, "direct_entry_center_m": _flat(player.global_position, maze.exit_world_pos),
			"eta_s": eta, "sprint_budget_s": budget_s, "stamina": player.stamina,
			"route_clearance_m": clearance, "interception_margin_s": margin, "blocked": blocked,
			"visible": entity._can_see(player), "heard_recently_s": entity._heard_recently,
			"lose_timer_s": entity._lose_t, "threat_position": str(entity.global_position), "player_position": str(player.global_position)}
		exit_decisions.append(record)
		print("SURVIVAL EXIT_ARBITRATION " + JSON.stringify(record))
	if exit_commit and leg != "exit":
		_objective()
	return exit_commit

func _close_sight_break(reason: String) -> void:
	if sight_start < 0:
		return
	var record := {"start_s": sight_start / 60.0, "end_s": ticks / 60.0,
		"duration_s": (ticks - sight_start) / 60.0, "end_reason": reason,
		"footsteps": noise.steps - sight_noise_start, "audible_footsteps": noise.audible_steps - sight_audible_start,
		"heard_recently_s": entity._heard_recently, "lose_timer_s": entity._lose_t}
	sight_intervals.append(record)
	print("SURVIVAL SIGHT_BREAK " + JSON.stringify(record))
	sight_start = -1

func _initialize() -> void:
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() - boot_ms > MAX_WALL_MS:
		_finish("TIMEOUT", "180s wall watchdog")
	return false

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _release() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			Input.action_release(action)

func _event(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _look(point: Vector3) -> void:
	var diff := point - player.camera.global_position
	var yaw := atan2(-diff.x, -diff.z)
	var pitch := clampf(atan2(diff.y, Vector2(diff.x, diff.z).length()), -1.4, 1.4)
	# Headless has no captured pointer. Drive look orientation directly (as in
	# pursuit_escape_test), never position or velocity; locomotion remains input.
	player.rotation.y = yaw
	player.head.rotation.x = pitch

func _crouch(want: bool) -> void:
	if player.crouched != want and not Input.is_action_pressed("crouch"):
		Input.action_press("crouch")
	else:
		Input.action_release("crouch")

func _drive(point: Vector3, sprint: bool, crouch: bool) -> void:
	_crouch(crouch)
	var remaining := _flat(player.global_position, point)
	var aim := Vector3(point.x, player.camera.global_position.y, point.z)
	_look(aim)
	if sprint:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")
	var speed := Player.CROUCH_SPEED if crouch else (Player.SPRINT_SPEED if sprint else Player.WALK_SPEED)
	# Analog stick steering and braking; acceleration/collision stay in Player.
	var strength := clampf(remaining * 5.0 / (speed * player._move_factor()), 0.0, 1.0)
	Input.action_press("move_forward", 0.5 + 0.5 * strength)

func _plan(destination: Vector2i, label_text: String) -> bool:
	goal = destination
	leg = label_text
	var here := maze.world_to_cell(player.global_position)
	path = planner.find_path(here, goal)
	if path.is_empty():
		_finish("BLOCKED", "no route from %s to %s" % [here, goal])
		return false
	# Recenter before changing direction; never cut diagonal wall corners.
	target = maze.cell_to_world(path[0])
	best_remaining = INF
	stalled = 0.0
	print("SURVIVAL ROUTE t=%.2f mode=%s leg=%s from=%s to=%s cells=%d" % [ticks / 60.0, mode, leg, here, goal, path.size()])
	return true

func _objective() -> void:
	mode = "objective"
	phase = "route"
	var stage: int = campaign.stage
	if stage < 3:
		_plan(campaign.CELLS[stage] + Vector2i.DOWN, "station_%d" % stage)
	else:
		_plan(maze.exit_cell, "exit")

func _occluded(point: Vector3) -> bool:
	return _occluded_from(entity.global_position, point)

func _occluded_from(from: Vector3, point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from + Vector3(0, 1.4, 0),
		point + Vector3(0, 1.4, 0), 1, [entity.get_rid(), player.get_rid()])
	return not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _evade() -> bool:
	var here := maze.world_to_cell(player.global_position)
	if not planner.is_walkable(here):
		return false # station approach: back out using the current physical route
	var queue: Array[Vector2i] = [here]
	var depth: Dictionary = {here: 0}
	var best := here
	var score := -INF
	var current_distance := _flat(player.global_position, entity.global_position)
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		var steps: int = depth[cell]
		if steps >= 3:
			var point := maze.cell_to_world(cell)
			var separation := _flat(point, entity.global_position)
			var route := planner.find_path(here, cell)
			var clearance := current_distance
			var corners := 0
			for i: int in range(1, route.size()):
				clearance = minf(clearance, _flat(maze.cell_to_world(route[i]), entity.global_position))
				if i > 1 and route[i] - route[i - 1] != route[i - 1] - route[i - 2]:
					corners += 1
			# Sprint away from the captured hunt memory with few braking corners;
			# concealment is a separate short side-branch selection above 12m.
			var value := separation + _flat(point, escape_memory) * 0.5 - steps * 0.65 - corners * 2.0
			if campaign.stage == 3:
				var exit_steps := exit_route_dist[cell.y * MazeGenerator.GRID_W + cell.x]
				var here_steps := exit_route_dist[here.y * MazeGenerator.GRID_W + here.x]
				if exit_steps < here_steps:
					value = -INF
				value += minf(float(exit_steps - here_steps), 6.0) * 0.75
			value -= maxf(0.0, current_distance - clearance - 0.25) * 20.0
			if value > score:
				score = value
				best = cell
		if steps < 14:
			for direction: Vector2i in DIRS:
				var next := cell + direction
				if planner.is_walkable(next) and not depth.has(next):
					depth[next] = steps + 1
					queue.append(next)
	if best == here:
		return false
	mode = "evade"
	phase = "route"
	evade_cooldown = 4.0
	return _plan(best, "escape_corner")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i] == "--survival-attempt" and i + 1 < args.size():
			attempt = clampi(int(args[i + 1]), 1, 3)
	for forbidden: String in ["--teleport-exit", "--force-hunt", "--mp-host-test", "--mp-join-test", "--seed"]:
		if forbidden in args:
			_finish("INVALID", "forbidden boot argument " + forbidden)
			return
	print("SURVIVAL USER_DATA " + OS.get_user_data_dir())
	if not "survival-" in OS.get_user_data_dir():
		_finish("INVALID", "run with isolated survival HOME to preserve production saves")
		return
	seed(1234)
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 1
	GameManager.pending_seed = 1234
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.game.state != GameManager.GState.PLAYING:
		await process_frame
		if finished:
			return
	game = current_scene.game
	player = current_scene.player
	entity = current_scene.entity
	maze = game.maze
	campaign = current_scene.get_node("Campaign")
	if game.current_seed != 1234 or campaign.stage != 0 or not campaign.started or maze.world_to_cell(player.global_position) != maze.spawn_cell:
		_finish("INVALID", "not fresh seed 1234 production spawn")
		return
	original_player_layer = player.collision_layer
	original_player_mask = player.collision_mask
	original_entity_layer = entity.collision_layer
	original_entity_mask = entity.collision_mask
	player_shape = player.collision.shape
	entity_shape = entity.get_node("CollisionShape3D").shape
	entity_shape_height = entity_shape.height
	entity_shape_radius = entity_shape.radius
	var blocked := maze.get_blocked()
	for cell: Vector2i in campaign.CELLS:
		blocked[cell.y * MazeGenerator.GRID_W + cell.x] = 1
	planner = GridAStar.new(MazeGenerator.GRID_W, MazeGenerator.GRID_H, blocked)
	# Lure metric: BFS distance to the exit from every cell. Evading away from
	# the door drags the hunter's hunt memory away from the exit corridor.
	exit_route_dist = campaign.route_distances(maze, maze.exit_cell)
	noise = NoiseRecorder.new()
	noise.threat = entity
	root.add_child(noise)
	noise.add_to_group("entity") # passive observer of real Player._footstep group calls
	for node: Node in game.world_root.find_children("*", "Area3D", true, false):
		var area := node as Area3D
		if area.global_position.distance_to(maze.exit_world_pos) < 1.0:
			exit_area = area
			area.body_entered.connect(func(body: Node3D) -> void:
				if body == player:
					exit_entries += 1
					print("SURVIVAL EXIT_BODY_ENTERED stage=%d position=%s" % [campaign.stage, player.global_position]))
	print("SURVIVAL START attempt=%d seed=1234 player=%s entity=%s production_physics=60Hz time_scale=%s map_and_threat_oracle=true" % [attempt, player.global_position, entity.global_position, Engine.time_scale])
	_objective()
	_diagnostic_startup()
	while not finished:
		_decide()
		_diagnostic_controller()
		if finished:
			return
		var before := player.global_position
		var e_before := entity.global_position
		var frame := Engine.get_physics_frames()
		await physics_frame
		await process_frame
		_sample(before, e_before, frame)

func _decide() -> void:
	_release_pulses()
	var separation := _flat(player.global_position, entity.global_position)
	var visible := entity._can_see(player)
	var searching := entity.state == Stalker.State.HUNT
	if campaign._read_open:
		_release()
		_event("journal", true)
		_event("journal", false)
		print("SURVIVAL READER_CLOSED t=%.2f active=%s" % [ticks / 60.0, player.active])
		return
	# An established hide is not interrupted by route arbitration or a timer.
	if mode == "hide":
		hide_elapsed = (ticks - hide_start) / 60.0
		_release()
		_crouch(true)
		if searching and (visible or separation < 2.0):
			# The hide spot is compromised; a stationary crouch is a guaranteed
			# catch once the hunter closes, so flee while distance remains.
			_close_hide("spotted")
			escape_memory = entity._last_known
			if not _evade():
				_objective()
			return
		if not searching:
			# Hold the hide until the exit route is actually committable: the
			# stalking threat flickers around its last memory, and standing up
			# into a door-camping position re-triggers the hunt.
			if campaign.stage == 3 and campaign.can_exit() and hide_elapsed < 90.0 \
				and not _exit_arbitration():
				if ticks >= hide_diagnostic_tick:
					print("SURVIVAL HIDE_HOLD " + JSON.stringify(_hide_diagnostic()))
					hide_diagnostic_tick = ticks + 300
				return
			_close_hide("exit_commit" if campaign.stage == 3 and campaign.can_exit() and _exit_arbitration() else "hunt_lost")
			_objective()
		elif ticks >= hide_diagnostic_tick:
			print("SURVIVAL HIDE_PERSIST " + JSON.stringify(_hide_diagnostic()))
			hide_diagnostic_tick = ticks + 300
		return
	# Preserve terminal arbitration before selecting a new escape route.
	var terminal := _exit_arbitration() if mode != "conceal" else false
	if campaign.stage == 3 and phase == "route" and not terminal and not searching and not visible:
		_begin_hide("exit_route_rejected_in_cover")
		return
	if not terminal and searching and phase == "route":
		if mode != "evade" and mode != "conceal":
			escape_memory = entity._last_known
			_evade()
		if mode == "evade" and not visible and separation > 9.0 and ticks >= conceal_retry_tick:
			conceal_retry_tick = ticks + 15
			if not _conceal():
				print("SURVIVAL CONCEAL_UNAVAILABLE t=%.2f separation=%.2f stamina=%.3f" % [ticks / 60.0, separation, player.stamina])
			if mode == "hide":
				return
	if searching and mode == "conceal" and (visible or separation < 5.0):
		escape_memory = entity._last_known
		_evade()
	if searching and mode == "evade" and player.stamina <= 0.12:
		_begin_hide("sprint_budget_exhausted")
		return
	if (mode == "evade" or mode == "conceal") and not searching:
		_objective()
	var remaining := _flat(player.global_position, target)
	var straight := path.size() > 2 and path[1] - path[0] == path[2] - path[1]
	if remaining < (0.65 if mode == "evade" and straight else 0.13):
		stalled = 0.0
		best_remaining = INF
		if not path.is_empty():
			path.pop_front()
		if not path.is_empty():
			target = maze.cell_to_world(path[0])
		elif mode == "conceal":
			_begin_hide("side_branch_arrival")
			return
		elif mode == "evade":
			if not _evade():
				_begin_hide("no_escape_route")
				return
		elif phase == "route" and campaign.stage < 3:
			phase = "approach"
			target = maze.cell_to_world(campaign.CELLS[campaign.stage])
		elif phase == "approach":
			_release()
			var id: int = campaign.stage
			var station: StaticBody3D = campaign.stations[id]
			_look(station.global_position + Vector3(0, 1.35, 0.2))
			var focused: Object = campaign.focused_interactable()
			interaction_tries += 1
			if focused != station:
				_finish("BLOCKED", "real 3.2m interaction ray missed station %d: %s" % [id, focused])
				return
			print("SURVIVAL INTERACT t=%.2f id=%d ray=%s separation=%.2f" % [ticks / 60.0, id, station.get_path(), separation])
			Input.action_press("interact")
			phase = "verify_interact"
			return
		elif phase == "verify_interact":
			if not campaign.stage == interactions.size() + 1:
				_finish("INVALID", "interaction failed to advance campaign")
				return
			interactions.append({"stage": campaign.stage, "seconds": ticks / 60.0, "distance_m": distance, "position": str(player.global_position)})
			print("SURVIVAL STATION_PASS " + JSON.stringify(interactions.back()))
			phase = "backout"
			target = maze.cell_to_world(campaign.CELLS[campaign.stage - 1] + Vector2i.DOWN)
		elif phase == "backout":
			_objective()
		else:
			var stop_key := "%s|%s|%s" % [mode, phase, leg]
			if diagnostic_stop_key != stop_key:
				diagnostic_stop_key = stop_key
				_diagnostic_controller("route_exhausted_within_waypoint_tolerance; release_inputs_without_exit_extension")
			_release()
			return
	remaining = _flat(player.global_position, target)
	if remaining < best_remaining - 0.02:
		best_remaining = remaining
		stalled = 0.0
	else:
		stalled += 1.0 / 60.0
	if stalled > 4.0:
		_finish("BLOCKED", "no 2cm waypoint progress for 4s; target=%s remaining=%.3f" % [target, remaining])
		return
	var sprint := terminal or (separation < 26.0 and (searching or visible) and player.stamina > 0.12)
	# Trial number is metadata only; no attempt-specific behavioral branches.
	# Do not slow a budgeted terminal commitment with generic quiet movement.
	var quiet := mode == "conceal"
	if searching and not sprint and not quiet:
		_begin_hide("no_sprint_budget")
		return
	_drive(target, sprint and not quiet, quiet)
	if mode == "evade" and path.size() > 2 and path[1] - path[0] == path[2] - path[1]:
		Input.action_press("move_forward", 1.0)

func _release_pulses() -> void:
	Input.action_release("interact")
	hide_cooldown = maxf(0.0, hide_cooldown - 1.0 / 60.0)
	evade_cooldown = maxf(0.0, evade_cooldown - 1.0 / 60.0)

func _sample(before: Vector3, e_before: Vector3, frame: int) -> void:
	ticks += 1
	_diagnostic_tick()
	var pd := _flat(before, player.global_position)
	var ed := _flat(e_before, entity.global_position)
	distance += pd
	if ed > Stalker.HUNT_SPEED / 60.0 + 0.03:
		native_jumps += 1
		print("SURVIVAL NATIVE_THREAT_TELEPORT t=%.2f from=%s to=%s state=%d->%d distance=%.2f" % [ticks / 60.0, e_before, entity.global_position, previous_state, entity.state, ed])
	else:
		threat_distance += ed
	var separation := player.global_position.distance_to(entity.global_position)
	min_separation = minf(min_separation, separation)
	min_stamina = minf(min_stamina, player.stamina)
	if player.sprinting:
		sprint_ticks += 1
	if player.crouched:
		crouch_ticks += 1
	var visible := entity._can_see(player)
	if mode == "hide":
		hide_ticks += 1
		if not visible and pd < 0.01:
			concealed_ticks += 1
	if entity.state == Stalker.State.HUNT:
		hunt_ticks += 1
		print("SURVIVAL HUNT_FRAME t=%.4f mode=%s visible=%s separation=%.3f hearing=%.4f lose=%.4f stamina=%.4f steps=%d" % [ticks / 60.0, mode, visible, separation, entity._heard_recently, entity._lose_t, player.stamina, noise.steps])
		if previous_visible and not visible:
			sight_breaks += 1
		if not visible and sight_start < 0:
			sight_start = ticks
			sight_noise_start = noise.steps
			sight_audible_start = noise.audible_steps
	if sight_start >= 0 and (visible or entity.state != Stalker.State.HUNT):
		_close_sight_break("visible" if visible else "hunt_lost")
	if previous_state != entity.state:
		if entity.state == Stalker.State.HUNT:
			hunts += 1
			hunt_start = ticks
		if previous_state == Stalker.State.HUNT:
			escapes += 1
			var record := {"start_s": hunt_start / 60.0, "end_s": ticks / 60.0, "duration_s": (ticks - hunt_start) / 60.0, "end_state": entity.state, "lose_timer_s": entity._lose_t}
			hunt_intervals.append(record)
			print("SURVIVAL HUNT_LOSS " + JSON.stringify(record))
			hunt_start = -1
		print("SURVIVAL THREAT t=%.2f state=%d->%d separation=%.2f stamina=%.3f mode=%s" % [ticks / 60.0, previous_state, entity.state, separation, player.stamina, mode])
	previous_state = entity.state
	previous_visible = visible
	contacts.clear()
	for i: int in player.get_slide_collision_count():
		var hit := player.get_slide_collision(i)
		var collider := hit.get_collider()
		contacts.append("%s normal=%s" % [collider.get_path() if collider is Node else str(collider), hit.get_normal()])
	if Engine.get_physics_frames() != frame + 1 or not is_equal_approx(Engine.time_scale, 1.0) or pd > Player.SPRINT_SPEED / 60.0 + 0.03:
		_finish("INVALID", "physics clock or continuous player movement invariant failed")
		return
	if player.collision_layer != original_player_layer or player.collision_mask != original_player_mask or player.collision.shape != player_shape or player.collision.disabled or not is_equal_approx(player_shape.radius, 0.35) or player_shape.height < 1.14 or player_shape.height > 1.81 or entity.collision_layer != original_entity_layer or entity.collision_mask != original_entity_mask or entity.get_node("CollisionShape3D").shape != entity_shape or not is_equal_approx(entity_shape.height, entity_shape_height) or not is_equal_approx(entity_shape.radius, entity_shape_radius):
		_finish("INVALID", "production collider invariant failed")
		return
	if game.state == GameManager.GState.WON:
		if campaign.can_exit() and interactions.size() == 3 and exit_entries > 0 and separation >= 0.0 and player.global_position.distance_to(maze.exit_world_pos) < 2.5:
			_finish("WON", "three real station rays and production exit body_entered")
		else:
			_finish("INVALID", "WON without complete station/exit evidence")
		return
	if game.state == GameManager.GState.DEAD:
		_finish("DEAD", game.ui._end_sub.text)
		return
	if game.state != GameManager.GState.PLAYING or paused or not entity.active or not entity.is_physics_processing() or not player.is_physics_processing() or not current_scene.scare.active or not current_scene.lights.active:
		_finish("INVALID", "production simulation unexpectedly disabled")
		return
	if ticks % 600 == 0:
		print("SURVIVAL TRACE t=%.2f stage=%d mode=%s cell=%s separation=%.2f stamina=%.3f thirst=%.3f hunger=%.3f footsteps=%d" % [ticks / 60.0, campaign.stage, mode, maze.world_to_cell(player.global_position), separation, player.stamina, game.thirst, game.hunger, noise.steps])
	if ticks / 60.0 >= MAX_SIM:
		_finish("TIMEOUT", "420s simulated campaign budget")

func _finish(outcome: String, reason: String) -> void:
	if finished:
		return
	finished = true
	_release()
	_close_sight_break("terminal_" + outcome)
	if is_instance_valid(player):
		_close_hide("terminal_" + outcome)
	var report := {"attempt": attempt, "seed": 1234, "outcome": outcome, "reason": reason,
		"sim_seconds": ticks / 60.0, "wall_seconds": (Time.get_ticks_msec() - boot_ms) / 1000.0,
		"player_distance_m": distance, "entity_physical_distance_m": threat_distance,
		"native_entity_teleports": native_jumps, "sprint_seconds": sprint_ticks / 60.0,
		"crouch_seconds": crouch_ticks / 60.0, "hide_seconds": hide_ticks / 60.0,
		"stationary_concealed_seconds": concealed_ticks / 60.0,
		"hunt_seconds": hunt_ticks / 60.0, "hunts": hunts, "hunt_losses": escapes,
		"sight_breaks": sight_breaks, "sight_break_intervals": sight_intervals,
		"exit_arbitration": exit_decisions, "controller": "sprint_side_branch_hide", "min_stamina": min_stamina,
		"hunt_loss_intervals": hunt_intervals, "hide_intervals": hide_intervals,
		"min_separation_m": min_separation, "interaction_tries": interaction_tries,
		"interactions": interactions, "exit_body_entries": exit_entries, "mode": mode, "leg": leg,
		"contacts": contacts, "limitation": "headless oracle map/threat bot; native threat teleports retained; no visual acceptance"}
	if is_instance_valid(player):
		report.merge({"position": str(player.global_position), "entity_position": str(entity.global_position),
			"stage": campaign.stage, "game_state": game.state, "stamina": player.stamina,
			"thirst": game.thirst, "hunger": game.hunger, "footsteps": noise.steps,
			"sprint_footsteps": noise.sprint_steps, "crouch_footsteps": noise.crouch_steps,
			"audible_footsteps": noise.audible_steps, "final_visible": entity._can_see(player),
			"final_separation_m": player.global_position.distance_to(entity.global_position)})
	if diagnostic_trigger != null:
		_diagnostic_controller("terminal_" + outcome + ": " + reason)
		var min_hunt := INF
		for record: Dictionary in diagnostic_hunts:
			min_hunt = minf(min_hunt, record.door_root_distance_xz_m)
		report["exit_diagnostic"] = {"closest_entire_run": diagnostic_closest, "hunt_starts": diagnostic_hunts,
			"minimum_hunt_start_door_root_xz_m": min_hunt if not diagnostic_hunts.is_empty() else null,
			"near_exit_ticks": diagnostic_near_ticks, "terminal_position": _diagnostic_position()}
	print("SURVIVAL RESULT " + JSON.stringify(report))
	print("SURVIVAL CAMPAIGN %s attempt=%d" % ["PASS" if outcome == "WON" else "FAIL", attempt])
	_shutdown.call_deferred(0 if outcome == "WON" else 1)

func _shutdown(code: int) -> void:
	# Release controller reference cycles only after the terminal result is logged.
	if is_instance_valid(player):
		player.game = null
		player.audio = null
		entity.player = null
		entity._game = null
		entity.maze = null
		entity.astar = null
		game.player = null
		game.entity = null
		game.maze = null
		current_scene.queue_free()
		noise.queue_free()
		await process_frame
	planner = null
	maze = null
	player_shape = null
	entity_shape = null
	await process_frame
	quit(code)
