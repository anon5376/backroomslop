class_name MazeGenerator
extends RefCounted
## Authored backrooms wings with seeded, connectivity-preserving micro-variations.
## Owns the grid, zones, fixtures, and world building. Same seed = same maze.

const GRID_W: int = 193
const GRID_H: int = 193
const GRID_C: int = GRID_W / 2  # center cell offset; world origin sits here
const CELL: float = 3.0
const WALL_H: float = 2.7
const MAX_ATTEMPTS: int = 25
const LEVEL_COUNT: int = 3
const FINAL_LEVEL: int = 2
const LEVEL_NAMES: Array[String] = ["LEVEL 0 · THE LOBBY", "LEVEL 1 · CONCRETE HALLS", "LEVEL 2 · PIPE DREAMS"]
const SPAWN := Vector2i(96, 98)
const EXIT := Vector2i(153, 96)
const CAMPAIGN_ANCHORS: Array[Vector2i] = [
	Vector2i(21, 89), Vector2i(33, 12), Vector2i(40, 30), Vector2i(95, 96),
]
# Deeper key cells. Station ids live on fixed levels: 0+3 on L0, 1 on L1, 2 on L2.
const SPAWN_1 := Vector2i(96, 96)
const EXIT_1 := Vector2i(149, 95)  # stairwell down
const STATION_1 := Vector2i(96, 21)
const SPAWN_2 := Vector2i(96, 96)
const EXIT_2 := Vector2i(147, 96)  # the one real exit
const STATION_2 := Vector2i(96, 21)
# Margin-note scraps. Each is provably floor under every wall variant:
# room centers, open corridors, or the stamped break room / archive.
const SCRAP_CELLS: Array[Vector2i] = [
	Vector2i(32, 91), Vector2i(92, 18), Vector2i(25, 85),
	Vector2i(92, 20), Vector2i(93, 96), Vector2i(146, 96),
]
const BREAK_ROOM := Rect2i(31, 90, 4, 4)  # off the west south corridor
const ARCHIVE_ROOM := Rect2i(90, 17, 6, 3)  # off the service north row

const F_NONE: int = 0
const F_STEADY: int = 1
const F_FLICKER: int = 2
const F_DEAD: int = 3

var rng := RandomNumberGenerator.new()
var seed_used: int = 0
var level_index: int = 0  # set before generate_with_validation
var grid := PackedByteArray()  # 0 floor, 1 wall. Index y * GRID_W + x.
var spawn_cell := Vector2i.ZERO
var exit_cell := Vector2i.ZERO
var key_cells: Array[Vector2i] = []  # spawn + stairs/exit + this level's stations
var spawn_yaw: float = 0.0
var _gen_spawn := Vector2i.ZERO  # connectivity root while stamping
var flicker_zones: Array[Dictionary] = []
var dark_zones: Array[Dictionary] = []
var prop_clusters: Array[Dictionary] = []
var humming_rooms: Array[Dictionary] = []
var district_rects: Array = []  # [Rect2i, district] paint, first match wins
var region_rects: Array = []  # [Rect2i, region name] paint, first match wins
var fixture_state := PackedByteArray()  # per cell: F_NONE/F_STEADY/F_FLICKER/F_DEAD
var fixture_phase := PackedFloat32Array()
var fixture_warmth := PackedFloat32Array()
var fixture_hanging := PackedByteArray()
var pillar_cells: Array[Vector2i] = []
var dist_map := PackedInt32Array()  # BFS distance from spawn, -1 = unreachable
var exit_world_pos := Vector3.ZERO
var backbone_segs: Array = []  # L2 pipe runs: {a: Vector2i, b: Vector2i} cell runs


func generate_with_validation(base_seed: int) -> int:
	"""Run full generation, bumping the seed until validation passes."""
	for attempt: int in MAX_ATTEMPTS:
		var s: int = base_seed + attempt
		_generate(s)
		if _validate():
			seed_used = s
			return s
	push_error("MazeGenerator: failed validation after %d attempts" % MAX_ATTEMPTS)
	return -1


func get_blocked() -> PackedByteArray:
	var blocked: PackedByteArray = grid.duplicate()
	# Grid paths travel through cell centres; pillar colliders occupy those centres.
	for cell: Vector2i in pillar_cells:
		blocked[cell.y * GRID_W + cell.x] = 1
	return blocked


func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((float(cell.x) - float(GRID_C)) * CELL, 0.0, (float(cell.y) - float(GRID_C)) * CELL)


func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(int(round(pos.x / CELL)) + GRID_C, int(round(pos.z / CELL)) + GRID_C)


func district_of(cell: Vector2i) -> int:
	# 0 = yellow halls, 1 = concrete service, 2 = server farm.
	for entry: Array in district_rects:
		if (entry[0] as Rect2i).has_point(cell):
			return int(entry[1])
	return 0


func region_of(cell: Vector2i) -> String:
	for entry: Array in region_rects:
		if (entry[0] as Rect2i).has_point(cell):
			return String(entry[1])
	return "west"


func wall_mat_of(cell: Vector2i) -> int:
	# 0 = wallpaper A (lobby), 1 = wallpaper B (west + dark), 2 = concrete, 3 = server.
	var r: String = region_of(cell)
	if r == "service":
		return 2
	if r == "server" or r == "machine":
		return 3
	if r == "lobby":
		return 0
	return 1


static func station_level(id: int) -> int:
	return [0, 1, 2, 0][clampi(id, 0, 3)]


static func station_cell_global(id: int) -> Vector2i:
	match clampi(id, 0, 3):
		0:
			return CAMPAIGN_ANCHORS[0]
		1:
			return STATION_1
		2:
			return STATION_2
	return CAMPAIGN_ANCHORS[3]


func level_station_ids() -> Array[int]:
	# Stations with wayfinding on this level (briefing 3 excluded everywhere).
	var out: Array[int] = []
	out.append(clampi(level_index, 0, FINAL_LEVEL))
	return out


func _level_spawn() -> Vector2i:
	return [SPAWN, SPAWN_1, SPAWN_2][clampi(level_index, 0, FINAL_LEVEL)]


func _level_exit() -> Vector2i:
	return [EXIT, EXIT_1, EXIT_2][clampi(level_index, 0, FINAL_LEVEL)]


func _generate(seed_value: int) -> void:
	rng.seed = seed_value
	seed_used = seed_value
	level_index = clampi(level_index, 0, FINAL_LEVEL)
	grid.clear()
	grid.resize(GRID_W * GRID_H)
	grid.fill(1)
	pillar_cells.clear()
	flicker_zones.clear()
	prop_clusters.clear()
	district_rects.clear()
	region_rects.clear()
	key_cells.clear()
	# STEP 1 — authored map: stamp floors, room walls, pillars, paint.
	if level_index == 0:
		key_cells = [SPAWN, EXIT, CAMPAIGN_ANCHORS[0], CAMPAIGN_ANCHORS[3]]
		_gen_spawn = SPAWN
		_stamp_authored()
	elif level_index == 1:
		key_cells = [SPAWN_1, EXIT_1, STATION_1]
		_gen_spawn = SPAWN_1
		_stamp_level1()
	else:
		key_cells = [SPAWN_2, EXIT_2, STATION_2]
		_gen_spawn = SPAWN_2
		_stamp_level2()
	backbone_segs.clear()
	_fill_maze()
	# STEP 6 — zones.
	_place_zones()
	# STEP 7 — fixtures.
	_place_fixtures()
	spawn_yaw = 0.0  # face north into the hall


func _floor_rect(r: Rect2i) -> void:
	for yy: int in range(r.position.y, r.position.y + r.size.y):
		for xx: int in range(r.position.x, r.position.x + r.size.x):
			grid[yy * GRID_W + xx] = 0


func _room_doors(x0: int, z0: int) -> void:
	# Rotate/mirror an asymmetric doorway stamp, then keep only safe walls.
	# The centre remains floor; doors may be centred, offset or double-width.
	var variants: Array = [
		[Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 2)],
		[Vector2i(0, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(0, 2)],
	]
	_stamp_variant(Vector2i(x0, z0), 3, variants[rng.randi_range(0, variants.size() - 1)])


func _protected_cell(cell: Vector2i) -> bool:
	# Leave station approaches clear as well as the campaign cells themselves.
	for anchor: Vector2i in key_cells:
		if _manhattan(cell, anchor) <= 1:
			return true
	return false


func _try_wall(cell: Vector2i) -> void:
	if _protected_cell(cell) or _is_wall(cell.x, cell.y) or pillar_cells.has(cell):
		return
	# Fixed rack footprints and the east-west server aisle stay clear.
	if level_index == 0 and (Rect2i(145, 95, 5, 4).has_point(cell) or cell == Vector2i(96, 148)):
		return
	# Districts stamp as islands (filler joins them later), so only forbid
	# walls that shrink whatever is already reachable from spawn.
	var before := _bfs_distances(_gen_spawn)
	_set_wall(cell.x, cell.y)
	var distances := _bfs_distances(_gen_spawn)
	for i: int in grid.size():
		if grid[i] == 0 and before[i] >= 0 and distances[i] < 0:
			# Reject articulation points and enclosed pockets, not the seed.
			grid[cell.y * GRID_W + cell.x] = 0
			return


func _stamp_variant(origin: Vector2i, size: int, walls: Array) -> void:
	var turns: int = rng.randi_range(0, 3)
	var mirror: bool = rng.randi_range(0, 1) == 1
	for offset: Vector2i in walls:
		var cell: Vector2i = offset
		if mirror:
			cell.x = size - 1 - cell.x
		for turn: int in turns:
			cell = Vector2i(size - 1 - cell.y, cell.x)
		_try_wall(origin + cell)


