extends SceneTree
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
func settle() -> void:
	for tick: int in 120:
		await physics_frame
		await process_frame
func _run() -> void:
	var actions := ["crouch", "toggle_view", "move_left", "move_right", "move_forward", "move_back", "sprint", "flash", "interact", "eat_bread"]
	for action: String in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	var scene := load("res://scenes/player.tscn") as PackedScene
	var player := scene.instantiate() as Player
	var other := scene.instantiate() as Player
	root.add_child(player)
	root.add_child(other)
	other.position.x = 5.0
	player.active = true
	await settle()
	var baseline := player.position.y
	check(player.is_on_floor(), "production player settled on floor")
	check(player.collision.shape != other.collision.shape, "player capsule resources are independent")
	for cycle: int in 3:
		Input.action_press("crouch")
		await physics_frame
		await process_frame
		Input.action_release("crouch")
		await settle()
		check(player.crouched, "cycle %d crouch input accepted" % cycle)
		check(absf(player.position.y - baseline) < 0.02, "cycle %d crouch preserves foot origin y=%.4f" % [cycle, player.position.y])
		check(absf(player.collision.position.y - player.collision.shape.height * 0.5) < 0.001, "crouch capsule bottom anchored")
		check(absf(other.collision.shape.height - 1.8) < 0.001, "other player retains standing capsule")
		check(absf(player.head.global_position.y - (baseline + 1.05)) < 0.02, "crouched eye height stays above floor")
		Input.action_press("crouch")
		await physics_frame
		await process_frame
		Input.action_release("crouch")
		await settle()
		check(not player.crouched, "stand input accepted")
		check(absf(player.position.y - baseline) < 0.02 and player.is_on_floor(), "standing restores grounded origin")
	player.free()
	other.free()
	floor_body.free()
	print("CROUCH TEST: %s" % ["ALL PASS" if failures == 0 else "%d FAILURES" % failures])
	quit(0 if failures == 0 else 1)
