extends SceneTree
var failures: int = 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1
func _run() -> void:
	var player := preload("res://scenes/player.tscn").instantiate() as Player
	var entity := preload("res://scenes/entity.tscn").instantiate() as Stalker
	root.add_child(player)
	root.add_child(entity)
	player.set_physics_process(false)
	entity.set_physics_process(false)
	entity.player = player
	entity.active = true
	entity.maze = MazeGenerator.new()
	entity.maze.generate_with_validation(1234)
	entity.astar = GridAStar.new(MazeGenerator.GRID_W, MazeGenerator.GRID_H, entity.maze.get_blocked())
	entity.position = Vector3(0, 0, 4)
	player.position = Vector3(0, 0, -4)
	await physics_frame
	check(entity._can_see(player), "unobstructed target visible")
	entity.state = Stalker.State.STALK
	entity._tick_stalk(0.1)
	check(entity.state == Stalker.State.HUNT, "visible nearby target starts pursuit")
	entity._tick_hunt(0.1)
	var last_seen: Vector3 = entity._last_known
	check(last_seen == player.position, "visible pursuit refreshes last-known position")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 3, 0.3)
	shape.shape = box
	shape.position.y = 1.5
	wall.add_child(shape)
	root.add_child(wall)
	await physics_frame
	player.position.x = 2.0
	await physics_frame
	check(not entity._can_see(player), "solid wall blocks sight")
	entity._tick_hunt(0.5)
	check(entity._last_known == last_seen, "unseen movement does not update pursuit destination")
	entity.hear_noise(player.position, 18.0)
	check(entity._last_known == player.position, "audible noise updates last-known position")
	for tick: int in 16:
		entity._tick_hunt(0.5)
	check(entity.state == Stalker.State.STALK, "unseen silent target lost after search timeout")
	entity._tick_stalk(0.1)
	check(entity.state == Stalker.State.STALK, "proximity alone cannot reacquire through wall")
	wall.queue_free()
	await physics_frame
	await physics_frame
	entity._tick_stalk(0.1)
	check(entity.state == Stalker.State.HUNT, "target reacquired when sight restored")
	player.queue_free()
	entity.queue_free()
	await process_frame
	print("PURSUIT TEST: %s" % ("ALL PASS" if failures == 0 else "FAILED"))
	quit(failures)