func _stamp_authored() -> void:
	# Same five districts, spread across the big grid; maze filler joins them.
	# Central lobby + links.
	_floor_rect(Rect2i(93, 94, 7, 5))
	_floor_rect(Rect2i(96, 90, 1, 4))
	_floor_rect(Rect2i(96, 99, 1, 1))
	# West wing: 3x3 rooms + corridors.
	for cx: int in [20, 24, 28]:
		for cz: int in [84, 88, 92]:
			_floor_rect(Rect2i(cx, cz, 3, 3))
	_floor_rect(Rect2i(23, 84, 1, 13))
	_floor_rect(Rect2i(27, 84, 1, 13))
	_floor_rect(Rect2i(20, 87, 11, 1))
	_floor_rect(Rect2i(20, 91, 11, 1))
	_floor_rect(Rect2i(20, 96, 15, 1))
	# Service wing: twin corridors + cross-links + link south.
	_floor_rect(Rect2i(88, 20, 15, 1))
	_floor_rect(Rect2i(88, 22, 15, 1))
	for lx: int in [91, 95, 99]:
		_floor_rect(Rect2i(lx, 20, 1, 3))
	_floor_rect(Rect2i(96, 22, 1, 10))
	# Server hall + exit room (door gap at (152, 96)).
	_floor_rect(Rect2i(144, 94, 8, 5))
	_floor_rect(Rect2i(152, 95, 3, 3))
	_set_wall(152, 95)
	_set_wall(152, 97)
	# Dark pocket: transformed interior stubs. Ring stays open.
	_floor_rect(Rect2i(92, 144, 8, 8))
	var dark_walls: Array[Vector2i] = []
	for zz: int in [35, 36, 37]:
		dark_walls.append(Vector2i(29, zz))
	for zz: int in [38, 39, 40]:
		dark_walls.append(Vector2i(31, zz))
	for xx: int in [27, 28]:
		dark_walls.append(Vector2i(xx, 37))
	for xx: int in [31, 32]:
		dark_walls.append(Vector2i(xx, 38))
	for xx: int in [30, 31, 32]:
		dark_walls.append(Vector2i(xx, 36))
	for zz: int in [39, 40]:
		dark_walls.append(Vector2i(28, zz))
	var local_walls: Array[Vector2i] = []
	for wcell: Vector2i in dark_walls:
		local_walls.append(wcell - Vector2i(26, 34))
	_stamp_variant(Vector2i(92, 144), 8, local_walls)
	# Break room + archive: furnished set-piece rooms on open edges.
	_floor_rect(BREAK_ROOM)
	_floor_rect(ARCHIVE_ROOM)
	# Apply room walls only after all wings and their links are connected.
	for cx: int in [20, 24, 28]:
		for cz: int in [84, 88, 92]:
			_room_doors(cx, cz)
	# Service cross-links become offset paired doors or small alcoves.
	for cx: int in [89, 93, 97, 100]:
		_floor_rect(Rect2i(cx + rng.randi_range(0, 1), 21, 1, 1))
		_stamp_variant(Vector2i(cx, 20), 3, [Vector2i(0, 1)])
	# Server baffles occupy only the top/bottom fringe, not rack rows or the spine.
	for cx: int in [145, 148]:
		_stamp_variant(Vector2i(cx, 94), 3, [Vector2i(0, 0)])
	# Shallow west alcoves open off the permanent southern corridor.
	for cx: int in [21, 25, 29]:
		_floor_rect(Rect2i(cx + rng.randi_range(-1, 1), 95, rng.randi_range(1, 2), 1))
	# Jitter each lobby pillar row outward; never occupy a station approach.
	for row: int in [95, 97]:
		for column: int in [94, 98]:
			var pc := Vector2i(column + rng.randi_range(-1, 1), row)
			if _protected_cell(pc):
				pc = Vector2i(93 if column == 94 else 99, row)
			pillar_cells.append(pc)
	district_rects = [
		[Rect2i(88, 20, 15, 3), 1],
		[Rect2i(96, 22, 1, 10), 1],
		[Rect2i(144, 94, 8, 5), 2],
		[Rect2i(152, 95, 3, 3), 2],
		[Rect2i(1, 1, 191, 191), 0],
	]
	region_rects = [
		[Rect2i(93, 94, 7, 5), "lobby"],
		[Rect2i(20, 84, 11, 13), "west"],
		[Rect2i(88, 20, 15, 12), "service"],
		[Rect2i(144, 94, 8, 5), "server"],
		[Rect2i(152, 95, 3, 3), "server"],
		[Rect2i(92, 144, 8, 8), "dark"],
		[Rect2i(1, 1, 191, 191), "west"],
	]


func _stamp_level1() -> void:
	# Concrete halls: same five blocks, spread; corridor-grid maze joins them.
	_floor_rect(Rect2i(92, 94, 9, 5))
	_floor_rect(Rect2i(96, 24, 1, 10))
	_floor_rect(Rect2i(90, 20, 12, 4))
	_floor_rect(Rect2i(143, 96, 8, 1))
	_floor_rect(Rect2i(146, 93, 7, 6))
	_floor_rect(Rect2i(24, 96, 8, 1))
	_floor_rect(Rect2i(20, 94, 5, 5))
	_floor_rect(Rect2i(96, 141, 1, 6))
	_floor_rect(Rect2i(92, 147, 9, 4))
	for pc: Vector2i in [Vector2i(94, 95), Vector2i(98, 95), Vector2i(94, 97), Vector2i(98, 97), Vector2i(94, 148), Vector2i(98, 148)]:
		pillar_cells.append(pc)
	_scatter_baffles(20)
	district_rects = [[Rect2i(1, 1, 191, 191), 1]]
	region_rects = [[Rect2i(1, 1, 191, 191), "service"]]


func _stamp_level2() -> void:
	# Pipe dreams: same five halls, spread; machine maze + pipe backbones join them.
	_floor_rect(Rect2i(93, 93, 7, 7))
	_floor_rect(Rect2i(92, 20, 9, 4))
	_floor_rect(Rect2i(144, 93, 7, 7))
	_floor_rect(Rect2i(20, 93, 7, 7))
	_floor_rect(Rect2i(92, 147, 9, 4))
	for pc: Vector2i in [Vector2i(94, 94), Vector2i(98, 94), Vector2i(94, 98), Vector2i(98, 98), Vector2i(94, 21), Vector2i(98, 21)]:
		pillar_cells.append(pc)
	_scatter_baffles(25)
	district_rects = [[Rect2i(1, 1, 191, 191), 2]]
	region_rects = [[Rect2i(1, 1, 191, 191), "machine"]]


func _scatter_baffles(count: int) -> void:
	# Connectivity-safe texture: _try_wall rejects articulation points.
	for i: int in count:
		_try_wall(_random_floor_cell())


func _district_skip() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var rects: Array = []
	if level_index == 0:
		rects = [Rect2i(93, 90, 7, 10), Rect2i(20, 84, 15, 13), Rect2i(88, 17, 15, 15), Rect2i(144, 94, 11, 5), Rect2i(92, 144, 8, 8)]
	elif level_index == 1:
		rects = [Rect2i(92, 94, 9, 5), Rect2i(90, 20, 12, 14), Rect2i(143, 93, 10, 6), Rect2i(20, 94, 12, 5), Rect2i(92, 141, 9, 10)]
	else:
		rects = [Rect2i(93, 93, 7, 7), Rect2i(92, 20, 9, 4), Rect2i(144, 93, 7, 7), Rect2i(20, 93, 7, 7), Rect2i(92, 147, 9, 4)]
	for r: Rect2i in rects:
		out.append(r)
	return out


func _district_doors() -> Array:
	# [edge wall cell adjacent to district floor, outward dig direction].
	if level_index == 0:
		return [
			[Vector2i(96, 89), Vector2i(0, -1)], [Vector2i(96, 100), Vector2i(0, 1)],
			[Vector2i(92, 96), Vector2i(-1, 0)], [Vector2i(100, 96), Vector2i(1, 0)],
			[Vector2i(19, 89), Vector2i(-1, 0)], [Vector2i(19, 96), Vector2i(-1, 0)],
			[Vector2i(27, 83), Vector2i(0, -1)], [Vector2i(27, 97), Vector2i(0, 1)],
			[Vector2i(87, 20), Vector2i(-1, 0)], [Vector2i(103, 20), Vector2i(1, 0)],
			[Vector2i(92, 16), Vector2i(0, -1)], [Vector2i(97, 31), Vector2i(1, 0)],
			[Vector2i(143, 96), Vector2i(-1, 0)], [Vector2i(147, 93), Vector2i(0, -1)],
			[Vector2i(147, 99), Vector2i(0, 1)],
			[Vector2i(91, 147), Vector2i(-1, 0)], [Vector2i(100, 147), Vector2i(1, 0)],
			[Vector2i(96, 143), Vector2i(0, -1)], [Vector2i(96, 152), Vector2i(0, 1)],
		]
	if level_index == 1:
		return [
			[Vector2i(96, 93), Vector2i(0, -1)], [Vector2i(96, 99), Vector2i(0, 1)],
			[Vector2i(91, 96), Vector2i(-1, 0)], [Vector2i(101, 96), Vector2i(1, 0)],
			[Vector2i(96, 34), Vector2i(0, 1)], [Vector2i(96, 19), Vector2i(0, -1)],
			[Vector2i(89, 21), Vector2i(-1, 0)], [Vector2i(102, 21), Vector2i(1, 0)],
			[Vector2i(142, 96), Vector2i(-1, 0)], [Vector2i(153, 95), Vector2i(1, 0)],
			[Vector2i(149, 92), Vector2i(0, -1)], [Vector2i(149, 99), Vector2i(0, 1)],
			[Vector2i(32, 96), Vector2i(1, 0)], [Vector2i(19, 96), Vector2i(-1, 0)],
			[Vector2i(22, 93), Vector2i(0, -1)], [Vector2i(22, 99), Vector2i(0, 1)],
			[Vector2i(96, 140), Vector2i(0, -1)], [Vector2i(96, 151), Vector2i(0, 1)],
			[Vector2i(91, 148), Vector2i(-1, 0)], [Vector2i(101, 148), Vector2i(1, 0)],
		]
	return [
		[Vector2i(96, 92), Vector2i(0, -1)], [Vector2i(96, 100), Vector2i(0, 1)],
		[Vector2i(92, 96), Vector2i(-1, 0)], [Vector2i(100, 96), Vector2i(1, 0)],
		[Vector2i(96, 24), Vector2i(0, 1)], [Vector2i(96, 19), Vector2i(0, -1)],
		[Vector2i(91, 21), Vector2i(-1, 0)], [Vector2i(101, 21), Vector2i(1, 0)],
		[Vector2i(143, 96), Vector2i(-1, 0)], [Vector2i(151, 96), Vector2i(1, 0)],
		[Vector2i(147, 92), Vector2i(0, -1)], [Vector2i(147, 99), Vector2i(0, 1)],
		[Vector2i(27, 96), Vector2i(1, 0)], [Vector2i(19, 96), Vector2i(-1, 0)],
		[Vector2i(23, 92), Vector2i(0, -1)], [Vector2i(23, 99), Vector2i(0, 1)],
		[Vector2i(96, 146), Vector2i(0, -1)], [Vector2i(96, 151), Vector2i(0, 1)],
		[Vector2i(91, 148), Vector2i(-1, 0)], [Vector2i(101, 148), Vector2i(1, 0)],
	]


