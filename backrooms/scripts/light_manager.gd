class_name LightManager
extends Node3D
## Pooled real lights in a 9x9-cell window around the player (max 16),
## shadows only in the immediate 3x3, color temperature per region.
## Plus pooled positional hum and flicker events for the entity's STALK.

signal flicker_event(cell: Vector2i)

const POOL_SIZE: int = 16
const WINDOW_R: int = 4  # 9x9 cells ~= 27m
const LIGHT_RANGE: float = 7.0
const LIGHT_ENERGY: float = 1.0
const LIGHT_ATTEN: float = 0.9
const HUM_POOL: int = 8
# Region color temperature: [tint, energy multiplier]. Lobby warm, west
# neutral, service dim green, server cool blue, dark faint warm.
const REGION_LIGHT := {
	"lobby": [Color(1.0, 0.88, 0.66), 1.05],
	"west": [Color(1.0, 0.94, 0.80), 1.0],
	"service": [Color(0.84, 0.92, 0.76), 0.85],
	"server": [Color(0.76, 0.87, 1.0), 1.0],
	"dark": [Color(0.90, 0.82, 0.66), 0.55],
	"machine": [Color(0.70, 0.82, 1.0), 0.7],
}

var maze: MazeGenerator = null
var player: Player = null
var active: bool = false

var _lights: Array[OmniLight3D] = []
var _light_cells: Array[Vector2i] = []  # parallel to _lights
var _light_flicker: Array[bool] = []
var _light_phase: Array[float] = []
var _light_key: Array[Vector2] = []
var _light_gain: Array[float] = []
var _hums: Array[AudioStreamPlayer3D] = []
var _retarget_t: float = 0.0
var _flicker_t: float = 0.0
var _dim: float = 1.0
var _blackout: Dictionary = {}  # Vector2i -> true (scare director)


func setup(p_maze: MazeGenerator, p_player: Player, hum_stream: AudioStream) -> void:
	maze = p_maze
	player = p_player
	for i: int in POOL_SIZE:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.94, 0.80)
		l.light_energy = LIGHT_ENERGY
		l.omni_range = LIGHT_RANGE
		l.omni_attenuation = LIGHT_ATTEN
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)
		_light_cells.append(Vector2i(-999, -999))
		_light_flicker.append(false)
		_light_phase.append(0.0)
		_light_key.append(Vector2.ZERO)
		_light_gain.append(1.0)
	for i: int in HUM_POOL:
		var h := AudioStreamPlayer3D.new()
		h.stream = hum_stream
		h.max_distance = 14.0
		h.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		h.volume_db = -6.0
		add_child(h)
		_hums.append(h)
		if hum_stream != null:
			h.play()


func retarget_maze(p_maze: MazeGenerator) -> void:
	# Descend hook: pools survive, assignments do not.
	maze = p_maze
	_blackout.clear()
	for i: int in _lights.size():
		_light_cells[i] = Vector2i(-999, -999)
		_lights[i].visible = false
	_retarget_t = 0.0


func set_dim(f: float) -> void:
	_dim = f


func set_blackout(cell: Vector2i, on: bool) -> void:
	if on:
		_blackout[cell] = true
	else:
		_blackout.erase(cell)


func clear_blackouts() -> void:
	_blackout.clear()


func _process(delta: float) -> void:
	if not active or maze == null or player == null:
		return
	_retarget_t -= delta
	if _retarget_t <= 0.0:
		_retarget_t = 0.15
		_retarget()
	# Flickering assigned lights modulate energy (cheap: only pool members).
	var t: float = Time.get_ticks_msec() / 1000.0
	for i: int in _lights.size():
		if not _lights[i].visible:
			continue
		var e: float = LIGHT_ENERGY * _dim * _light_gain[i]
		if _light_flicker[i]:
			e *= _flicker_value(_light_phase[i], _light_key[i], t)
		if _blackout.has(_light_cells[i]):
			e = 0.0
		_lights[i].light_energy = e
	# Flicker events for the entity.
	_flicker_t -= delta
	if _flicker_t <= 0.0:
		_flicker_t = 0.4
		_emit_flicker_event()


