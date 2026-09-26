extends SceneTree
## Run with godot --headless --path backrooms --script res://tools/generation_test.gd
const MG = preload("res://scripts/maze_generator.gd")
const ANCHORS: Array[Vector2i] = [Vector2i(21, 89), Vector2i(95, 96), Vector2i(153, 96)]
const REGIONS: Array = [[Rect2i(93, 94, 7, 5), "lobby"], [Rect2i(20, 84, 11, 13), "west"], [Rect2i(88, 20, 15, 12), "service"], [Rect2i(144, 94, 8, 5), "server"], [Rect2i(152, 95, 3, 3), "server"], [Rect2i(92, 144, 8, 8), "dark"], [Rect2i(1, 1, 191, 191), "west"]]
const DISTRICTS: Array = [[Rect2i(88, 20, 15, 3), 1], [Rect2i(96, 22, 1, 10), 1], [Rect2i(144, 94, 8, 5), 2], [Rect2i(152, 95, 3, 3), 2], [Rect2i(1, 1, 191, 191), 0]]
var failures: int = 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func snapshot(m: MazeGenerator) -> Array:
	return [m.seed_used, m.grid.duplicate(), m.spawn_cell, m.exit_cell, m.spawn_yaw, m.pillar_cells.duplicate(), m.flicker_zones.duplicate(true), m.dark_zones.duplicate(true), m.prop_clusters.duplicate(true), m.humming_rooms.duplicate(true), m.fixture_state.duplicate(), m.fixture_phase.duplicate(), m.fixture_warmth.duplicate(), m.fixture_hanging.duplicate(), m.dist_map.duplicate(), m.region_rects.duplicate(true), m.district_rects.duplicate(true)]

func count_accents(m: MazeGenerator) -> Array:
	"""[west wall count, accent count, district-material violations]."""
	var west_w: int = 0
	var accents: int = 0
	var bad: int = 0
	for yy: int in MG.GRID_H:
		for xx: int in MG.GRID_W:
			if m.grid[yy * MG.GRID_W + xx] == 0:
				continue
			var wc := Vector2i(xx, yy)
			var r: String = m.region_of(wc)
			var mat: int = m.wall_mat_of(wc)
			if r == "west":
				west_w += 1
				if mat == 0:
					accents += 1
				elif mat != 1:
					bad += 1
			elif r == "service" and mat != 2:
				bad += 1
			elif (r == "server" or r == "machine") and mat != 3:
				bad += 1
			elif r == "lobby" and mat != 0:
				bad += 1
	return [west_w, accents, bad]


func flood(m: MazeGenerator) -> Dictionary:
	# Independent BFS: do not trust the generator's cached distance map.
	var reached: Dictionary = {m.spawn_cell: 0}
	var queue: Array[Vector2i] = [m.spawn_cell]
	var cursor: int = 0
	while cursor < queue.size():
		var c: Vector2i = queue[cursor]
		cursor += 1
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := c + d
			if n.x < 0 or n.y < 0 or n.x >= MG.GRID_W or n.y >= MG.GRID_H:
				continue
			if m.grid[n.y * MG.GRID_W + n.x] != 0 or reached.has(n):
				continue
			reached[n] = int(reached[c]) + 1
			queue.append(n)
	return reached

func wing_bytes(m: MazeGenerator, rect: Rect2i) -> PackedByteArray:
	var bytes := PackedByteArray()
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			bytes.append(m.grid[y * MG.GRID_W + x])
	return bytes