func _in_skip(cell: Vector2i, skip: Array[Rect2i]) -> bool:
	for r: Rect2i in skip:
		if r.has_point(cell):
			return true
	return false


func _fill_maze() -> void:
	# Open floor everywhere except districts (their interior walls survive),
	# then recursive-division partitions (the original backrooms look),
	# halls, district doors, L2 pipe backbones, and a connectivity repair.
	var skip := _district_skip()
	for y: int in range(1, GRID_H - 1):
		for x: int in range(1, GRID_W - 1):
			if not _in_skip(Vector2i(x, y), skip):
				grid[y * GRID_W + x] = 0
	var halls: Array[Rect2i] = []
	if level_index == 0:
		halls = _stamp_halls(skip, 8, 5, 9)
	elif level_index == 1:
		halls = _stamp_halls(skip, 12, 6, 10)
	else:
		halls = _stamp_halls(skip, 6, 4, 6)
	var wall_skip: Array[Rect2i] = skip.duplicate()
	for h: Rect2i in halls:
		wall_skip.append(h)
	if level_index == 0:
		_scatter_partitions(wall_skip, 500, 3, 10, 40, 15, 40, 2)
	elif level_index == 1:
		_scatter_partitions(wall_skip, 350, 4, 12, 50, 20, 50, 2)
	else:
		_scatter_partitions(wall_skip, 450, 3, 8, 30, 12, 30, 1)
	for h: Rect2i in halls:
		_hall_pillars(h)
	for d: Array in _district_doors():
		_punch_door(d[0], d[1])
	if level_index == 2:
		_carve_backbone(Vector2i(96, 91), Vector2i(96, 25), skip)
		_carve_backbone(Vector2i(96, 101), Vector2i(96, 145), skip)
		_carve_backbone(Vector2i(101, 96), Vector2i(142, 96), skip)
		_carve_backbone(Vector2i(91, 96), Vector2i(28, 96), skip)
	_repair_connectivity()


func _repair_connectivity() -> void:
	# Division gaps can seal when child walls abut both sides. Tunnel each
	# cut-off pocket back to the spawn net; validation then always passes.
	var guard: int = 0
	while guard < 40:
		guard += 1
		var dist := _bfs_distances(_gen_spawn)
		var target := Vector2i(-1, -1)
		for y: int in range(1, GRID_H - 1):
			for x: int in range(1, GRID_W - 1):
				if grid[y * GRID_W + x] == 0 and dist[y * GRID_W + x] < 0:
					target = Vector2i(x, y)
					break
			if target.x >= 0:
				break
		if target.x < 0:
			return
		var p := target
		var steps: int = 0
		while steps < 400:
			steps += 1
			grid[p.y * GRID_W + p.x] = 0
			var done: bool = false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = p + d
				if grid[n.y * GRID_W + n.x] == 0 and dist[n.y * GRID_W + n.x] >= 0:
					done = true
					break
			if done:
				break
			var dx: int = _gen_spawn.x - p.x
			var dy: int = _gen_spawn.y - p.y
			if abs(dx) >= abs(dy):
				p.x += _signi(dx)
			else:
				p.y += _signi(dy)
			p.x = clampi(p.x, 1, GRID_W - 2)
			p.y = clampi(p.y, 1, GRID_H - 2)


func _signi(v: int) -> int:
	return 1 if v > 0 else (-1 if v < 0 else 0)


func _stamp_halls(skip: Array[Rect2i], count: int, lo: int, hi: int) -> Array[Rect2i]:
	var halls: Array[Rect2i] = []
	var guard: int = 0
	while halls.size() < count and guard < count * 80:
		guard += 1
		var w: int = rng.randi_range(lo, hi)
		var h: int = rng.randi_range(lo, hi)
		var r := Rect2i(rng.randi_range(3, GRID_W - 4 - w), rng.randi_range(3, GRID_H - 4 - h), w, h)
		var bad: bool = false
		for s: Rect2i in skip:
			if r.intersects(s.grow(2)):
				bad = true
				break
		if not bad:
			for hh: Rect2i in halls:
				if r.intersects(hh.grow(1)):
					bad = true
					break
		if bad:
			continue
		halls.append(r)
	return halls


func _hall_pillars(h: Rect2i) -> void:
	# Inset pillars in open halls: never adjacent to a wall, never sealing.
	var spots: Array[Vector2i] = [
		Vector2i(h.position.x + 1, h.position.y + 1),
		Vector2i(h.end.x - 2, h.position.y + 1),
		Vector2i(h.position.x + 1, h.end.y - 2),
		Vector2i(h.end.x - 2, h.end.y - 2),
	]
	for c: Vector2i in spots:
		if not _protected_cell(c) and not pillar_cells.has(c):
			pillar_cells.append(c)


func _scatter_partitions(skip: Array[Rect2i], stubs: int, stub_lo: int, stub_hi: int, longs: int, long_lo: int, long_hi: int, long_gaps: int) -> void:
	# Free partitions, not a grid: short stubs for texture, long walls with
	# gaps for structure. The repair pass guarantees connectivity after.
	for i: int in stubs:
		_partition_seg(skip, rng.randi_range(stub_lo, stub_hi), 0)
	for i: int in longs:
		_partition_seg(skip, rng.randi_range(long_lo, long_hi), long_gaps)


func _partition_seg(skip: Array[Rect2i], length: int, gaps: int) -> void:
	var horiz: bool = rng.randi_range(0, 1) == 0
	if horiz:
		var y: int = rng.randi_range(2, GRID_H - 3)
		var x: int = rng.randi_range(2, GRID_W - 2 - length)
		var gap_at: Array[int] = []
		for i: int in gaps:
			gap_at.append(rng.randi_range(x, x + length - 1))
		for xx: int in range(x, x + length):
			if gap_at.has(xx):
				continue
			var c := Vector2i(xx, y)
			if _in_skip(c, skip) or _protected_cell(c):
				continue
			_set_wall(xx, y)
	else:
		var wx: int = rng.randi_range(2, GRID_W - 3)
		var wy: int = rng.randi_range(2, GRID_H - 2 - length)
		var gap_at_v: Array[int] = []
		for i: int in gaps:
			gap_at_v.append(rng.randi_range(wy, wy + length - 1))
		for yy: int in range(wy, wy + length):
			if gap_at_v.has(yy):
				continue
			var c2 := Vector2i(wx, yy)
			if _in_skip(c2, skip) or _protected_cell(c2):
				continue
			_set_wall(wx, yy)


func _punch_door(edge: Vector2i, dir: Vector2i) -> void:
	# District edges can carry pattern walls (room doors, dark stubs), so try
	# the edge plus lateral offsets until the inward cell is district floor.
	var perp := Vector2i(-dir.y, dir.x)
	var cands: Array[Vector2i] = [edge]
	for k: int in [1, -1, 2, -2]:
		cands.append(edge + perp * k)
	for c: Vector2i in cands:
		if c.x < 1 or c.y < 1 or c.x >= GRID_W - 1 or c.y >= GRID_H - 1:
			continue
		if pillar_cells.has(c):
			continue
		if _is_wall((c - dir).x, (c - dir).y):
			continue
		_punch_walk(c, dir)
		return


func _punch_walk(cell: Vector2i, dir: Vector2i) -> void:
	# Floor outward until the walk touches existing floor (12 cells max).
	var p := cell
	for i: int in 12:
		if p.x < 1 or p.y < 1 or p.x >= GRID_W - 1 or p.y >= GRID_H - 1:
			return
		grid[p.y * GRID_W + p.x] = 0
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if n != p - dir and grid[n.y * GRID_W + n.x] == 0:
				return
		p += dir


func _carve_backbone(a: Vector2i, b: Vector2i, skip: Array[Rect2i]) -> void:
	# Winding 2-wide pipe tunnel; never straight for long. Records pipe runs.
	var p := a
	var guard: int = 0
	while p != b and guard < 300:
		guard += 1
		var dx: int = b.x - p.x
		var dy: int = b.y - p.y
		var go_h: bool = dx != 0 and (dy == 0 or rng.randf() < 0.5)
		if dx == 0 and rng.randf() < 0.6:
			go_h = true  # forced jog: no straight corridors
			dx = rng.randi_range(6, 14) * (1 if rng.randf() < 0.5 else -1)
		elif dy == 0 and rng.randf() < 0.6:
			go_h = false
			dy = rng.randi_range(6, 14) * (1 if rng.randf() < 0.5 else -1)
		var n: Vector2i = p
		if go_h and dx != 0:
			var step: int = clampi(dx, -14, 14)
			n = Vector2i(clampi(p.x + step, 2, GRID_W - 3), p.y)
		elif not go_h and dy != 0:
			var step2: int = clampi(dy, -14, 14)
			n = Vector2i(p.x, clampi(p.y + step2, 2, GRID_H - 3))
		else:
			continue
		if n == p:
			continue
		_floor_thick(p, n, skip)
		backbone_segs.append({"a": p, "b": n})
		p = n


