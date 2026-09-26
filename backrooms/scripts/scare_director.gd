class_name ScareDirector
extends Node
## Timed scares every 90-150s: lights die row-by-row toward the player,
## a silhouette flashes in view for 0.3s, static swells, everything restores.
## Never fires during a chase. Uses its own prop silhouette, never the entity.

var game: Node = null
var lights: LightManager = null
var maze: MazeGenerator = null
var player: Player = null
var entity: Stalker = null
var ui: Node = null  # UIManager, untyped to avoid load-order coupling
var panel_materials: Array = []

var active: bool = false
var _t: float = 0.0
var _next: float = 100.0
var _running: bool = false
var _swell: AudioStreamPlayer


func setup(p_game: Node, p_lights: LightManager, p_maze: MazeGenerator, p_player: Player,
		p_entity: Stalker, p_ui: Node, p_panels: Array, screech: AudioStream) -> void:
	game = p_game
	lights = p_lights
	maze = p_maze
	player = p_player
	entity = p_entity
	ui = p_ui
	panel_materials = p_panels
	if _swell == null or not is_instance_valid(_swell):
		_swell = AudioStreamPlayer.new()
		_swell.stream = screech
		_swell.volume_db = -10.0
		add_child(_swell)
	_running = false
	_t = 0.0
	_next = randf_range(90.0, 150.0)


func _process(delta: float) -> void:
	if not active or _running:
		return
	if game != null and game.has_method("is_playing") and not game.is_playing():
		return
	if entity != null and entity.state == Stalker.State.HUNT:
		_t = 0.0  # chases reset the clock
		return
	_t += delta
	if _t >= _next:
		_t = 0.0
		_next = randf_range(90.0, 150.0)
		_fire()


func _pick_variant() -> int:
	return randi_range(0, 2)


func _fire() -> void:
	_running = true
	match _pick_variant():
		0:
			await _scare_row_blackout()
		1:
			await _scare_surge()
		_:
			await _scare_strobe()
	lights.clear_blackouts()
	for m: ShaderMaterial in panel_materials:
		m.set_shader_parameter("global_dim", 1.0)
	_running = false


func _scare_row_blackout() -> void:
	var pc: Vector2i = maze.world_to_cell(player.global_position)
	# Pick a row marching toward the player from a random direction.
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var d: Vector2i = dirs[randi_range(0, 3)]
	var row: Array[Vector2i] = []
	for k: int in range(6, 0, -1):
		row.append(Vector2i(pc.x + d.x * k, pc.y + d.y * k))
	for i: int in row.size():
		if not _still_ok():
			break
		lights.set_blackout(row[i], true)
		for m: ShaderMaterial in panel_materials:
			m.set_shader_parameter("global_dim", 1.0 - 0.18 * float(i + 1))
		await get_tree().create_timer(0.22, false).timeout
	if _still_ok():
		_flash_silhouette()
		_swell.play()
		if ui != null and ui.has_method("static_burst"):
			ui.static_burst(0.6)
		await get_tree().create_timer(0.45, false).timeout


func _scare_surge() -> void:
	"""Every panel flares hot-white for half a second, then snaps back."""
	if not _still_ok():
		return
	for m: ShaderMaterial in panel_materials:
		m.set_shader_parameter("global_dim", 1.7)
	_swell.play()
	if ui != null and ui.has_method("static_burst"):
		ui.static_burst(0.3)
	await get_tree().create_timer(0.5, false).timeout


func _scare_strobe() -> void:
	"""Three hard full-room blinks. No silhouette: the scare is the dark."""
	for k: int in 3:
		if not _still_ok():
			break
		for m: ShaderMaterial in panel_materials:
			m.set_shader_parameter("global_dim", 0.1)
		await get_tree().create_timer(0.12, false).timeout
		for m: ShaderMaterial in panel_materials:
			m.set_shader_parameter("global_dim", 1.0)
		await get_tree().create_timer(0.18, false).timeout
	_swell.play()


func _still_ok() -> bool:
	if game != null and game.has_method("is_playing") and not game.is_playing():
		return false
	if entity != null and entity.state == Stalker.State.HUNT:
		return false
	return true


func _flash_silhouette() -> void:
	"""0.3s dark figure at a visible floor cell 12-20m out. Pure prop."""
	var cam_pos: Vector3 = player.camera.global_position
	var cam_fwd: Vector3 = -player.camera.global_transform.basis.z
	var spot := Vector3.ZERO
	var found: bool = false
	for attempt: int in 24:
		var ang: float = randf_range(0.0, TAU)
		var r: float = randf_range(12.0, 20.0)
		var p := Vector3(cam_pos.x + cos(ang) * r, 0, cam_pos.z + sin(ang) * r)
		var cell: Vector2i = maze.world_to_cell(p)
		if cell.x < 1 or cell.y < 1 or cell.x >= MazeGenerator.GRID_W - 1 or cell.y >= MazeGenerator.GRID_H - 1:
			continue
		if maze.grid[cell.y * MazeGenerator.GRID_W + cell.x] != 0:
			continue
		var s: Vector3 = maze.cell_to_world(cell)
		var to_s: Vector3 = (s + Vector3(0, 1.4, 0)) - cam_pos
		if cam_fwd.angle_to(to_s.normalized()) > 0.7:
			continue
		var query := PhysicsRayQueryParameters3D.create(cam_pos, s + Vector3(0, 1.4, 0), 1, [player.get_rid()])
		if get_tree().root.world_3d.direct_space_state.intersect_ray(query).is_empty():
			spot = s
			found = true
			break
	if not found:
		return
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.01, 0.01, 0.01)
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var fig := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 2.1, 0.25)
	fig.mesh = bm
	fig.material_override = dark
	fig.position = spot + Vector3(0, 1.05, 0)
	get_tree().current_scene.add_child(fig)
	await get_tree().create_timer(0.3, false).timeout
	if is_instance_valid(fig):
		fig.queue_free()
