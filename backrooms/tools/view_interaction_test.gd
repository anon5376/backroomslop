extends SceneTree
class Target extends StaticBody3D:
	var uses := 0
	func interact() -> void:
		uses += 1
	func prompt_text() -> String:
		return "USE"
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1
func _run() -> void:
	var player := preload("res://scenes/player.tscn").instantiate() as Player
	root.add_child(player)
	player.set_physics_process(false)
	player._cam3.reparent(root)
	player._camf.reparent(root)
	var campaign := preload("res://scripts/campaign.gd").new()
	campaign.player = player
	var target := Target.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.2)
	shape.shape = box
	target.add_child(shape)
	root.add_child(target)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(4, 3, 0.2)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	root.add_child(wall)
	wall.position = Vector3(10, 1.5, 0)
	for mode: int in 3:
		player.view_mode = mode
		# Fix boom extension for a deterministic open-space camera fixture.
		player._boom.set_physics_process(false)
		player._boom2.set_physics_process(false)
		var cam: Camera3D = player.camera if mode == 0 else (player._cam3 if mode == 1 else player._camf)
		cam.global_position = Vector3(0, 1.62, 0 if mode == 0 else (3.4 if mode == 1 else -3.0))
		var direction := Vector3.FORWARD if mode != 2 else Vector3.BACK
		cam.look_at(cam.global_position + direction)
		target.position = Vector3(0, 1.62, direction.z * 2.0)
		await physics_frame
		await process_frame
		var before := target.uses
		check(campaign.focused_interactable() == target, "view %d nearby prompt excludes self" % mode)
		player._try_interact()
		check(target.uses == before + 1, "view %d nearby interaction" % mode)
		target.position.z = direction.z * 3.5
		await physics_frame
		await process_frame
		before = target.uses
		player._try_interact()
		check(target.uses == before and campaign.focused_interactable() == null, "view %d rejects beyond actor reach" % mode)
		target.position.z = direction.z * 2.0
		wall.position = Vector3(0, 1.5, direction.z)
		await physics_frame
		await process_frame
		before = target.uses
		player._try_interact()
		check(target.uses == before and campaign.focused_interactable() == null, "view %d wall blocks use and prompt" % mode)
		wall.position.x = 10
	player.view_mode = Player.View.CHASE
	player._cam3.global_position = Vector3(0, 1.62, 6)
	player._cam3.look_at(Vector3(0, 1.62, 0))
	target.position = Vector3(0, 1.62, 4)
	await physics_frame
	await process_frame
	var uses_before := target.uses
	player._try_interact()
	check(target.uses == uses_before and campaign.focused_interactable() == null, "camera-visible target outside actor reach rejected")
	player._cam3.global_position = Vector3(3, 1.62, 0)
	target.position = Vector3(0, 1.62, -2)
	player._cam3.look_at(target.position)
	wall_box.size = Vector3(0.4, 3, 0.2)
	wall.position = Vector3(0, 1.5, -1)
	await physics_frame
	await process_frame
	var camera_query := PhysicsRayQueryParameters3D.create(player._cam3.global_position, target.position, 0xFFFFFFFF, [player.get_rid()])
	var camera_hit := player.get_world_3d().direct_space_state.intersect_ray(camera_query)
	print("OFFSET FIXTURE camera=%s target=%s hit=%s" % [player._cam3.global_position, target.position, camera_hit])
	check(not camera_hit.is_empty() and camera_hit.collider == target, "offset camera sees target around actor-only obstruction")
	player._try_interact()
	check(target.uses == uses_before and campaign.focused_interactable() == null, "actor-only obstruction blocks camera-visible target")
	player._cam3.free()
	player._camf.free()
	player.free()
	player = preload("res://scenes/player.tscn").instantiate() as Player
	root.add_child(player)
	campaign.player = player
	wall_box.size = Vector3(4, 3, 0.2)
	for mode: int in 3:
		wall.position.x = 10
		var direction: float = -1.0 if mode != Player.View.FRONT else 1.0
		target.position = Vector3(0, 1.62, direction * 2)
		for frame: int in 10:
			await physics_frame
			await process_frame
		var count: int = target.uses
		check(campaign.focused_interactable() == target, "live boom view %d prompt" % mode)
		player._try_interact()
		check(target.uses == count + 1, "live boom view %d use" % mode)
		wall.position = Vector3(0, 1.5, direction)
		for frame: int in 10:
			await physics_frame
			await process_frame
		count = target.uses
		player._try_interact()
		check(target.uses == count and campaign.focused_interactable() == null, "live boom view %d wall rejection" % mode)
		player.cycle_view()
	player.free()
	target.free()
	wall.free()
	campaign.free()
	print("VIEW INTERACTION TEST: %s" % ["ALL PASS" if failures == 0 else "%d FAILURES" % failures])
	quit(0 if failures == 0 else 1)