func _floor_thick(a: Vector2i, b: Vector2i, skip: Array[Rect2i]) -> void:
	var lo_x: int = mini(a.x, b.x)
	var hi_x: int = maxi(a.x, b.x)
	var lo_y: int = mini(a.y, b.y)
	var hi_y: int = maxi(a.y, b.y)
	for x: int in range(lo_x, hi_x + 1):
		for y: int in range(lo_y, hi_y + 1):
			for off: int in 2:
				var c := Vector2i(x, y + off) if hi_y == lo_y else Vector2i(x + off, y)
				if c.x < 1 or c.y < 1 or c.x >= GRID_W - 1 or c.y >= GRID_H - 1:
					continue
				if _in_skip(c, skip):
					continue
				grid[c.y * GRID_W + c.x] = 0


func _set_wall(x: int, y: int) -> void:
	grid[y * GRID_W + x] = 1


func _is_wall(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= GRID_W or y >= GRID_H:
		return true
	return grid[y * GRID_W + x] == 1


func _floor_neighbors(x: int, y: int) -> int:
	var n: int = 0
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not _is_wall(x + d.x, y + d.y):
			n += 1
	return n


func _random_floor_cell() -> Vector2i:
	while true:
		var c := Vector2i(rng.randi_range(1, GRID_W - 2), rng.randi_range(1, GRID_H - 2))
		if not _is_wall(c.x, c.y):
			return c
	return Vector2i(GRID_C, GRID_C)  # unreachable, keeps the type checker calm


func _bfs_distances(from: Vector2i) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(GRID_W * GRID_H)
	dist.fill(-1)
	dist[from.y * GRID_W + from.x] = 0
	var queue: Array[Vector2i] = [from]
	var head: int = 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var cd: int = dist[c.y * GRID_W + c.x]
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= GRID_W or n.y >= GRID_H:
				continue
			if _is_wall(n.x, n.y):
				continue
			if dist[n.y * GRID_W + n.x] != -1:
				continue
			dist[n.y * GRID_W + n.x] = cd + 1
			queue.append(n)
	return dist


func _place_zones() -> void:
	# Authored map: fixed spawn and stairs/exit per level.
	var guard: int = 0
	spawn_cell = _level_spawn()
	dist_map = _bfs_distances(spawn_cell)
	exit_cell = _level_exit()
	# Flicker zones: eight, spread so the maze never sits uniform.
	flicker_zones.clear()
	guard = 0
	while flicker_zones.size() < 8 and guard < 6000:
		guard += 1
		var c := _random_floor_cell()
		if _manhattan(c, spawn_cell) >= 40 and _zone_spread_ok(c, flicker_zones, 40):
			flicker_zones.append({"center": c, "radius": 8})
	# Three dark zones: a big one far away, two smaller nasty pockets.
	dark_zones.clear()
	guard = 0
	while dark_zones.size() < 3 and guard < 8000:
		guard += 1
		var c := _random_floor_cell()
		var want_r: int = [14, 9, 9][dark_zones.size()]
		var want_d: int = [70, 50, 50][dark_zones.size()]
		if _manhattan(c, spawn_cell) >= want_d and _zone_spread_ok(c, dark_zones, 50):
			dark_zones.append({"center": c, "radius": want_r})
	# Distinct, roomy prop pockets; avoid placing furniture on campaign stations.
	prop_clusters.clear()
	var candidates: Array[Vector2i] = []
	for y: int in GRID_H:
		for x: int in GRID_W:
			var c := Vector2i(x, y)
			if not _is_wall(x, y) and not _protected_cell(c) and _floor_neighbors(x, y) >= 3:
				candidates.append(c)
	for i: int in rng.randi_range(6, 10):
		var index: int = rng.randi_range(0, candidates.size() - 1)
		prop_clusters.append({"center": candidates[index], "radius": rng.randi_range(5, 8)})
		candidates.remove_at(index)
	# Two actual west rooms, sampled without replacement, with varying light reach.
	humming_rooms.clear()
	if level_index == 0:
		var rooms: Array[Vector2i] = []
		for x: int in [21, 25, 29]:
			for y: int in [85, 89, 93]:
				if not _protected_cell(Vector2i(x, y)):
					rooms.append(Vector2i(x, y))
		for i: int in 4:
			var index: int = rng.randi_range(0, rooms.size() - 1)
			humming_rooms.append({"center": rooms[index], "radius": rng.randi_range(2, 4)})
			rooms.remove_at(index)
	else:
		guard = 0
		while humming_rooms.size() < 4 and guard < 6000:
			guard += 1
			var hc := _random_floor_cell()
			if _manhattan(hc, spawn_cell) >= 30 and not _protected_cell(hc) and _zone_spread_ok(hc, humming_rooms, 40):
				humming_rooms.append({"center": hc, "radius": rng.randi_range(3, 5)})


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _zone_spread_ok(c: Vector2i, zones: Array, min_d: int) -> bool:
	for z: Dictionary in zones:
		if _manhattan(c, z["center"]) < min_d:
			return false
	return true


func _in_zone(cell: Vector2i, zone: Dictionary) -> bool:
	var c: Vector2i = zone["center"]
	var dx: int = cell.x - c.x
	var dy: int = cell.y - c.y
	var r: int = int(zone["radius"])
	return dx * dx + dy * dy <= r * r


func _place_fixtures() -> void:
	fixture_state.clear()
	fixture_state.resize(GRID_W * GRID_H)
	fixture_state.fill(F_NONE)
	fixture_phase.clear()
	fixture_phase.resize(GRID_W * GRID_H)
	fixture_warmth.clear()
	fixture_warmth.resize(GRID_W * GRID_H)
	fixture_hanging.clear()
	fixture_hanging.resize(GRID_W * GRID_H)
	for y: int in GRID_H:
		for x: int in GRID_W:
			if _is_wall(x, y):
				continue
			var i: int = y * GRID_W + x
			var region: String = region_of(Vector2i(x, y))
			var density: float = 0.88
			if region == "service":
				density = 0.6
			elif region == "server":
				density = 1.0
			elif region == "dark":
				density = 0.7
			elif region == "machine":
				density = 0.5
			var cell := Vector2i(x, y)
			var near_key: bool = false
			for k: Vector2i in key_cells:
				if _manhattan(cell, k) <= 2:
					near_key = true
					break
			if rng.randf() > density and not near_key:
				continue  # no fixture
			var st: int = F_STEADY
			var in_dark: bool = false
			for z: Dictionary in dark_zones:
				if _in_zone(cell, z):
					in_dark = true
					break
			var in_hum: bool = false
			for z: Dictionary in humming_rooms:
				if _in_zone(cell, z):
					in_hum = true
					break
			if in_hum or near_key:
				st = F_STEADY
			elif in_dark:
				st = F_DEAD
			else:
				var in_flicker: bool = false
				for z: Dictionary in flicker_zones:
					if _in_zone(cell, z):
						in_flicker = true
						break
				var roll: float = rng.randf()
				if in_flicker:
					if roll < 0.30:
						st = F_FLICKER
					elif roll < 0.40:
						st = F_DEAD
				else:
					# Authored lighting character per wing.
					if region == "service":
						if roll < 0.15:
							st = F_FLICKER
						elif roll < 0.25:
							st = F_DEAD
					elif region == "server":
						st = F_STEADY
					elif region == "dark":
						if roll < 0.08:
							st = F_FLICKER
						elif roll < 0.78:
							st = F_DEAD
					elif region == "machine":
						if roll < 0.10:
							st = F_FLICKER
						elif roll < 0.55:
							st = F_DEAD
					elif roll < 0.05:
						st = F_FLICKER
					elif roll < 0.07:
						st = F_DEAD
			fixture_state[i] = st
			fixture_phase[i] = rng.randf_range(0.0, 100.0)
			fixture_warmth[i] = rng.randf_range(0.9, 1.1)
			fixture_hanging[i] = 1 if rng.randf() < 0.05 else 0


func _validate() -> bool:
	if grid.size() != GRID_W * GRID_H or spawn_cell != _level_spawn() or exit_cell != _level_exit():
		return false
	for anchor: Vector2i in key_cells:
		if _is_wall(anchor.x, anchor.y):
			return false
	dist_map = _bfs_distances(spawn_cell)
	for anchor: Vector2i in key_cells:
		if dist_map[anchor.y * GRID_W + anchor.x] < 0:
			return false
	if level_index == 0:
		for scrap: Vector2i in SCRAP_CELLS:
			if _is_wall(scrap.x, scrap.y) or dist_map[scrap.y * GRID_W + scrap.x] < 0:
				return false
	var reached: int = 0
	var floor_total: int = 0
	for y: int in GRID_H:
		for x: int in GRID_W:
			if _is_wall(x, y):
				continue
			floor_total += 1
			if dist_map[y * GRID_W + x] != -1:
				reached += 1
	if floor_total == 0:
		return false
	var exit_dist: int = dist_map[exit_cell.y * GRID_W + exit_cell.x]
	return exit_dist > 0 and reached == floor_total


func random_entity_spawn(min_dist: int = 45, max_dist: int = 160) -> Vector2i:
	var guard: int = 0
	while guard < 2000:
		guard += 1
		var c := _random_floor_cell()
		var d: int = dist_map[c.y * GRID_W + c.x]
		if d >= min_dist and d <= max_dist and not _protected_cell(c) and not pillar_cells.has(c):
			return c
	# Fallback: farthest in-band cell, else farthest reachable anywhere.
	var best: Vector2i = spawn_cell
	var best_d: int = -1
	var far: Vector2i = spawn_cell
	var far_d: int = 0
	for y: int in GRID_H:
		for x: int in GRID_W:
			var c := Vector2i(x, y)
			var d: int = dist_map[y * GRID_W + x]
			if d < 0 or _protected_cell(c) or pillar_cells.has(c):
				continue
			if d > far_d:
				far_d = d
				far = c
			if d >= min_dist and d <= max_dist and d > best_d:
				best_d = d
				best = c
	return best if best_d >= 0 else far


# ---------------------------------------------------------------- world build

func _floor_quad(parent: Node3D, x0: float, z0: float, x1: float, z1: float, mat: Material, y: float) -> void:
	var q := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(x1 - x0, z1 - z0)
	q.mesh = pm
	q.material_override = mat
	q.position = Vector3((x0 + x1) / 2.0, y, (z0 + z1) / 2.0)
	parent.add_child(q)


func build_world(parent: Node3D, mats: Dictionary) -> Dictionary:
	"""Create static geometry. Returns {spawn_pos, spawn_yaw, exit_pos, exit_area}."""
	var static_body := StaticBody3D.new()
	static_body.name = "Static"
	parent.add_child(static_body)
	var span: float = float(GRID_W) * CELL
	# Floor (visual + collision) and ceiling (visual only).
	var floor_mesh := MeshInstance3D.new()
	var floor_plane := PlaneMesh.new()
	floor_plane.size = Vector2(span, span)
	floor_mesh.mesh = floor_plane
	floor_mesh.material_override = mats["floor"]
	parent.add_child(floor_mesh)
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(span, 1.0, span)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0, -0.5, 0)
	static_body.add_child(floor_shape)
	var ceil_mesh := MeshInstance3D.new()
	var ceil_plane := PlaneMesh.new()
	ceil_plane.size = Vector2(span, span)
	ceil_mesh.mesh = ceil_plane
	ceil_mesh.rotation_degrees = Vector3(180, 0, 0)
	ceil_mesh.position = Vector3(0, WALL_H, 0)
	ceil_mesh.material_override = mats["ceiling"]
	parent.add_child(ceil_mesh)
	# Per-wing floor skins over the carpet base (L0 paint; deeper levels
	# reskin the base floor itself).
	if level_index == 0:
		_floor_quad(parent, -25.5, -229.5, 19.5, -220.5, mats["floor_service"], 0.01)
		_floor_quad(parent, -1.5, -223.5, 1.5, -193.5, mats["floor_service"], 0.011)
		_floor_quad(parent, 142.5, -7.5, 166.5, 7.5, mats["floor_server"], 0.012)
		_floor_quad(parent, 166.5, -4.5, 175.5, 4.5, mats["floor_server"], 0.013)
	# Walls: merge each row into runs -> one MultiMesh + one collision box per run.
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3(1, 1, 1)
	var wall_x: Array = [[], [], [], []]
	var base_xforms: Array[Transform3D] = []
	for y: int in GRID_H:
		# Wall runs break on floor cells and on district changes.
		var run_start: int = -1
		var run_d: int = 0
		for x: int in GRID_W + 1:  # +1 sentinel flushes the run
			var w: bool = x < GRID_W and grid[y * GRID_W + x] == 1
			var wd: int = wall_mat_of(Vector2i(x, y)) if w else -1
			if run_start != -1 and (not w or x == GRID_W or wd != run_d):
				var length: int = x - run_start
				var center_cell: float = float(run_start) + float(length - 1) / 2.0
				var pos := Vector3((center_cell - float(GRID_C)) * CELL, WALL_H / 2.0, (float(y) - float(GRID_C)) * CELL)
				var scl := Vector3(float(length) * CELL, WALL_H, CELL)
				(wall_x[run_d] as Array).append(Transform3D(Basis.from_scale(scl), pos))
				base_xforms.append(Transform3D(Basis.from_scale(Vector3(scl.x, 0.12, CELL + 0.04)), Vector3(pos.x, 0.06, pos.z)))
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = scl
				cs.shape = bs
				cs.position = pos
				static_body.add_child(cs)
				run_start = -1
			if w and run_start == -1:
				run_start = x
				run_d = wd
	_add_multimesh(parent, "WallsLobby", unit_box, mats["wall"], wall_x[0])
	_add_multimesh(parent, "WallsWest", unit_box, mats["wallB"], wall_x[1])
	_add_multimesh(parent, "WallsService", unit_box, mats["wall2"], wall_x[2])
	_add_multimesh(parent, "WallsServer", unit_box, mats["wall3"], wall_x[3])
	# Pillars + dark base/capital trim so they read as columns, not boxes.
	var pillar_xforms: Array[Transform3D] = []
	var trim_xforms: Array[Transform3D] = []
	for pc: Vector2i in pillar_cells:
		var base: Vector3 = cell_to_world(pc)
		var pos := Vector3(base.x, WALL_H / 2.0, base.z)
		var scl := Vector3(0.6, WALL_H, 0.6)
		pillar_xforms.append(Transform3D(Basis.from_scale(scl), pos))
		trim_xforms.append(Transform3D(Basis.from_scale(Vector3(0.68, 0.25, 0.68)), Vector3(base.x, 0.125, base.z)))
		trim_xforms.append(Transform3D(Basis.from_scale(Vector3(0.68, 0.16, 0.68)), Vector3(base.x, WALL_H - 0.08, base.z)))
		var pcs := CollisionShape3D.new()
		var pbs := BoxShape3D.new()
		pbs.size = scl
		pcs.shape = pbs
		pcs.position = pos
		static_body.add_child(pcs)
	_add_multimesh(parent, "Pillars", unit_box, mats["wall"], pillar_xforms)
	_add_multimesh(parent, "PillarTrim", unit_box, PropFactory.get_shared()["dark"], trim_xforms)
	_add_multimesh(parent, "Baseboards", unit_box, PropFactory.get_shared()["dark"], base_xforms)
	return {"static_body": static_body}


