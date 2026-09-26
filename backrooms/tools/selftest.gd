extends SceneTree
## Deterministic logic self-test. No window, no scene, pure RefCounted math.
## Run: godot --headless --log-file /tmp/st.log --path backrooms \
##        --script res://tools/selftest.gd
## Exit code 0 = all pass.

const MG = preload("res://scripts/maze_generator.gd")
const GA = preload("res://scripts/grid_astar.gd")
const TF = preload("res://scripts/texture_factory.gd")
const AM = preload("res://scripts/audio_manager.gd")
const GM = preload("res://scripts/game_manager.gd")
const LM = preload("res://scripts/light_manager.gd")
const UI = preload("res://scripts/ui_manager.gd")

var _fails: int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS ", label)
	else:
		_fails += 1
		printerr("FAIL ", label)


func _init() -> void:
	_determinism()
	_validation_matrix()
	_astar()
	_audio()
	_textures()
	_meters()
	_build()
	_mp_netids()
	_layout()
	_flicker_punch()
	await process_frame  # let the tree settle so player _ready fires on add
	_views()
	_settings()
	_inventory()
	_net_flags()
	if _fails == 0:
		print("SELFTEST ALL PASS")
	else:
		printerr("SELFTEST FAILURES: %d" % _fails)
	quit(_fails)


func _determinism() -> void:
	var a = MG.new()
	var b = MG.new()
	_check(a.generate_with_validation(1234) == b.generate_with_validation(1234), "same seed validates identically")
	_check(a.grid == b.grid, "same seed identical grid bytes")
	_check(a.spawn_cell == b.spawn_cell and a.exit_cell == b.exit_cell, "same seed identical spawn/exit")
	_check(a.spawn_cell == Vector2i(96, 98) and a.exit_cell == Vector2i(153, 96), "authored fixed spawn/exit")
	var c = MG.new()
	c.generate_with_validation(999)
	_check(a.grid != c.grid, "different seeds vary the facility layout")


func _validation_matrix() -> void:
	for s: int in [0, 1, 42, 777, 999999, -5, 2147483647]:
		var m = MG.new()
		var used: int = m.generate_with_validation(s)
		_check(used != -1, "seed %d validates" % s)
		if used == -1:
			continue
		var exit_d: int = m.dist_map[m.exit_cell.y * MG.GRID_W + m.exit_cell.x]
		_check(exit_d > 0, "seed %d exit reachable (dist %d)" % [s, exit_d])
		var reached: int = 0
		var total: int = 0
		for i: int in m.grid.size():
			if m.grid[i] == 0:
				total += 1
				if m.dist_map[i] != -1:
					reached += 1
		_check(float(reached) / float(total) >= 0.95, "seed %d reachability %.1f%%" % [s, 100.0 * reached / total])
		_check(m.dark_zones.size() == 3, "seed %d three dark zones" % s)
		_check(m.humming_rooms.size() == 4, "seed %d four humming rooms" % s)


func _astar() -> void:
	var m = MG.new()
	m.generate_with_validation(4242)
	var astar = GA.new(MG.GRID_W, MG.GRID_H, m.get_blocked())
	var path: Array[Vector2i] = astar.find_path(m.spawn_cell, m.exit_cell)
	_check(path.size() > 5, "A* spawn->exit path length %d" % path.size())
	var ok: bool = path.size() > 0
	if ok:
		for c: Vector2i in path:
			if m.grid[c.y * MG.GRID_W + c.x] != 0:
				ok = false
				break
		# 4-dir adjacency.
		for i: int in range(1, path.size()):
			var step: Vector2i = (path[i] - path[i - 1]).abs()
			if step != Vector2i(1, 0) and step != Vector2i(0, 1):
				ok = false
				break
	_check(ok, "A* path walkable + 4-dir adjacent")
	_check(astar.find_path(Vector2i(0, 0), m.exit_cell).is_empty(), "A* from wall cell = empty")


func _wav_peak(w: AudioStreamWAV) -> float:
	var peak: float = 0.0
	var d: PackedByteArray = w.data
	for i: int in range(0, d.size(), 2):
		var v: int = d[i] | (d[i + 1] << 8)
		if v >= 32768:
			v -= 65536
		peak = maxf(peak, absf(float(v) / 32767.0))
	return peak


func _audio() -> void:
	var am = AM.new()
	_check(_wav_peak(am._synth_hum()) > 0.05, "hum synth non-silent")
	_check(_wav_peak(am._synth_drone()) > 0.05, "drone synth non-silent")
	_check(_wav_peak(am._synth_step()) > 0.05, "step synth non-silent")
	_check(_wav_peak(am._synth_screech()) > 0.2, "screech synth hot")
	_check(_wav_peak(am._synth_thunk()) > 0.1, "thunk synth non-silent")
	_check(_wav_peak(am._synth_creak()) > 0.05, "creak synth non-silent")
	_check(_wav_peak(am._synth_gulp()) > 0.1, "gulp synth non-silent")
	_check(_wav_peak(am._synth_drag()) > 0.1, "drag synth non-silent")
	var hum: AudioStreamWAV = am._synth_hum()
	_check(hum.loop_mode == AudioStreamWAV.LOOP_FORWARD, "hum loops forward")


