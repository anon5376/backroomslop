extends SceneTree
## Mega-upgrade suite: rooms, scraps, way-plates, beacon, compass, stealth,
## FOV, glowsticks, intro/hunt/end UI. Run via tools/regression.py.
const MG = preload("res://scripts/maze_generator.gd")
const TF = preload("res://scripts/texture_factory.gd")
const AM = preload("res://scripts/audio_manager.gd")
const GM = preload("res://scripts/game_manager.gd")
const UI = preload("res://scripts/ui_manager.gd")
const Campaign = preload("res://scripts/campaign.gd")
const EV = preload("res://scripts/entity_visual.gd")

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _run() -> void:
	_rooms_and_validation()
	_dressing()
	_compass()
	await _stealth()
	_fov_and_glow()
	_ui_bits()
	_audio_beacon()
	_graphics()
	print("UPGRADE TEST: %s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)


func _rooms_and_validation() -> void:
	for s: int in [0, 42, 999, 1234, 424242]:
		var m := MG.new()
		check(m.generate_with_validation(s) == s, "seed retained %d" % s)
		var ok_rooms: bool = true
		for r: Rect2i in [MG.BREAK_ROOM, MG.ARCHIVE_ROOM]:
			for yy: int in range(r.position.y, r.position.y + r.size.y):
				for xx: int in range(r.position.x, r.position.x + r.size.x):
					if m.grid[yy * MG.GRID_W + xx] != 0:
						ok_rooms = false
		check(ok_rooms, "rooms stamped floor %d" % s)
		var ok_scraps: bool = true
		for c: Vector2i in MG.SCRAP_CELLS:
			if m.grid[c.y * MG.GRID_W + c.x] != 0 or m.dist_map[c.y * MG.GRID_W + c.x] < 0:
				ok_scraps = false
		check(ok_scraps, "scrap cells floor+reachable %d" % s)
	check(MG.SCRAP_CELLS.size() == 6, "6 scrap cells")


func _dressed_level(lv: int) -> Array:
	var m := MG.new()
	m.level_index = lv
	m.generate_with_validation(31337)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var mats: Dictionary = TF.load_materials(rng, lv)
	var world := Node3D.new()
	root.add_child(world)
	m.build_world(world, mats)
	var am := AM.new()
	var info: Dictionary = m.build_dressing(world, mats, am)
	return [m, world, info]


func _dressing() -> void:
	var lv0: Array = _dressed_level(0)
	var m: MG = lv0[0]
	var world: Node3D = lv0[1]
	var info: Dictionary = lv0[2]
	check(info["stairs_area"] != null and info["exit_area"] == null, "L0 dressing keeps stairs, no exit")
	var lv2: Array = _dressed_level(2)
	check((lv2[2] as Dictionary)["exit_area"] != null and (lv2[2] as Dictionary)["stairs_area"] == null, "L2 dressing keeps exit, no stairs")
	(lv2[1] as Node).free()
	# Way-plates: 4 per level, true-pointing, arrow matches yaw.
	for lv: int in 3:
		var built: Array = _dressed_level(lv) if lv != 0 else lv0
		var lm: MG = built[0]
		var lworld: Node3D = built[1]
		var plates: Array[Node] = lworld.find_children("WayPlate_*", "", true, false)
		check(plates.size() == 6, "L%d 6 way-plates (%d)" % [lv, plates.size()])
		var all_true: bool = true
		for plate: Node in plates:
			var s: int = int(plate.get_meta("station"))
			if s != lv:
				all_true = false
			var flow: Vector2i = plate.get_meta("flow")
			var cell: Vector2i = plate.get_meta("cell")
			var dist: PackedInt32Array = lm._bfs_distances(MG.station_cell_global(s))
			var d: int = dist[cell.y * MG.GRID_W + cell.x]
			if d < 6 or d > 40 or dist[(cell + flow).y * MG.GRID_W + (cell + flow).x] != d - 1:
				all_true = false
			var n3: Node3D = plate as Node3D
			var lx := Vector2i(roundi(cos(n3.rotation.y)), roundi(-sin(n3.rotation.y)))
			var want: String = "0%d >" % (s + 1) if flow == lx else "< 0%d" % (s + 1)
			var label: Label3D = n3.get_child(2) as Label3D
			if label == null or label.text != want:
				all_true = false
		check(all_true, "L%d all plates point downhill with matching arrows" % lv)
		if lv != 0:
			lworld.free()
	# Scraps: 6, correct cells, readable prompts.
	var scraps: Array[Node] = world.find_children("LoreScrap_*", "", true, false)
	check(scraps.size() == 6, "6 lore scraps (%d)" % scraps.size())
	var cells_ok: bool = true
	for i: int in scraps.size():
		var sn: Node3D = scraps[i] as Node3D
		var want_w: Vector3 = m.cell_to_world(MG.SCRAP_CELLS[(sn as LoreScrap).scrap_id])
		if sn.position.distance_to(Vector3(want_w.x, 0, want_w.z)) > 0.01:
			cells_ok = false
		if String((sn as LoreScrap).prompt_text()).is_empty():
			cells_ok = false
	check(cells_ok, "scraps on scrap cells with prompts")
	check(world.get_node_or_null("ExitBeacon") != null, "exit beacon emitter placed")
	check(world.get_node_or_null("Table") != null, "break-room table placed")
	check(world.find_children("Shelf*", "", true, false).size() == 3, "3 archive shelves")
	world.free()


func _compass() -> void:
	var tape: String = Campaign.compass_tape(0.0, 0.0)
	check(tape.length() == 25, "tape is 25 chars")
	check(tape[12] == "*", "dead-ahead target centers a star")
	var tape2: String = Campaign.compass_tape(0.0, 45.0)
	check(tape2[12] == "|", "off-axis heading centers a bar")
	check(tape2.count("*") >= 1, "target star on tape")
	check(Campaign.compass_tape(0.0, 180.0).count("*") == 0, "target behind is off-tape")
	var tape3: String = Campaign.compass_tape(90.0, 90.0)
	check(tape3[12] == "*", "east dead-ahead centers a star")
	check(Campaign.compass_tape(45.0, 45.0)[12] == "*", "diagonal dead-ahead centers a star")


func _stealth() -> void:
	var player := preload("res://scenes/player.tscn").instantiate() as Player
	var entity := preload("res://scenes/entity.tscn").instantiate() as Stalker
	root.add_child(player)
	root.add_child(entity)
	player.set_physics_process(false)
	entity.set_physics_process(false)
	entity.player = player
	entity.active = true
	entity.maze = MG.new()
	entity.maze.generate_with_validation(1234)
	entity.astar = GridAStar.new(MG.GRID_W, MG.GRID_H, entity.maze.get_blocked())
	entity.position = Vector3(0, 0, 4)
	player.position = Vector3(0, 0, -4)  # 8m, clear sight
	await physics_frame
	player.crouched = true
	entity.state = Stalker.State.STALK
	entity._tick_stalk(0.1)
	check(entity.state == Stalker.State.STALK, "crouched prey at 8m does not trigger")
	player.crouched = false
	entity._tick_stalk(0.1)
	check(entity.state == Stalker.State.HUNT, "standing prey at 8m triggers")
	entity.state = Stalker.State.STALK
	player.crouched = true
	player.position = Vector3(0, 0, 0.5)  # 3.5m
	await physics_frame
	entity._tick_stalk(0.1)
	check(entity.state == Stalker.State.HUNT, "crouched prey at 3.5m triggers")
	# Lose timer runs double-speed for unseen unheard crouched prey.
	entity._heard_recently = 0.0
	player.crouched = true
	player.position = Vector3(0, 0, -200)
	await physics_frame
	entity._tick_hunt(1.0)
	check(entity._lose_t >= 1.9, "crouch doubles lose rate (%.2f)" % entity._lose_t)
	player.queue_free()
	entity.queue_free()
	await process_frame


func _fov_and_glow() -> void:
	var g := GM.new()
	check(g.fov == 75.0, "default fov 75")
	g.player = null
	g.main_ref = null
	g.ui = null
	g.apply_settings(0.0022, "High", false, 80.0)
	check(g.fov == 80.0, "fov setting applies")
	g.apply_settings(0.0022, "High", false, 200.0)
	check(g.fov == 90.0, "fov clamps to 90")
	var before: int = g.glowsticks
	g.drop_glowstick()
	check(g.glowsticks == before, "drop with none carried is a no-op")
	var stick := Glowstick.build(1)
	check(stick.get_child_count() == 2, "glowstick has tube + light")
	var lamp: OmniLight3D = stick.get_node("OmniLight3D") if stick.has_node("OmniLight3D") else stick.get_child(1)
	check(lamp is OmniLight3D and (lamp as OmniLight3D).omni_range == 2.5, "glowstick light range 2.5")
	stick.free()
	var net_script: Script = preload("res://scripts/net_manager.gd")
	var net_inst: Node = net_script.new()
	check(net_inst.has_method("request_glowstick"), "net exposes glowstick requests")
	check(net_inst.has_signal("glowstick_spawned"), "net exposes glowstick signal")
	net_inst.free()
	g.free()


func _ui_bits() -> void:
	var ui := UI.new()
	root.add_child(ui)
	await process_frame
	var g := GM.new()
	g.ui = ui
	ui.game = g
	ui.show_hud(7)
	check(ui._intro_label.visible, "intro card shows on run start")
	ui._intro_t = 0.01
	await process_frame
	await process_frame
	check(not ui._intro_label.visible, "intro card fades")
	ui.hunt_flash()
	check(ui._hunt_t > 0.0, "hunt flash arms")
	check(ui._vignette != null and ui._vignette.texture != null, "vignette overlay present")
	check(ui._hud.get_child(0) == ui._vignette, "vignette sits behind HUD")
	ui.show_death("caught", 7, 60.0)
	check(ui._end_sub.text == "Answered. It finished learning you.", "death names the fate")
	ui.show_win(61000, 7)
	check("Notes" in ui._end_stats.text, "win stats count notes")
	ui.free()
	g.free()


func _graphics() -> void:
	var m := MG.new()
	m.generate_with_validation(31337)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var mats: Dictionary = TF.load_materials(rng)
	var world := Node3D.new()
	root.add_child(world)
	m.build_world(world, mats)
	var am := AM.new()
	m.build_dressing(world, mats, am)
	var s: Dictionary = PropFactory.get_shared()
	# Rail frames: 4 per fixture + 2 rods per hanging drop, aluminum.
	var fixtures: int = 0
	var hanging: int = 0
	for i: int in MG.GRID_W * MG.GRID_H:
		if m.fixture_state[i] != MG.F_NONE:
			fixtures += 1
		if m.fixture_hanging[i] == 1:
			hanging += 1
	var frames: MultiMeshInstance3D = world.get_node_or_null("Frames")
	check(frames != null and frames.multimesh.instance_count == 4 * fixtures + 2 * hanging, "rail frame instances (%d)" % (frames.multimesh.instance_count if frames != null else -1))
	check(frames != null and frames.material_override == s["alu"], "frames use aluminum")
	check(world.get_node_or_null("PillarTrim") != null and (world.get_node_or_null("PillarTrim") as MultiMeshInstance3D).multimesh.instance_count == 72, "pillar trim 72 instances")
	var plates: MultiMeshInstance3D = world.get_node_or_null("WallPlates")
	check(plates != null and plates.multimesh.instance_count >= 100 and plates.multimesh.instance_count <= 120, "wall plates capped (%d)" % (plates.multimesh.instance_count if plates != null else -1))
	check(plates != null and plates.material_override == s["ivory"], "plates use ivory")
	check(world.find_children("WestPipe*", "", true, false).size() == 8, "8 west pipe segments")
	world.free()
	# Rack tray, exit arch + spill, pickup rings.
	var rack: Node3D = PropFactory.build_server_rack(null)
	check(rack.find_children("*", "MeshInstance3D", true, false).size() >= 38, "rack carries tray + cables")
	rack.free()
	var exit_door: Node3D = PropFactory.build_exit_door()
	check(exit_door.find_children("ExitSpill*", "", true, false).size() == 2, "exit spill both sides")
	var ivory_n: int = 0
	for mi: Node in exit_door.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override == s["ivory"]:
			ivory_n += 1
	check(ivory_n == 3, "exit arch trim 3 pieces")
	exit_door.free()
	var lm_script: Script = preload("res://scripts/light_manager.gd")
	var lm: Node3D = lm_script.new()
	var h1: float = lm._hash12(Vector2(3.0, 7.0))
	check(h1 == lm._hash12(Vector2(3.0, 7.0)) and h1 >= 0.0 and h1 < 1.0, "fixture hash deterministic in range")
	lm.free()
	var wpu: Pickup = PropFactory.build_pickup("water", null)
	var wring: MeshInstance3D = wpu.get_node_or_null("GlowRing")
	check(wring != null and wring.material_override == s["ring_water"], "water ring material")
	wpu.free()
	var bpu: Pickup = PropFactory.build_pickup("bread", null)
	var bring: MeshInstance3D = bpu.get_node_or_null("GlowRing")
	check(bring != null and bring.material_override == s["ring_bread"], "bread ring material")
	bpu.free()
	# Eye-light follows hunt blend; stalk keeps an ember.
	var vis := EV.new()
	root.add_child(vis)
	vis.build()
	check(vis.eye_light != null and vis.eye_light.light_energy == 0.0, "eye-light starts dark")
	vis.animate(0.1, 2, Vector3.ZERO, false, Vector3.ZERO)
	check(vis.eye_light.light_energy > 0.5, "hunt lights the eyes (%.2f)" % vis.eye_light.light_energy)
	vis.free()
	var stalk := EV.new()
	root.add_child(stalk)
	stalk.build()
	stalk.animate(0.1, 1, Vector3.ZERO, false, Vector3.ZERO)
	check(absf(stalk.eye_light.light_energy - 0.3) < 0.05, "stalk keeps an ember (%.2f)" % stalk.eye_light.light_energy)
	stalk.free()


func _audio_beacon() -> void:
	var am := AM.new()
	root.add_child(am)
	await process_frame
	check(am.beacon_stream != null, "beacon stream synthesized")
	if am.beacon_stream != null:
		check(absf(am.beacon_stream.get_length() - 6.0) < 0.05, "beacon loop is 6s")
	am.free()
