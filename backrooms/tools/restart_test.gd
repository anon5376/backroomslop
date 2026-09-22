extends SceneTree

var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func wait_for_run(previous: Node = null) -> Node:
	var deadline: int = Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if current_scene != null and current_scene != previous:
			var game: GameManager = current_scene.get_node_or_null("Game") as GameManager
			if game != null and game.state == GameManager.GState.PLAYING:
				game.entity.active = false
				game.scare.active = false
				return current_scene
	check(false, "run started before timeout")
	return null

func _run() -> void:
	GameManager.pending_seed = 424242
	check(change_scene_to_file("res://scenes/main.tscn") == OK, "main scene loads")
	var scene: Node = await wait_for_run()
	if scene == null:
		quit(1)
		return
	check(scene.game.current_seed == 424242, "pending restart seed overrides launch seed")
	check(GameManager.pending_seed == -1, "pending seed consumed once")
	check(scene.player.active, "restarted player is active")
	var old_id: int = scene.get_instance_id()
	scene.game.restart_same_seed()
	scene = await wait_for_run()
	if scene == null:
		quit(1)
		return
	check(scene.get_instance_id() != old_id, "same-seed restart reloads scene")
	check(scene.game.current_seed == 424242, "same-seed restart enters run with identical seed")
	check(not paused, "restart leaves tree unpaused")
	old_id = scene.get_instance_id()
	scene.game.restart_new_seed()
	var requested_seed: int = GameManager.pending_seed
	scene = await wait_for_run()
	if scene == null:
		quit(1)
		return
	check(scene.get_instance_id() != old_id, "new-seed restart reloads scene")
	check(scene.game.current_seed == requested_seed, "new-seed restart uses requested seed")
	check(GameManager.pending_seed == -1, "new seed consumed once")
	if not "--seed" in OS.get_cmdline_user_args():
		scene.game.quit_to_menu()
		await process_frame
		await process_frame
		check(current_scene.game.state == GameManager.GState.MENU, "quit returns to menu without autoplay")
		check(not current_scene.player.active, "menu player inactive")
	print("RESTART TEST: %s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	if current_scene != null:
		current_scene.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