func _add_multimesh(parent: Node, node_name: String, mesh: Mesh, mat: Material, xforms: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)
	return mmi


func build_dressing(parent: Node3D, mats: Dictionary, audio: AudioManager) -> Dictionary:
	"""Fixtures, vents, doors, chairs, stains, props, pickups, exit."""
	# Independent seeded dressing stream: repeatable even after entity RNG draws.
	rng.seed = seed_used ^ 20240314
	var panel_shader := load("res://shaders/light_panel.gdshader") as Shader
	var steady_mat := ShaderMaterial.new()
	steady_mat.shader = panel_shader
	var flicker_mat := ShaderMaterial.new()
	flicker_mat.shader = panel_shader
	flicker_mat.set_shader_parameter("flicker_enabled", 1.0)
	var steady_dim := ShaderMaterial.new()
	steady_dim.shader = panel_shader
	steady_dim.set_shader_parameter("steady_color", Color(0.72, 0.75, 0.72))
	steady_dim.set_shader_parameter("energy", 1.0)
	var steady_cool := ShaderMaterial.new()
	steady_cool.shader = panel_shader
	steady_cool.set_shader_parameter("steady_color", Color(0.72, 0.86, 1.0))
	steady_cool.set_shader_parameter("energy", 1.9)
	var dead_mat := StandardMaterial3D.new()
	dead_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dead_mat.albedo_color = Color(0.045, 0.045, 0.045)
	var s := PropFactory.get_shared()
	var down := Basis.from_euler(Vector3(PI / 2.0, 0, 0))
	# --- Light panels, one MultiMesh per behavior + one for frames.
	var panel_quad := QuadMesh.new()
	panel_quad.size = Vector2(1.5, 0.75)
	var steady_x: Array = [[], [], []]
	var flicker_x: Array[Transform3D] = []
	var dead_x: Array[Transform3D] = []
	var frame_xforms: Array[Transform3D] = []
	for y: int in GRID_H:
		for x: int in GRID_W:
			var i: int = y * GRID_W + x
			var st: int = fixture_state[i]
			if st == F_NONE:
				continue
			var fdistrict: int = district_of(Vector2i(x, y))
			var base: Vector3 = cell_to_world(Vector2i(x, y))
			var drop: float = 0.5 if fixture_hanging[i] == 1 else 0.0
			var py: float = WALL_H - 0.06 - drop
			var xf := Transform3D(down, Vector3(base.x, py, base.z))
			if st == F_FLICKER:
				flicker_x.append(xf)
			elif st == F_DEAD:
				dead_x.append(xf)
			else:
				(steady_x[fdistrict] as Array).append(xf)
			# Slim aluminum rails around the diffuser, not a solid slab.
			var ry: float = py + 0.01
			frame_xforms.append(Transform3D(Basis.from_scale(Vector3(1.60, 0.06, 0.06)), Vector3(base.x, ry, base.z - 0.40)))
			frame_xforms.append(Transform3D(Basis.from_scale(Vector3(1.60, 0.06, 0.06)), Vector3(base.x, ry, base.z + 0.40)))
			frame_xforms.append(Transform3D(Basis.from_scale(Vector3(0.06, 0.06, 0.74)), Vector3(base.x - 0.77, ry, base.z)))
			frame_xforms.append(Transform3D(Basis.from_scale(Vector3(0.06, 0.06, 0.74)), Vector3(base.x + 0.77, ry, base.z)))
			if drop > 0.0:
				frame_xforms.append(Transform3D(Basis.from_scale(Vector3(0.035, 0.5, 0.035)), Vector3(base.x, WALL_H - 0.25, base.z)))
				frame_xforms.append(Transform3D(Basis.from_scale(Vector3(0.035, 0.5, 0.035)), Vector3(base.x + 0.5, WALL_H - 0.25, base.z)))
	_add_multimesh(parent, "PanelsSteady", panel_quad, steady_mat, steady_x[0])
	_add_multimesh(parent, "PanelsSteadyC", panel_quad, steady_dim, steady_x[1])
	_add_multimesh(parent, "PanelsSteadyE", panel_quad, steady_cool, steady_x[2])
	_add_multimesh(parent, "PanelsFlicker", panel_quad, flicker_mat, flicker_x)
	_add_multimesh(parent, "PanelsDead", panel_quad, dead_mat, dead_x)
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3(1, 1, 1)
	_add_multimesh(parent, "Frames", unit_box, s["alu"], frame_xforms)
	# --- Vents: 8 dark grilles on the ceiling.
	var vent_mat := StandardMaterial3D.new()
	vent_mat.albedo_texture = mats["vent"] as Texture2D
	vent_mat.roughness = 1.0
	for i: int in 20:
		var vc: Vector3 = cell_to_world(_random_floor_cell())
		var vent := MeshInstance3D.new()
		var vq := QuadMesh.new()
		vq.size = Vector2(1.2, 0.6)
		vent.mesh = vq
		vent.material_override = vent_mat
		vent.transform = Transform3D(down, Vector3(vc.x, WALL_H - 0.02, vc.z))
		parent.add_child(vent)
	# --- Fake doors on six long walls. Never open.
	if level_index == 0:
		var di: int = 0
		for face: Dictionary in [
			{"cell": Vector2i(90, 19), "dir": Vector2i(0, 1)},
			{"cell": Vector2i(98, 19), "dir": Vector2i(0, 1)},
			{"cell": Vector2i(146, 93), "dir": Vector2i(0, 1)},
			{"cell": Vector2i(23, 83), "dir": Vector2i(0, 1)},
			{"cell": Vector2i(94, 99), "dir": Vector2i(0, -1)},
			{"cell": Vector2i(94, 93), "dir": Vector2i(0, 1)},
		]:
			var door := PropFactory.build_fake_door(audio.thunk_stream, mats["metaldor"])
			door.name = "FakeDoor_%d" % di
			di += 1
			_place_on_face(door, face)
			parent.add_child(door)
	# --- Fake EXIT signs pointing at nothing.
	for i: int in rng.randi_range(5, 8):
		var face := _random_wall_face()
		var sign := PropFactory.build_exit_sign()
		_place_on_face(sign, face, 2.42)
		parent.add_child(sign)
	# --- Half-sunk chairs: the signature wrongness.
	for i: int in rng.randi_range(24, 36):
		var cc: Vector3 = cell_to_world(_random_floor_cell())
		var chair := PropFactory.build_chair()
		chair.position = Vector3(cc.x, -rng.randf_range(0.2, 0.55), cc.z)
		chair.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(0.0, TAU), rng.randf_range(-0.12, 0.12))
		parent.add_child(chair)
	# --- Chair rows facing blank walls, one chair missing each.
	for i: int in 5:
		_build_chair_row(parent)
	# --- Wet floor patches.
	var wet_mat := StandardMaterial3D.new()
	wet_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wet_mat.albedo_texture = mats["wet"] as Texture2D
	wet_mat.roughness = 0.15
	wet_mat.metallic = 0.25
	for i: int in rng.randi_range(60, 90):
		var wc: Vector3 = cell_to_world(_random_floor_cell())
		var patch := MeshInstance3D.new()
		var pq := QuadMesh.new()
		var ps: float = rng.randf_range(1.0, 2.5)
		pq.size = Vector2(ps, ps)
		patch.mesh = pq
		patch.material_override = wet_mat
		patch.rotation = Vector3(-PI / 2.0, 0, rng.randf_range(0.0, TAU))
		patch.position = Vector3(wc.x, 0.015, wc.z)
		parent.add_child(patch)
	# Service district sweats: extra wet patches where the concrete weeps.
	for i: int in rng.randi_range(30, 45):
		var sc: Vector3 = cell_to_world(_random_floor_cell_in_district(1))
		var spatch := MeshInstance3D.new()
		var sq := QuadMesh.new()
		var ss: float = rng.randf_range(1.2, 3.0)
		sq.size = Vector2(ss, ss)
		spatch.mesh = sq
		spatch.material_override = wet_mat
		spatch.rotation = Vector3(-PI / 2.0, 0, rng.randf_range(0.0, TAU))
		spatch.position = Vector3(sc.x, 0.015, sc.z)
		parent.add_child(spatch)
	# --- Wall grime streaks.
	var grime_mat := StandardMaterial3D.new()
	grime_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grime_mat.albedo_texture = mats["grime"] as Texture2D
	grime_mat.roughness = 1.0
	for i: int in 100:
		var face := _random_wall_face()
		var quad := MeshInstance3D.new()
		var gq := QuadMesh.new()
		gq.size = Vector2(1.4, 1.8)
		quad.mesh = gq
		quad.material_override = grime_mat
		_place_on_face(quad, face, 1.5, 0.03)
		parent.add_child(quad)
	for i: int in 40:
		var sface := _random_wall_face_in_district(1)
		var squad := MeshInstance3D.new()
		var sgq := QuadMesh.new()
		sgq.size = Vector2(1.4, 1.8)
		squad.mesh = sgq
		squad.material_override = grime_mat
		_place_on_face(squad, sface, 1.5, 0.03)
		parent.add_child(squad)
	# --- Prop corners: filing cabinet + crates + cooler + cone, arranged wrong.
	for cluster: Dictionary in prop_clusters:
		_build_prop_corner(parent, cluster["center"], mats["screen"])
	# --- Server racks along east-district walls, LEDs blinking wrong.
	var rack_blink := ShaderMaterial.new()
	rack_blink.shader = panel_shader
	rack_blink.set_shader_parameter("flicker_enabled", 1.0)
	rack_blink.set_shader_parameter("steady_color", Color(0.3, 1.0, 0.6))
	rack_blink.set_shader_parameter("energy", 2.0)
	if level_index == 0:
		for rz: float in [-4.0, -1.0, 2.0, 5.0]:
			for k: int in 5:
				var rack := PropFactory.build_server_rack(rack_blink)
				rack.name = "ServerRack_%d_%d" % [k, int(rz)]
				rack.position = Vector3(146.0 + float(k) * 3.0, 0, rz)
				parent.add_child(rack)
	# --- Survival pickups: 14 water + 12 bread, random per run.
	# 8m+ from spawn, 2m+ apart, never on the exit cell.
	# Build order is deterministic per seed, so net ids match on both peers.
	rng.seed = seed_used * 7919 + 17
	var placed: Array[Vector3] = []
	var spawn_w: Vector3 = cell_to_world(spawn_cell)
	var water_n: int = 0
	var net_i: int = 0
	var pickups_out: Array = []
	var guard: int = 0
	while water_n < 42 and guard < 2400:
		guard += 1
		var wc: Vector2i = _random_floor_cell()
		if wc == exit_cell:
			continue
		var wp0: Vector3 = cell_to_world(wc)
		var wp := Vector3(wp0.x + rng.randf_range(-0.9, 0.9), 0, wp0.z + rng.randf_range(-0.9, 0.9))
		if wp.distance_to(spawn_w) < 8.0 or _too_close(wp, placed):
			continue
		placed.append(wp)
		var bottle := PropFactory.build_pickup("water", audio.gulp_stream)
		bottle.net_id = net_i
		net_i += 1
		bottle.position = wp
		parent.add_child(bottle)
		pickups_out.append(bottle)
		water_n += 1
	var bread_n: int = 0
	guard = 0
	while bread_n < 36 and guard < 2400:
		guard += 1
		var bc: Vector2i = _random_floor_cell()
		if bc == exit_cell:
			continue
		var bp0: Vector3 = cell_to_world(bc)
		var bp := Vector3(bp0.x + rng.randf_range(-0.9, 0.9), 0, bp0.z + rng.randf_range(-0.9, 0.9))
		if bp.distance_to(spawn_w) < 8.0 or _too_close(bp, placed):
			continue
		placed.append(bp)
		var loaf := PropFactory.build_pickup("bread", audio.thunk_stream)
		loaf.net_id = net_i
		net_i += 1
		loaf.position = bp
		parent.add_child(loaf)
		pickups_out.append(loaf)
		bread_n += 1
	rng.seed = seed_used ^ 20240315
	# --- Humming rooms get a chair row + cooler each.
	for room: Dictionary in humming_rooms:
		_build_chair_row_at(parent, room["center"])
		var cp: Vector3 = cell_to_world(_nearest_floor(room["center"] + Vector2i(2, 0)))
		var cooler := PropFactory.build_cooler()
		cooler.position = Vector3(cp.x, 0, cp.z)
		parent.add_child(cooler)
	# --- Wing gateways: hazard portal frames.
	if level_index == 0:
		var gi: int = 0
		for g: Array in [[Vector2i(92, 96), 0.0], [Vector2i(96, 90), PI / 2.0], [Vector2i(100, 96), 0.0], [Vector2i(96, 99), PI / 2.0]]:
			var gp: Vector3 = cell_to_world(g[0])
			var gate := PropFactory.build_gateway(mats["hazard"])
			gate.name = "Gateway_%d" % gi
			gi += 1
			gate.position = Vector3(gp.x, 0, gp.z)
			gate.rotation.y = float(g[1])
			parent.add_child(gate)
	# --- Service pipes along both twin corridors.
	if level_index == 0:
		var pipemat: Material = PropFactory.get_shared()["metal"]
		for pz: float in [-228.0, -222.0]:
			for off: float in [-1.3, 1.3]:
				var pipe := MeshInstance3D.new()
				var pbm := BoxMesh.new()
				pbm.size = Vector3(45.0, 0.12, 0.12)
				pipe.mesh = pbm
				pipe.material_override = pipemat
				pipe.position = Vector3(-3.0, 2.2, pz + off)
				parent.add_child(pipe)
	# --- Lobby reception: desk + cooler + cone.
	if level_index == 0:
		var desk := PropFactory.build_desk(mats["screen"])
		desk.position = Vector3(0, 0, -5.0)
		parent.add_child(desk)
		var cooler0 := PropFactory.build_cooler()
		cooler0.position = Vector3(1.6, 0, -5.0)
		parent.add_child(cooler0)
		var cone0 := PropFactory.build_cone()
		cone0.position = Vector3(-1.6, 0, -5.0)
		parent.add_child(cone0)
	# --- Briefing room chairs + monitor room desk.
	if level_index == 0:
		for k: int in 4:
			var bchair := PropFactory.build_chair()
			bchair.position = Vector3(-202.5 + float(k), 0, -20.0)
			bchair.rotation.y = PI
			parent.add_child(bchair)
		var mdesk := PropFactory.build_desk(mats["screen"])
		mdesk.position = Vector3(-225.0, 0, -32.0)
		mdesk.rotation.y = PI
		parent.add_child(mdesk)
	# --- Service crates + cones, dark pocket scattered chairs.
	if level_index == 0:
		var crate0 := PropFactory.build_crate(0.7)
		crate0.position = Vector3(-18.0, 0, -227.0)
		parent.add_child(crate0)
		var crate1 := PropFactory.build_crate(0.5)
		crate1.position = Vector3(0.0, 0, -221.0)
		parent.add_child(crate1)
		for cpos: Vector2 in [Vector2(-15.0, -225.0), Vector2(9.0, -225.0)]:
			var svc_cone := PropFactory.build_cone()
			svc_cone.position = Vector3(cpos.x, 0, cpos.y)
			parent.add_child(svc_cone)
		for ch: Array in [[Vector3(-9.0, 0, 132.0), 0.4], [Vector3(3.0, 0, 135.0), 2.1], [Vector3(-9.0, 0, 144.0), 4.0], [Vector3(6.0, 0, 135.0), 5.3]]:
			var dchair := PropFactory.build_chair()
			dchair.position = ch[0]
			dchair.rotation.y = float(ch[1])
			parent.add_child(dchair)
	# --- Break room + archive: furnished set-piece rooms.
	if level_index == 0:
		_build_break_room(parent)
		_build_archive(parent)
	# --- Amber way-plates: true station signage, numbered like the plates.
	_place_wayfinding(parent)
	# --- Margin-note scraps for the field journal.
	if level_index == 0:
		_place_scraps(parent)
	# --- Wall plates: outlets low, switches high, alternating.
	_place_wall_plates(parent)
	# --- West pipe runs along two corridors.
	if level_index == 0:
		_place_west_pipes(parent)
	elif level_index == 2:
		_place_machine_pipes(parent)
	# --- Stairs down, or the one real exit on the final level.
	var exit_area: Area3D = null
	var stairs_area: Area3D = null
	var ep: Vector3 = cell_to_world(exit_cell)
	if level_index == FINAL_LEVEL:
		var exit_door := PropFactory.build_exit_door()
		exit_door.position = Vector3(ep.x, 0, ep.z)
		exit_door.rotation.y = float(rng.randi_range(0, 3)) * PI / 2.0
		parent.add_child(exit_door)
		exit_area = exit_door.get_node("ExitArea") as Area3D
	else:
		var stairs := PropFactory.build_stairs_down()
		stairs.position = Vector3(ep.x, 0, ep.z)
		rng.randi_range(0, 3)  # keep the draw: stream position is pinned downstream.
		stairs.rotation.y = -PI / 2.0  # open side + DOWN sign face the west approach.
		parent.add_child(stairs)
		stairs_area = stairs.get_node("StairsArea") as Area3D
	exit_world_pos = Vector3(ep.x, 0, ep.z)
	var beacon := AudioStreamPlayer3D.new()
	beacon.name = "ExitBeacon"
	beacon.stream = audio.beacon_stream
	beacon.max_distance = 30.0
	beacon.volume_db = -4.0
	beacon.position = exit_world_pos + Vector3(0, 2.2, 0)
	parent.add_child(beacon)
	if audio.beacon_stream != null:
		beacon.play()
	_apply_culling(parent)
	var dzc: Vector2i = dark_zones[0]["center"]
	return {
		"panel_materials": [steady_mat, steady_dim, steady_cool, flicker_mat, rack_blink],
		"exit_area": exit_area,
		"stairs_area": stairs_area,
		"exit_pos": exit_world_pos,
		"spawn_pos": cell_to_world(spawn_cell),
		"spawn_yaw": spawn_yaw,
		"dark_zone_world": cell_to_world(dzc),
		"pickup_water": water_n,
		"pickup_bread": bread_n,
		"pickups": pickups_out,
	}