func _init() -> void:
	var seeds: Array[int] = [-2147483648, -5, -1, 999999, 2147483647, 4242, 424242]
	for s: int in 38:
		seeds.append(s)
	var regen_seeds: Dictionary = {}
	for s: int in seeds:
		if s < 0 or s > 99999 or s % 9 == 0:
			regen_seeds[s] = true
	var grids: Dictionary = {}
	var pillars: Dictionary = {}
	var props: Dictionary = {}
	var hums: Dictionary = {}
	var wings: Array[Dictionary] = [{}, {}, {}, {}]
	var wing_rects: Array[Rect2i] = [Rect2i(20, 84, 11, 13), Rect2i(88, 20, 15, 3), Rect2i(144, 94, 8, 5), Rect2i(92, 144, 8, 8)]
	var reused := MG.new()
	for s: int in seeds:
		var m := MG.new()
		check(m.generate_with_validation(s) == s, "seed retained %d" % s)
		check(m._validate(), "valid %d" % s)
		check(m.grid.size() == MG.GRID_W * MG.GRID_H and m.grid.count(0) + m.grid.count(1) == MG.GRID_W * MG.GRID_H, "binary dimensions %d" % s)
		check(m.spawn_cell == Vector2i(96, 98) and m.exit_cell == Vector2i(153, 96), "fixed endpoints %d" % s)
		check(m.region_rects == REGIONS and m.district_rects == DISTRICTS, "stable paint %d" % s)
		var reached := flood(m)
		for anchor: Vector2i in ANCHORS:
			check(m.grid[anchor.y * MG.GRID_W + anchor.x] == 0 and reached.has(anchor), "anchor %s seed %d" % [anchor, s])
		check(reached.size() == m.grid.count(0), "all floors reachable %d" % s)
		var bfs_bad: int = 0
		for c: Vector2i in reached:
			if m.dist_map[c.y * MG.GRID_W + c.x] != reached[c]:
				bfs_bad += 1
		check(bfs_bad == 0, "cached BFS %d" % s)
		for c: Vector2i in [Vector2i(147, 96), Vector2i(96, 148)]:
			check(m.grid[c.y * MG.GRID_W + c.x] == 0, "fixed server/dark floor %s seed %d" % [c, s])
		check(m.grid[96 * MG.GRID_W + 152] == 0 and m.grid[95 * MG.GRID_W + 152] == 1 and m.grid[97 * MG.GRID_W + 152] == 1, "exit doorway %d" % s)
		for i: int in MG.GRID_W:
			check(m.grid[i] == 1 and m.grid[(MG.GRID_H - 1) * MG.GRID_W + i] == 1 and m.grid[i * MG.GRID_W] == 1 and m.grid[i * MG.GRID_W + (MG.GRID_W - 1)] == 1, "sealed border %d" % s)
		check(m.pillar_cells.size() == 36, "district + hall pillars %d" % s)
		var seen_pillars: Dictionary = {}
		for c: Vector2i in m.pillar_cells:
			check(reached.has(c) and not seen_pillars.has(c) and not m._protected_cell(c), "safe pillar %d" % s)
			seen_pillars[c] = true
		check(m.prop_clusters.size() >= 6 and m.prop_clusters.size() <= 10 and m.humming_rooms.size() == 4, "zone counts %d" % s)
		for zones: Array in [m.prop_clusters, m.humming_rooms, m.dark_zones, m.flicker_zones]:
			for zone: Dictionary in zones:
				check(reached.has(zone.center) and zone.radius > 0, "reachable zone %d" % s)
		var fix_bad: int = 0
		for i: int in m.grid.size():
			if not (m.fixture_state[i] <= MG.F_DEAD and (m.grid[i] == 0 or m.fixture_state[i] == MG.F_NONE)):
				fix_bad += 1
		check(fix_bad == 0, "valid fixture %d" % s)
		var acc: Array = count_accents(m)
		check(acc[1] >= acc[0] * 8 / 100 and acc[1] <= acc[0] * 16 / 100, "wallpaper accent ratio %d" % s)
		check(acc[2] == 0, "district wall materials intact %d" % s)
		var before := snapshot(m)
		if regen_seeds.has(s):
			reused.generate_with_validation(s)
			check(before == snapshot(reused), "fresh/reused determinism %d" % s)
		var occupied := m.get_blocked()
		for c: Vector2i in m.pillar_cells:
			check(occupied[c.y * MG.GRID_W + c.x] == 1, "pillar excluded from navigation %d" % s)
		var navigation := GridAStar.new(MG.GRID_W, MG.GRID_H, occupied)
		for anchor: Vector2i in ANCHORS:
			check(not navigation.find_path(m.spawn_cell, anchor).is_empty(), "pillar-aware route %s seed %d" % [anchor, s])
		for attempt: int in 8:
			var spawn := m.random_entity_spawn()
			check(not m._protected_cell(spawn) and not m.pillar_cells.has(spawn), "entity spawn clear of objectives and pillars %d" % s)
		if regen_seeds.has(s):
			m.generate_with_validation(s)
			check(before == snapshot(m), "same-instance regeneration %d" % s)
			var acc2: Array = count_accents(m)
			check(acc2 == acc, "accent determinism %d" % s)
		grids[m.grid] = true
		pillars[str(m.pillar_cells)] = true
		props[str(m.prop_clusters)] = true
		hums[str(m.humming_rooms)] = true
		for i: int in wings.size():
			wings[i][wing_bytes(m, wing_rects[i])] = true
	check(grids.size() >= 40, "multi-seed topology diversity")
	check(pillars.size() >= 6 and props.size() >= 38 and hums.size() >= 18, "pillar/prop/humming diversity")
	for i: int in wings.size():
		check(wings[i].size() >= 3, "wing %d diversity" % i)
	print("GENERATION: %d seeds, %d grids; wing variants %s; pillars %d, props %d, humming %d" % [seeds.size(), grids.size(), [wings[0].size(), wings[1].size(), wings[2].size(), wings[3].size()], pillars.size(), props.size(), hums.size()])
	_levels()
	# Validation must reject blocked anchors, disconnected anchors, and sealed spawn.
	var lv0 := MG.new()
	lv0.generate_with_validation(42)
	for anchor: Vector2i in lv0.key_cells:
		var broken := MG.new()
		broken.generate_with_validation(42)
		broken.grid[anchor.y * MG.GRID_W + anchor.x] = 1
		check(not broken._validate(), "reject blocked anchor %s" % anchor)
	var isolated := MG.new()
	isolated.generate_with_validation(42)
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var c := Vector2i(21, 89) + d
		isolated.grid[c.y * MG.GRID_W + c.x] = 1
	check(not isolated._validate(), "reject disconnected anchor despite stale cached distances")
	print("GENERATION TEST: ALL PASS" if failures == 0 else "GENERATION TEST: %d FAILURES" % failures)
	quit(0 if failures == 0 else 1)


