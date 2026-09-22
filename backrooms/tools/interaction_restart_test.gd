extends SceneTree

var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures += 1

func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await create_timer(0.06, true).timeout
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func wait_for_run() -> bool:
	var deadline: int = Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if current_scene != null and current_scene.game.state == GameManager.GState.PLAYING:
			await physics_frame
			return true
	return false

func _run() -> void:
	GameManager.pending_seed = 1234
	change_scene_to_file("res://scenes/main.tscn")
	for cycle: int in 3:
		if not await wait_for_run():
			check(false, "run startup before timeout")
			quit(1)
			return
		var scene: Node = current_scene
		var campaign: Node = scene.get_node("Campaign")
		scene.entity.active = false
		scene.scare.active = false
		check(campaign.stage == 0, "cycle %d starts with reset campaign" % cycle)
		scene.player.global_position = scene.game.maze.cell_to_world(campaign.CELLS[0]) + Vector3(0, 0.1, 1.0)
		scene.player.velocity = Vector3.ZERO
		await physics_frame
		scene.player.camera.look_at(campaign.stations[0].global_position + Vector3(0, 1.35, 0.2))
		await process_frame
		check(campaign.focused_interactable() == campaign.stations[0], "cycle %d ray sees first station" % cycle)
		await press("interact")
		check(campaign.stage == 1, "cycle %d E advances objective" % cycle)
		check(campaign._read_open, "cycle %d transcript opens" % cycle)
		await press("journal")
		check(not campaign._read_open and scene.player.active, "cycle %d J closes reader and restores movement" % cycle)
		await press("pause")
		check(paused and scene.game.state == GameManager.GState.PAUSED, "cycle %d pause freezes solo" % cycle)
		await press("pause")
		check(not paused and scene.game.state == GameManager.GState.PLAYING, "cycle %d keyboard resumes solo" % cycle)
		if cycle < 2:
			scene.game.restart_same_seed()
	print("INTERACTION RESTART TEST: %s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(0 if failures == 0 else 1)
