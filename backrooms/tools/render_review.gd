extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	auto_accept_quit = false
	print("RENDER START")
	GameManager.pending_seed = 1234
	change_scene_to_file("res://scenes/main.tscn")
	var deadline := Time.get_ticks_msec() + 90000
	while current_scene == null or current_scene.game.state != GameManager.GState.PLAYING:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			quit(1)
			return
	var main: Node = current_scene
	main.entity.active = false
	main.scare.active = false
	main.player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var camera := Camera3D.new()
	main.add_child(camera)
	camera.current = true
	camera.fov = 72
	var folder: String = ProjectSettings.globalize_path("res://../build/review")
	DirAccess.make_dir_recursive_absolute(folder)
	var views: Array = [
		["lobby", Vector3(0,1.65,5), Vector3(0,1.5,-5), 0],
		["west", Vector3(-219,1.65,-18), Vector3(-219,1.35,-30), 0],
		["service", Vector3(3,1.65,-228), Vector3(13,1.4,-228), 0],
		["server", Vector3(144,1.65,0), Vector3(162,1.5,0), 0],
		["dark", Vector3(0,1.65,141), Vector3(0,1.5,155), 0],
		["breakroom", Vector3(-189,1.65,-9.5), Vector3(-189,0.7,-15), 0],
		["stairs", Vector3(165,1.65,0), Vector3(171,1.2,0), 0],
		["maze0", Vector3(-145.5,1.65,-145.5), Vector3(-145.5,1.35,-169.5), 0],
		["level1_hall", Vector3(0,1.65,4), Vector3(0,1.3,-14), 1],
		["level1_north", Vector3(-9,1.65,-223), Vector3(2,1.2,-225), 1],
		["maze1", Vector3(60,1.65,120), Vector3(90,1.4,120), 1],
		["level2_spokes", Vector3(0,1.65,5), Vector3(0,1.5,-20), 2],
		["level2_exit", Vector3(145,1.65,4), Vector3(153,1.4,0), 2],
		["maze2", Vector3(-120,1.65,60), Vector3(-90,1.4,60), 2]
	]
	for view: Array in views:
		while main.game.level_index < int(view[3]):
			await main.game.descend()
			for frame: int in 60:
				await process_frame
			main.player.active = false
		var snap: Vector2i = main.game.maze._nearest_floor(main.game.maze.world_to_cell(view[1]))
		var campos: Vector3 = main.game.maze.cell_to_world(snap) + Vector3(0, 1.65, 0)
		main.player.global_position = campos - Vector3(0, 1.65, 0)
		camera.global_position = campos
		camera.look_at(view[2])
		for frame: int in 120:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var error := image.save_png(folder.path_join(view[0] + ".png"))
		print("RENDER %s %s" % [view[0], error])
	print("RENDER REVIEW COMPLETE")
	quit()