func _too_close(p: Vector3, placed: Array[Vector3]) -> bool:
	for q: Vector3 in placed:
		var d: Vector3 = p - q
		if d.x * d.x + d.z * d.z < 4.0:
			return true
	return false


func _random_wall_face() -> Dictionary:
	"""Random wall cell + the direction toward an adjacent floor cell."""
	var guard: int = 0
	while guard < 2000:
		guard += 1
		var x: int = rng.randi_range(1, GRID_W - 2)
		var y: int = rng.randi_range(1, GRID_H - 2)
		if not _is_wall(x, y):
			continue
		var dirs: Array[Vector2i] = []
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not _is_wall(x + d.x, y + d.y):
				dirs.append(d)
		if not dirs.is_empty():
			return {"cell": Vector2i(x, y), "dir": dirs[rng.randi_range(0, dirs.size() - 1)]}
	return {"cell": Vector2i(1, 1), "dir": Vector2i(1, 0)}


func _place_on_face(node: Node3D, face: Dictionary, height: float = 0.0, proud: float = 0.06) -> void:
	var base: Vector3 = cell_to_world(face["cell"])
	var d: Vector2i = face["dir"]
	var n := Vector3(float(d.x), 0, float(d.y))
	node.position = Vector3(base.x + n.x * (CELL / 2.0 - proud), height, base.z + n.z * (CELL / 2.0 - proud))
	node.rotation.y = atan2(n.x, n.z)


