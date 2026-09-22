extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var player := preload("res://scenes/player.tscn").instantiate() as CharacterBody3D
	root.add_child(player)
	player.set_physics_process(false)
	var start: Vector3 = player.position
	for frame: int in 60:
		await physics_frame
		player.velocity = Vector3(0, 0, -3.2)
		player.move_and_slide()
		for index: int in player.get_slide_collision_count():
			var collision := player.get_slide_collision(index)
			print("CONTROLLER CONTACT position=%s normal=%s" % [collision.get_position(), collision.get_normal()])
	var delta: Vector3 = player.position - start
	print("CONTROLLER DELTA %s distance=%.4f" % [delta, delta.length()])
	var passed: bool = delta.length() > 0.1
	print("CONTROLLER PROBE: %s" % ("PASS" if passed else "BLOCKED: no measurable displacement"))
	player.queue_free()
	await process_frame
	quit(0 if passed else 1)
