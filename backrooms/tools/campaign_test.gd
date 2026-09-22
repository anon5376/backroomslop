extends SceneTree
const Campaign = preload("res://scripts/campaign.gd")
var failures: int = 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS: " if ok else "FAIL: ", label)
	if not ok:
		failures += 1
func _run() -> void:
	GameManager.pending_seed = 424242
	change_scene_to_file("res://scenes/main.tscn")
	var deadline: int = Time.get_ticks_msec() + 60000
	while current_scene == null or current_scene.get_node_or_null("Campaign") == null or not current_scene.get_node("Campaign").started:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			quit(1)
			return
	var scene: Node = current_scene
	var game: GameManager = scene.game
	var campaign: Node = scene.get_node("Campaign")
	game.entity.active = false
	game.scare.active = false
	await physics_frame
	check(not campaign.can_exit(), "exit initially locked")
	check(Campaign.next_stage(0, 0) == 1, "matching objective advances")
	check(Campaign.next_stage(0, 2) == 0, "skip refused")
	check(Campaign.next_stage(1, 0) == 1, "duplicate refused")
	check(Campaign.next_stage(3, 3) == 3, "completion capped")
	check(not campaign._server_activate(1, 2), "server refuses wrong order")
	check(not campaign._server_activate(1, 0), "server refuses distant activation")
	var fired: Array[int] = []
	campaign.objectives_changed.connect(func(value: int) -> void: fired.append(value))
	for id: int in [3, 0, 1, 2]:
		while game.level_index < Campaign.STATION_LEVEL[id]:
			await game.descend()
		check(game.level_index == Campaign.STATION_LEVEL[id], "station %d on its level" % id)
		var cell: Vector2i = Campaign.CELLS[id]
		check(game.maze.grid[cell.y * MazeGenerator.GRID_W + cell.x] == 0 and game.maze.dist_map[cell.y * MazeGenerator.GRID_W + cell.x] >= 0, "authored landmark %d reachable" % id)
		var station: StaticBody3D = campaign.stations[id]
		game.player.global_position = station.global_position + Vector3(0, 0.1, 1.7)
		game.player.rotation = Vector3.ZERO
		game.player.head.rotation = Vector3.ZERO
		await physics_frame
		await process_frame
		check(campaign.focused_interactable() == station, "player convention ray reaches station %d" % id)
		game.player._try_interact()
		if id < 3:
			check(campaign.stage == id + 1, "actual E interaction advances stage %d" % id)
		check(campaign.journal.has(id), "record %d retained locally" % id)
		check(campaign._read_open, "readable overlay opened")
		campaign._close_reader()
	check(campaign.can_exit(), "exit unlocked after ordered chain")
	check(fired == [1, 2, 3], "one ordered signal per objective")
	game.win()
	check(game.state == GameManager.GState.WON, "completed campaign can win")
	print("CAMPAIGN TEST: ", "ALL PASS" if failures == 0 else "%d FAILURES" % failures)
	current_scene.queue_free()
	await process_frame
	quit(failures)