func _textures() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for entry: Array in [["wallpaper", TF.make_wallpaper(rng)], ["wallpaper_b", TF.make_wallpaper_b(rng)], ["carpet", TF.make_carpet(rng)], ["ceiling", TF.make_ceiling(rng)], ["floortile", TF.make_floortile(rng)], ["hazard", TF.make_hazard(rng)], ["metaldor", TF.make_metaldor(rng)]]:
		var img: Image = (entry[1] as ImageTexture).get_image()
		_check(img.get_size() == Vector2i(256, 256), "%s is 256px" % entry[0])
		var a: Color = img.get_pixel(10, 10)
		var b: Color = img.get_pixel(200, 150)
		_check(a != b, "%s non-uniform" % entry[0])


func _meters() -> void:
	var g = GM.new()
	g.hunger = 0.5
	g.thirst = 0.5
	g.drink(0.3)
	_check(is_equal_approx(g.thirst, 0.8), "drink restores thirst")
	g.eat(0.9)
	_check(is_equal_approx(g.hunger, 1.0), "eat clamps at 1.0")
	g.hunger = 0.0
	g.thirst = 0.0
	_check(g.get_move_factor() < 1.0, "starving slows movement")
	_check(g.get_stamina_drain_mul() > 1.0, "parched drains stamina faster")
	_check(g.get_stamina_regen_mul() < 1.0, "starving slows stamina regen")
	g.hunger = 1.0
	g.thirst = 1.0
	_check(g.get_move_factor() == 1.0, "fed move factor neutral")


func _build() -> void:
	var m = MG.new()
	m.generate_with_validation(31337)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var mats: Dictionary = TF.load_materials(rng)
	var root := Node3D.new()
	m.build_world(root, mats)
	var am = AM.new()  # bare: null streams tolerated by builders
	var info: Dictionary = m.build_dressing(root, mats, am)
	_check(info["stairs_area"] != null and info["exit_area"] == null, "L0 build produces stairs, no exit")
	var waters: int = int(info["pickup_water"])
	var breads: int = int(info["pickup_bread"])
	_check(waters >= 34 and waters <= 50, "seed-varied water pickups (%d)" % waters)
	_check(breads >= 28 and breads <= 44, "seed-varied bread pickups (%d)" % breads)
	_check(root.find_children("Cones*", "", true, false).is_empty(), "no light-shaft cones")
	_check(root.get_node_or_null("Baseboards") != null, "baseboards built")
	_check(root.get_node_or_null("PanelsFlicker") != null, "flicker panels built")
	_check(root.find_children("ServerRack_*", "", true, false).size() == 20, "20 authored server racks")
	_check(root.find_children("Gateway_*", "", true, false).size() == 4, "4 wing gateways")
	_check(root.find_children("FakeDoor_*", "", true, false).size() == 6, "6 fake doors")
	root.free()


func _mp_netids() -> void:
	# Both peers must build identical pickup net_id -> position maps.
	var ids: Dictionary = {}
	var totals: Array[int] = []
	for attempt: int in 2:
		var m = MG.new()
		var used: int = m.generate_with_validation(555)
		var rng := RandomNumberGenerator.new()
		rng.seed = used
		var mats: Dictionary = TF.load_materials(rng)
		var root := Node3D.new()
		m.build_world(root, mats)
		var am = AM.new()
		var info: Dictionary = m.build_dressing(root, mats, am)
		totals.append(int(info["pickup_water"]) + int(info["pickup_bread"]))
		for p in info["pickups"]:
			var pk: Pickup = p as Pickup
			var pos: Vector3 = (pk as Node3D).position
			if ids.has(pk.net_id):
				_check(ids[pk.net_id] == pos, "net_id %d identical across builds" % pk.net_id)
			else:
				ids[pk.net_id] = pos
		root.free()
	_check(totals[0] == totals[1], "seed-varied counts deterministic (%d)" % totals[0])
	_check(ids.size() >= 62 and ids.size() <= 94, "pickups carry net ids (%d)" % ids.size())


func _net_flags() -> void:
	var nm = load("res://scripts/net_manager.gd").new()
	_check(nm.is_mp() == false and nm.am_server() == true and nm.is_host(), "net defaults to solo/host/server")
	nm.mode = "client"
	_check(nm.is_mp() == true and nm.am_server() == false and not nm.is_host(), "client mode flags flip")
	nm.mode = "host"
	_check(nm.is_mp() == true and nm.am_server() == true and nm.is_host(), "host mode flags")
	nm.free()


