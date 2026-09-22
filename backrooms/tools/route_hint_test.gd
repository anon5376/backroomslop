extends SceneTree
const Campaign = preload("res://scripts/campaign.gd")
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _run() -> void:
	for seed_value: int in [0, 42, 999, 1234, 424242]:
		for level: int in 3:
			_check_level(seed_value, level)
		var maze := MazeGenerator.new()
		maze.generate_with_validation(seed_value)
		var hud := Campaign.new()
		var game := GameManager.new()
		var player := preload("res://scenes/player.tscn").instantiate() as Player
		root.add_child(player)
		game.maze = maze
		hud.game = game
		hud.player = player
		hud._route = Label.new()
		for pillar: Vector2i in maze.pillar_cells:
			for offset: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
				player.position = maze.cell_to_world(pillar) + offset
				hud._update_route()
				check(hud._route.text.begins_with("ROUTE UNAVAILABLE"), "pillar-edge HUD never reports false arrival")
		player.position = Vector3(10000, 0, 10000)
		hud._update_route()
		check(hud._route.text.begins_with("ROUTE UNAVAILABLE"), "outside-map HUD invalidates stale guidance")
		player.position = maze.cell_to_world(maze.spawn_cell)
		hud._update_route()
		check(not "UNAVAILABLE" in hud._route.text and not "AT SIGNAL" in hud._route.text, "guidance recovers in clear corridor")
		player.position = maze.cell_to_world(Campaign.CELLS[0])
		hud._update_route()
		check("AT SIGNAL" in hud._route.text, "arrival only at objective cell")
		hud._route.free()
		hud.free()
		game.free()
		player.free()
		print("ROUTE HINT seed=%d checked" % seed_value)
	print("ROUTE HINT TEST: %s" % ["ALL PASS" if failures == 0 else "%d FAILURES" % failures])
	quit(0 if failures == 0 else 1)


func _check_level(seed_value: int, level: int) -> void:
	var maze := MazeGenerator.new()
	maze.level_index = level
	maze.generate_with_validation(seed_value)
	var blocked := maze.get_blocked()
	var planner := GridAStar.new(MazeGenerator.GRID_W, MazeGenerator.GRID_H, blocked)
	var goals: Array[Vector2i] = []
	for id: int in 4:
		if Campaign.STATION_LEVEL[id] == level:
			goals.append(Campaign.CELLS[id])
	goals.append(maze.exit_cell)
	for goal: Vector2i in goals:
		var distances := Campaign.route_distances(maze, goal)
		for pillar: Vector2i in maze.pillar_cells:
			check(distances[pillar.y * MazeGenerator.GRID_W + pillar.x] == -1, "L%d pillar excluded" % level)
		var path := planner.find_path(maze.spawn_cell, goal)
		check(not path.is_empty(), "L%d objective reachable" % level)
		# A-star routes around pillars (which BFS ignores), so its path can
		# only tie or exceed the BFS distance: BFS is the lower bound.
		check(distances[maze.spawn_cell.y * MazeGenerator.GRID_W + maze.spawn_cell.x] <= path.size() - 1, "L%d hint distance bounds independent A-star" % level)
		for y: int in MazeGenerator.GRID_H:
			for x: int in MazeGenerator.GRID_W:
				var index := y * MazeGenerator.GRID_W + x
				if blocked[index] != 0:
					check(distances[index] == -1, "L%d solid cell excluded" % level)
				if distances[index] <= 0:
					continue
				var descending := false
				for step: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
					var next := Vector2i(x, y) + step
					if next.x >= 0 and next.y >= 0 and next.x < MazeGenerator.GRID_W and next.y < MazeGenerator.GRID_H:
						var ni := next.y * MazeGenerator.GRID_W + next.x
						if distances[ni] == distances[index] - 1 and blocked[ni] == 0:
							descending = true
				check(descending, "L%d every hint has an unobstructed descending step" % level)