func _nearest_floor(cell: Vector2i) -> Vector2i:
	if not _is_wall(cell.x, cell.y):
		return cell
	for r: int in range(1, 5):
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				var c := Vector2i(cell.x + dx, cell.y + dy)
				if c.x > 0 and c.y > 0 and c.x < GRID_W - 1 and c.y < GRID_H - 1 and not _is_wall(c.x, c.y):
					return c
	return spawn_cell


func _build_chair_row(parent: Node3D) -> void:
	var face := _random_wall_face()
	var d: Vector2i = face["dir"]
	# Row runs along the wall (perpendicular), chairs stand on the floor side.
	var along := Vector2i(-d.y, d.x)
	var base: Vector2i = face["cell"] + d
	var count: int = rng.randi_range(3, 5)
	var missing: int = rng.randi_range(0, count - 1)
	for k: int in count:
		if k == missing:
			continue
		var spot: Vector2i = _nearest_floor(base + along * k)
		var wp: Vector3 = cell_to_world(spot)
		var chair := PropFactory.build_chair()
		chair.position = Vector3(wp.x, 0, wp.z)
		# Face the wall.
		chair.rotation.y = atan2(float(-d.x), float(-d.y))
		parent.add_child(chair)


func _random_wall_face_near(center: Vector2i, radius: int) -> Dictionary:
	var guard: int = 0
	while guard < 800:
		guard += 1
		var x: int = clampi(center.x + rng.randi_range(-radius, radius), 1, GRID_W - 2)
		var y: int = clampi(center.y + rng.randi_range(-radius, radius), 1, GRID_H - 2)
		if not _is_wall(x, y):
			continue
		var dirs: Array[Vector2i] = []
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not _is_wall(x + d.x, y + d.y):
				dirs.append(d)
		if not dirs.is_empty():
			return {"cell": Vector2i(x, y), "dir": dirs[rng.randi_range(0, dirs.size() - 1)]}
	return _random_wall_face()


func _random_floor_cell_in_district(d: int) -> Vector2i:
	var guard: int = 0
	while guard < 2000:
		guard += 1
		var c := _random_floor_cell()
		if district_of(c) == d:
			return c
	return _random_floor_cell()


func _random_wall_face_in_district(d: int) -> Dictionary:
	var guard: int = 0
	while guard < 200:
		guard += 1
		var face := _random_wall_face()
		if district_of(face["cell"]) == d:
			return face
	return _random_wall_face()


func _build_chair_row_at(parent: Node3D, center: Vector2i) -> void:
	var face := _random_wall_face_near(center, 5)
	var d: Vector2i = face["dir"]
	var along := Vector2i(-d.y, d.x)
	var base: Vector2i = face["cell"] + d
	var count: int = rng.randi_range(3, 5)
	var missing: int = rng.randi_range(0, count - 1)
	for k: int in count:
		if k == missing:
			continue
		var spot: Vector2i = _nearest_floor(base + along * k)
		var wp: Vector3 = cell_to_world(spot)
		var chair := PropFactory.build_chair()
		chair.position = Vector3(wp.x, 0, wp.z)
		chair.rotation.y = atan2(float(-d.x), float(-d.y))
		parent.add_child(chair)