func _levels() -> void:
	# Deeper levels: same contract (valid, connected, deterministic), own keys.
	var CampaignScript: Script = load("res://scripts/campaign.gd")
	for id: int in 4:
		check(CampaignScript.CELLS[id] == MG.station_cell_global(id), "campaign/maze station cell %d agree" % id)
		check(CampaignScript.STATION_LEVEL[id] == MG.station_level(id), "campaign/maze station level %d agree" % id)
	for lv: int in [1, 2]:
		for s: int in [0, 42, 1234, 424242, 31337]:
			var m := MG.new()
			m.level_index = lv
			check(m.generate_with_validation(s) == s, "L%d seed retained %d" % [lv, s])
			check(m._validate(), "L%d valid %d" % [lv, s])
			var reached := flood(m)
			for k: Vector2i in m.key_cells:
				check(m.grid[k.y * MG.GRID_W + k.x] == 0 and reached.has(k), "L%d key %s seed %d" % [lv, k, s])
			check(reached.size() == m.grid.count(0), "L%d all floors reachable %d" % [lv, s])
			for i: int in MG.GRID_W:
				check(m.grid[i] == 1 and m.grid[(MG.GRID_H - 1) * MG.GRID_W + i] == 1 and m.grid[i * MG.GRID_W] == 1 and m.grid[i * MG.GRID_W + (MG.GRID_W - 1)] == 1, "L%d sealed border %d" % [lv, s])
			check(m.pillar_cells.size() == (54 if lv == 1 else 30), "L%d district + hall pillars %d" % [lv, s])
			for c: Vector2i in m.pillar_cells:
				check(reached.has(c) and not m._protected_cell(c), "L%d safe pillar %d" % [lv, s])
			check(m.humming_rooms.size() == 4 and m.dark_zones.size() == 3, "L%d zone counts %d" % [lv, s])
			var lfix_bad: int = 0
			for i: int in m.grid.size():
				if not (m.fixture_state[i] <= MG.F_DEAD and (m.grid[i] == 0 or m.fixture_state[i] == MG.F_NONE)):
					lfix_bad += 1
			check(lfix_bad == 0, "L%d valid fixture %d" % [lv, s])
			var other := MG.new()
			other.level_index = lv
			other.generate_with_validation(s)
			check(snapshot(m) == snapshot(other), "L%d determinism %d" % [lv, s])
			for attempt: int in 4:
				var spawn := m.random_entity_spawn()
				check(not m._protected_cell(spawn) and not m.pillar_cells.has(spawn) and reached.has(spawn), "L%d entity spawn clear %d" % [lv, s])