func _layout() -> void:
	var m = MG.new()
	m.generate_with_validation(4242)
	var rooms: int = 0
	for cx: int in [20, 24, 28]:
		for cz: int in [84, 88, 92]:
			if m.grid[(cz + 1) * MG.GRID_W + cx + 1] == 0:
				rooms += 1
	_check(rooms == 9, "nine west rooms open")
	_check(m.grid[96 * MG.GRID_W + 96] == 0, "lobby floor open")
	_check(m.grid[96 * MG.GRID_W + 147] == 0, "server hall floor open")
	_check(m.grid[147 * MG.GRID_W + 96] == 0, "dark pocket floor open")
	_check(m.grid[96 * MG.GRID_W + 152] == 0 and m.grid[95 * MG.GRID_W + 152] == 1 and m.grid[97 * MG.GRID_W + 152] == 1, "exit room single door")
	_check(m.region_of(Vector2i(96, 96)) == "lobby", "lobby region")
	_check(m.region_of(Vector2i(22, 86)) == "west", "west region")
	_check(m.region_of(Vector2i(92, 20)) == "service", "service region")
	_check(m.region_of(Vector2i(147, 96)) == "server", "server region")
	_check(m.region_of(Vector2i(96, 147)) == "dark", "dark region")
	_check(m.district_of(Vector2i(92, 20)) == 1, "service district concrete")
	_check(m.district_of(Vector2i(147, 96)) == 2, "server district")
	_check(m.pillar_cells.size() == 36, "district + hall pillars")


func _flicker_punch() -> void:
	var m = MG.new()
	m.generate_with_validation(4242)
	var fl: int = 0
	var total: int = 0
	for i: int in m.fixture_state.size():
		var st: int = m.fixture_state[i]
		if st == MG.F_NONE:
			continue
		total += 1
		if st == MG.F_FLICKER:
			fl += 1
	var frac: float = float(fl) / float(maxi(total, 1))
	_check(frac < 0.08, "flicker fraction low (%.3f)" % frac)
	var lm = LM.new()
	var floor_v: float = 1.0
	for s: int in 240:
		var v: float = lm._flicker_value(1.7, Vector2(3.0, 5.0), float(s) * 0.5)
		floor_v = minf(floor_v, v)
	_check(floor_v <= 0.0, "flicker kill gate hits full off (%.3f)" % floor_v)


func _settings() -> void:
	var g = GM.new()
	_check(g.vhs_enabled == false, "vhs off by default")


func _inventory() -> void:
	var g = GM.new()
	g.add_pickup("water")
	g.add_pickup("water")
	g.add_pickup("bread")
	_check(g.inv_water == 2 and g.inv_bread == 1, "pickups stash counts")
	g.thirst = 0.5
	_check(g.drink_inv() == true, "drink consumes stash")
	_check(g.inv_water == 1 and g.thirst > 0.9, "drink restores thirst")
	g.thirst = 1.0
	_check(g.drink_inv() == false and g.inv_water == 1, "no drink at full")
	g.hunger = 0.4
	_check(g.eat_inv() == true and g.inv_bread == 0, "eat consumes stash")
	_check(g.eat_inv() == false, "no eat when empty")
	var ui := UI.new()
	root.add_child(ui)
	ui.setup(g, null, null)
	ui.toggle_inventory()
	_check(ui.is_inventory_open(), "inventory opens")
	ui.toggle_inventory()
	_check(not ui.is_inventory_open(), "inventory closes")
	ui.set_vhs_enabled(true)
	_check(ui._vhs_layer.visible, "vhs toggle shows overlay")
	ui.set_vhs_enabled(false)
	_check(not ui._vhs_layer.visible, "vhs toggle hides overlay")
	for a: String in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "flash", "interact", "eat_bread", "toggle_view"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
	var ps := load("res://scenes/player.tscn") as PackedScene
	var p := ps.instantiate()
	root.add_child(p)
	p.game = g
	p.active = true
	g.ui = ui
	g.thirst = 0.5
	g.inv_water = 1
	ui.toggle_inventory()
	Input.action_press("interact")
	p._physics_process(0.016)
	Input.action_release("interact")
	_check(g.inv_water == 0, "E with pack open drinks")
	g.inv_bread = 1
	g.hunger = 0.4
	Input.action_press("eat_bread")
	p._physics_process(0.016)
	Input.action_release("eat_bread")
	_check(g.inv_bread == 0, "Q with pack open eats")
	root.remove_child(p)
	p.free()
	root.remove_child(ui)
	ui.free()


func _views() -> void:
	var ps := load("res://scenes/player.tscn") as PackedScene
	var p := ps.instantiate()
	root.add_child(p)
	_check(p.view_mode == 0, "boots in first person")
	p.cycle_view()
	_check(p.view_mode == 1 and p._cam3.current and p._body.visible, "chase cam + body")
	p.cycle_view()
	_check(p.view_mode == 2 and p._camf.current and p._body.visible, "front cam + body")
	p.cycle_view()
	_check(p.view_mode == 0 and p.camera.current and not p._body.visible, "cycles back to first")
	p._bob_phase = 1.0
	p._tick_body_anim(0.1, 5.6)
	_check(absf(p._thigh_l.rotation.x) > 0.2, "walk swing moves thighs")
	p._tick_body_anim(0.1, 0.0)
	_check(is_equal_approx(p._thigh_l.rotation.x, 0.0), "idle legs settle")
	root.remove_child(p)
	p.free()