func _retarget() -> void:
	var pc: Vector2i = maze.world_to_cell(player.global_position)
	var cands: Array[Vector2i] = []
	for dy: int in range(-WINDOW_R, WINDOW_R + 1):
		for dx: int in range(-WINDOW_R, WINDOW_R + 1):
			var c := Vector2i(pc.x + dx, pc.y + dy)
			if c.x < 0 or c.y < 0 or c.x >= MazeGenerator.GRID_W or c.y >= MazeGenerator.GRID_H:
				continue
			var st: int = maze.fixture_state[c.y * MazeGenerator.GRID_W + c.x]
			if st == MazeGenerator.F_STEADY or st == MazeGenerator.F_FLICKER:
				cands.append(c)
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _cell_dist2(a, pc) < _cell_dist2(b, pc))
	for i: int in _lights.size():
		if i < cands.size():
			var c: Vector2i = cands[i]
			_light_cells[i] = c
			var wp: Vector3 = maze.cell_to_world(c)
			_lights[i].position = Vector3(wp.x, MazeGenerator.WALL_H - 0.3, wp.z)
			_lights[i].visible = true
			var st: int = maze.fixture_state[c.y * MazeGenerator.GRID_W + c.x]
			_light_flicker[i] = st == MazeGenerator.F_FLICKER
			var rl: Array = REGION_LIGHT.get(maze.region_of(c), REGION_LIGHT["west"])
			_lights[i].light_color = rl[0]
			var key := Vector2(floor(wp.x / 3.0), floor(wp.z / 3.0))
			# Per-fixture energy variation: no two troffers burn alike.
			_light_gain[i] = float(rl[1]) * (0.9 + 0.2 * _hash12(key * 3.1 + Vector2(11.0, 5.0)))
			_light_key[i] = key
			_light_phase[i] = _hash12(key) * 100.0
			# Shadows only in the immediate 3x3.
			_lights[i].shadow_enabled = absi(c.x - pc.x) <= 1 and absi(c.y - pc.y) <= 1
		else:
			_lights[i].visible = false
			_light_cells[i] = Vector2i(-999, -999)
	# Hum emitters ride a sparse subset of the lit cells.
	var h_i: int = 0
	for i: int in range(0, cands.size(), 3):
		if h_i >= _hums.size():
			break
		var wp: Vector3 = maze.cell_to_world(cands[i])
		_hums[h_i].position = Vector3(wp.x, MazeGenerator.WALL_H - 0.4, wp.z)
		h_i += 1
	for j: int in range(h_i, _hums.size()):
		_hums[j].position = _hums[0].position if h_i > 0 else Vector3.ZERO


func _cell_dist2(a: Vector2i, b: Vector2i) -> int:
	var dx: int = a.x - b.x
	var dy: int = a.y - b.y
	return dx * dx + dy * dy


func _flicker_value(phase: float, key: Vector2, t: float) -> float:
	# Same telegraph + dropout math as the panel shader (world-hash phase
	# keeps the pooled light roughly in sync with its fixture's panel).
	var n: float = sin(t * 13.0 + phase) * sin(t * 7.3 + phase * 1.7)
	var e: float = 1.0
	if n > 0.72:
		e = 0.12
	elif n > 0.55:
		e = 0.55
	if _hash12(key + Vector2(floor(t * 0.35), 0.0)) < 0.16:
		e *= 0.05
	# Slow random kill gate: sometimes fully dark for seconds, then snaps on.
	if _hash12(key * 1.7 + Vector2(floor(t * 0.25), 3.0)) < 0.08:
		e = 0.0
	return e


func _hash12(p: Vector2) -> float:
	# CPU mirror of the shader hash12().
	var x3: float = p.x * 0.1031
	var y3: float = p.y * 0.1031
	var z3: float = p.x * 0.1031
	x3 -= floor(x3)
	y3 -= floor(y3)
	z3 -= floor(z3)
	var d: float = x3 * (y3 + 33.33) + y3 * (z3 + 33.33) + z3 * (x3 + 33.33)
	return _fract((x3 + d + y3 + d) * (z3 + d))


func _fract(v: float) -> float:
	return v - floor(v)


func _emit_flicker_event() -> void:
	var pc: Vector2i = maze.world_to_cell(player.global_position)
	var near: Array[Vector2i] = []
	for dy: int in range(-10, 11):
		for dx: int in range(-10, 11):
			var c := Vector2i(pc.x + dx, pc.y + dy)
			if c.x < 0 or c.y < 0 or c.x >= MazeGenerator.GRID_W or c.y >= MazeGenerator.GRID_H:
				continue
			if maze.fixture_state[c.y * MazeGenerator.GRID_W + c.x] == MazeGenerator.F_FLICKER:
				near.append(c)
	if near.is_empty():
		return
	flicker_event.emit(near[randi_range(0, near.size() - 1)])