func _build_prop_corner(parent: Node3D, center: Vector2i, screen_tex: Texture2D) -> void:
	var items: Array[Node3D] = [
		PropFactory.build_cabinet(),
		PropFactory.build_crate(0.7),
		PropFactory.build_crate(0.5),
		PropFactory.build_cooler(),
		PropFactory.build_cone(),
		PropFactory.build_desk(screen_tex),
	]
	var offsets: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, 1)
	]
	for i: int in items.size():
		var spot: Vector2i = _nearest_floor(center + offsets[i])
		var wp: Vector3 = cell_to_world(spot)
		items[i].position = Vector3(wp.x + rng.randf_range(-0.7, 0.7), 0, wp.z + rng.randf_range(-0.7, 0.7))
		items[i].rotation.y = rng.randf_range(0.0, TAU)
		parent.add_child(items[i])
	# Second crate stacked on the first, slightly wrong.
	items[2].position = items[1].position + Vector3(0.12, 0.7, -0.08)


func _build_break_room(parent: Node3D) -> void:
	# Table + chairs + cooler in BREAK_ROOM. Scrap 0 stands at (32, 91).
	var table := PropFactory.build_table()
	var tw: Vector3 = cell_to_world(Vector2i(33, 91))
	table.position = Vector3(tw.x, 0, tw.z)
	table.rotation.y = 0.15
	parent.add_child(table)
	for cc: Vector2i in [Vector2i(32, 92), Vector2i(34, 91), Vector2i(33, 90)]:
		var cw: Vector3 = cell_to_world(cc)
		var chair := PropFactory.build_chair()
		chair.position = Vector3(cw.x, 0, cw.z)
		chair.rotation.y = atan2(tw.x - cw.x, tw.z - cw.z) + rng.randf_range(-0.2, 0.2)
		parent.add_child(chair)
	var cooler := PropFactory.build_cooler()
	var kw: Vector3 = cell_to_world(Vector2i(31, 90))
	cooler.position = Vector3(kw.x, 0, kw.z)
	parent.add_child(cooler)


func _build_archive(parent: Node3D) -> void:
	# Shelf wall + crates in ARCHIVE_ROOM. Scrap 1 stands at (92, 18).
	for sx: int in [90, 92, 94]:
		var sw: Vector3 = cell_to_world(Vector2i(sx, 17))
		var shelf := PropFactory.build_shelf()
		shelf.name = "Shelf_%d" % sx
		shelf.position = Vector3(sw.x, 0, sw.z - 0.9)
		parent.add_child(shelf)
	for cc: Vector2i in [Vector2i(91, 18), Vector2i(93, 18)]:
		var cw: Vector3 = cell_to_world(cc)
		var crate := PropFactory.build_crate(0.7)
		crate.position = Vector3(cw.x, 0, cw.z)
		crate.rotation.y = rng.randf_range(0.0, TAU)
		parent.add_child(crate)


func _place_wayfinding(parent: Node3D) -> void:
	# Six amber plates per field station, wall-mounted where the corridor
	# runs along the downhill flow. Deterministic scan, no RNG.
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var placed: Array[Vector2i] = []
	var idx: int = 0
	for s: int in level_station_ids():
		var dist: PackedInt32Array = _bfs_distances(station_cell_global(s))
		var count: int = 0
		for y: int in range(1, GRID_H - 1):
			if count >= 6:
				break
			for x: int in range(1, GRID_W - 1):
				if count >= 6:
					break
				var d: int = dist[y * GRID_W + x]
				if d < 6 or d > 40:
					continue
				var cell := Vector2i(x, y)
				if _protected_cell(cell):
					continue
				var spread: bool = true
				for p: Vector2i in placed:
					if _manhattan(p, cell) < 8:
						spread = false
						break
				if not spread:
					continue
				# Downhill flow: first neighbor with strictly lower distance.
				var flow := Vector2i.ZERO
				for f: Vector2i in dirs:
					var n: Vector2i = cell + f
					if dist[n.y * GRID_W + n.x] == d - 1:
						flow = f
						break
				if flow == Vector2i.ZERO:
					continue
				# Aligned wall: plate faces the corridor, arrow runs along flow.
				for w: Vector2i in dirs:
					var wall_c: Vector2i = cell + w
					if not _is_wall(wall_c.x, wall_c.y):
						continue
					var nrm: Vector2i = cell - wall_c
					if flow.x * nrm.x + flow.y * nrm.y != 0:
						continue
					var theta: float = atan2(float(nrm.x), float(nrm.y))
					var local_x := Vector2i(roundi(cos(theta)), roundi(-sin(theta)))
					var text: String = "0%d >" % (s + 1) if flow == local_x else "< 0%d" % (s + 1)
					var plate := PropFactory.build_way_plate(text)
					plate.name = "WayPlate_%d" % idx
					idx += 1
					plate.set_meta("station", s)
					plate.set_meta("flow", flow)
					plate.set_meta("cell", cell)
					_place_on_face(plate, {"cell": wall_c, "dir": nrm}, 1.9)
					parent.add_child(plate)
					placed.append(cell)
					count += 1
					break


func _place_scraps(parent: Node3D) -> void:
	for i: int in SCRAP_CELLS.size():
		var scrap := LoreScrap.new()
		scrap.name = "LoreScrap_%d" % i
		scrap.scrap_id = i
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.5, 1.5, 0.5)
		cs.shape = bs
		cs.position = Vector3(0, 0.75, 0)
		scrap.add_child(cs)
		var stand := PropFactory.build_scrap_stand()
		scrap.add_child(stand)
		var wp: Vector3 = cell_to_world(SCRAP_CELLS[i])
		scrap.position = Vector3(wp.x, 0, wp.z)
		scrap.rotation.y = float(i) * PI / 3.0
		parent.add_child(scrap)


func _place_wall_plates(parent: Node3D) -> void:
	# Ivory outlet/switch plates on corridor walls. Deterministic scan of
	# wall faces, strided to cap the count. One shared multimesh.
	var faces: Array = []
	for y: int in range(1, GRID_H - 1):
		for x: int in range(1, GRID_W - 1):
			if not _is_wall(x, y):
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not _is_wall(x + d.x, y + d.y):
					faces.append({"cell": Vector2i(x, y), "dir": d})
	var stride: int = maxi(1, faces.size() / 120)
	var xforms: Array[Transform3D] = []
	var idx: int = 0
	for fi: int in range(0, faces.size(), stride):
		if xforms.size() >= 120:
			break
		var face: Dictionary = faces[fi]
		var base: Vector3 = cell_to_world(face["cell"])
		var d: Vector2i = face["dir"]
		var n := Vector3(float(d.x), 0, float(d.y))
		var h: float = 0.35 if idx % 2 == 0 else 1.15
		var yaw: float = atan2(n.x, n.z)
		var basis := Basis.from_euler(Vector3(0, yaw, 0)) * Basis.from_scale(Vector3(0.09, 0.13, 0.025))
		xforms.append(Transform3D(basis, Vector3(base.x + n.x * (CELL / 2.0 - 0.02), h, base.z + n.z * (CELL / 2.0 - 0.02))))
		idx += 1
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3(1, 1, 1)
	_add_multimesh(parent, "WallPlates", unit_box, PropFactory.get_shared()["ivory"], xforms)


func _place_west_pipes(parent: Node3D) -> void:
	var pipemat: Material = PropFactory.get_shared()["metal"]
	var run_i: int = 0
	for run: Array in [[Vector3(-207.0, 2.2, 1.3), 42.0], [Vector3(-207.0, 2.2, -1.3), 42.0], [Vector3(-213.0, 2.2, -25.7), 30.0], [Vector3(-213.0, 2.2, -28.3), 30.0]]:
		var pipe := MeshInstance3D.new()
		pipe.name = "WestPipe_%d" % run_i
		var pbm := BoxMesh.new()
		pbm.size = Vector3(float(run[1]), 0.12, 0.12)
		pipe.mesh = pbm
		pipe.material_override = pipemat
		pipe.position = run[0]
		parent.add_child(pipe)
		var pipe2 := MeshInstance3D.new()
		pipe2.name = "WestPipe"
		var cbm := CylinderMesh.new()
		cbm.top_radius = 0.05
		cbm.bottom_radius = 0.05
		cbm.height = float(run[1])
		cbm.radial_segments = 10
		pipe2.mesh = cbm
		pipe2.material_override = pipemat
		pipe2.rotation.z = PI / 2.0
		pipe2.position = (run[0] as Vector3) + Vector3(0, -0.16, 0.12)
		pipe2.name = "WestPipe_c%d" % run_i
		parent.add_child(pipe2)
		run_i += 1


func _place_machine_pipes(parent: Node3D) -> void:
	# Pipe Dreams: twin pipe runs along the winding backbone tunnels.
	var pipemat: Material = PropFactory.get_shared()["metal"]
	var run_i: int = 0
	for seg: Dictionary in backbone_segs:
		var a: Vector3 = cell_to_world(seg["a"])
		var b: Vector3 = cell_to_world(seg["b"])
		var along_x: bool = absf(a.x - b.x) > absf(a.z - b.z)
		var length: float = (absf(a.x - b.x) if along_x else absf(a.z - b.z)) + CELL
		if length < 2.0:
			continue
		var mid := (a + b) * 0.5
		for side: float in [-1.3, 1.3]:
			var pipe := MeshInstance3D.new()
			pipe.name = "MachinePipe_%d" % run_i
			run_i += 1
			var pbm := BoxMesh.new()
			if along_x:
				pbm.size = Vector3(length, 0.14, 0.14)
				pipe.position = Vector3(mid.x, 2.2, mid.z + side)
			else:
				pbm.size = Vector3(0.14, 0.14, length)
				pipe.position = Vector3(mid.x + side, 2.2, mid.z)
			pipe.mesh = pbm
			pipe.material_override = pipemat
			parent.add_child(pipe)


func _apply_culling(node: Node) -> void:
	# Fog hides everything past ~40m, so stop drawing small stuff beyond that.
	# MultiMeshes (walls, panels) span the map and stay always visible.
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visibility_range_end = 45.0
		_apply_culling(child)
