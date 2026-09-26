class_name AudioManager
extends Node
## CC0 file slots in assets/ + fully synthesized fallback.
## Fallback sounds are baked to AudioStreamWAV once at startup (pure math,
## no per-frame cost). Loops use integer cycle counts so they click-free loop.

const RATE: int = 22050

var hum_stream: AudioStream
var drone_stream: AudioStream
var step_stream: AudioStream
var screech_stream: AudioStream
var thunk_stream: AudioStream
var creak_stream: AudioStream
var gulp_stream: AudioStream
var drag_stream: AudioStream
var beacon_stream: AudioStream

var _death_player: AudioStreamPlayer
var _win_player: AudioStreamPlayer
var _drone_player: AudioStreamPlayer
var _drone_levels: Array[AudioStream] = []
var _amb_level: int = -1
var _steps: Array[AudioStream] = []
var _last_step: int = -1
var _step_count: int = 0
var _master_volume: float = 1.0
var _reverb: AudioEffectReverb
var _lowpass: AudioEffectLowPassFilter
var _pan: AudioEffectPanner
var _district: String = "west"
var _poll: float = 0.0
var _owned_buses: Array[StringName] = []

const AUDIO_CONFIG := "user://audio.cfg"
const ROOM_BUS := &"BackroomsRoom"
const STEP_BUS := &"BackroomsSteps"
# Wet amount, room size, damping, low-pass cutoff. Dry signal stays dominant.
const ACOUSTICS := {
	"west": Vector4(0.07, 0.35, 0.75, 15000.0),
	"lobby": Vector4(0.12, 0.60, 0.60, 17000.0),
	"service": Vector4(0.19, 0.72, 0.42, 14000.0),
	"server": Vector4(0.09, 0.42, 0.80, 11000.0),
	"dark": Vector4(0.13, 0.55, 0.85, 9000.0),
}


func get_master_volume() -> float:
	return _master_volume


# Linear 0..1, including true mute. Invalid input leaves the current mix intact.
func set_master_volume(value: float) -> void:
	if not is_finite(value):
		return
	_master_volume = clampf(value, 0.0, 1.0)
	_apply_master_volume()
	var config := ConfigFile.new()
	config.load(AUDIO_CONFIG)
	config.set_value("audio", "master_volume", _master_volume)
	var result: Error = config.save(AUDIO_CONFIG)
	if result != OK:
		push_warning("AudioManager: cannot save volume (%s)" % error_string(result))


func _apply_master_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(_master_volume, 0.0001)))
	AudioServer.set_bus_mute(0, _master_volume <= 0.0)


func _make_bus(bus_name: StringName, send: StringName) -> int:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, send)
		_owned_buses.append(bus_name)
	return index


func _setup_acoustics() -> void:
	# These names are private to this manager; no project bus layout is changed.
	var room: int = _make_bus(ROOM_BUS, &"Master")
	if _owned_buses.has(ROOM_BUS):
		_reverb = AudioEffectReverb.new()
		_reverb.dry = 1.0
		_reverb.wet = 0.07
		_reverb.room_size = 0.35
		_reverb.damping = 0.75
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = 15000.0
		AudioServer.add_bus_effect(room, _reverb)
		AudioServer.add_bus_effect(room, _lowpass)
	var steps: int = _make_bus(STEP_BUS, ROOM_BUS)
	if _owned_buses.has(STEP_BUS):
		_pan = AudioEffectPanner.new()
		AudioServer.add_bus_effect(steps, _pan)


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.2
		var game := get_tree().get_first_node_in_group("game")
		if game != null:
			var maze = game.get("maze")
			var listener = game.get("player")
			if maze != null and is_instance_valid(listener) and listener.is_inside_tree():
				_district = maze.region_of(maze.world_to_cell(listener.global_position))
	if _reverb != null and _lowpass != null:
		var target: Vector4 = ACOUSTICS.get(_district, ACOUSTICS["west"])
		var blend: float = 1.0 - exp(-delta * 3.0)
		_reverb.wet = lerpf(_reverb.wet, target.x, blend)
		_reverb.room_size = lerpf(_reverb.room_size, target.y, blend)
		_reverb.damping = lerpf(_reverb.damping, target.z, blend)
		_lowpass.cutoff_hz = lerpf(_lowpass.cutoff_hz, target.w, blend)


func _route_audio(node: Node) -> void:
	# Deferred node-added hook sees streams assigned after add_child too.
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node is AudioStreamPlayer3D and node.bus == &"Master":
		node.bus = ROOM_BUS


func _exit_tree() -> void:
	# Child players leave with the scene; remove only buses this instance created.
	_owned_buses.reverse()
	for bus_name: StringName in _owned_buses:
		var index: int = AudioServer.get_bus_index(bus_name)
		if index > 0:
			AudioServer.remove_bus(index)
	_owned_buses.clear()


func _ready() -> void:
	add_to_group("audio")
	var config := ConfigFile.new()
	if config.load(AUDIO_CONFIG) == OK:
		var saved = config.get_value("audio", "master_volume", 1.0)
		if (saved is float or saved is int) and is_finite(float(saved)):
			_master_volume = clampf(float(saved), 0.0, 1.0)
	_apply_master_volume()
	_setup_acoustics()
	get_tree().node_added.connect(_route_audio, CONNECT_DEFERRED)
	hum_stream = _slot_or_synth("hum_loop", _synth_hum)
	drone_stream = _slot_or_synth("drone_loop", _synth_drone)
	_drone_levels = [
		drone_stream,
		_slot_or_synth("drone_loop_l1", _synth_drone_l1),
		_slot_or_synth("drone_loop_l2", _synth_drone_l2),
	]
	screech_stream = _slot_or_synth("screech", _synth_screech)
	thunk_stream = _slot_or_synth("thunk", _synth_thunk)
	creak_stream = _slot_or_synth("creak", _synth_creak)
	gulp_stream = _slot_or_synth("gulp", _synth_gulp)
	drag_stream = _slot_or_synth("drag", _synth_drag)
	beacon_stream = _slot_or_synth("beacon_loop", _synth_beacon)
	for index: int in 6:
		_steps.append(_slot_or_synth("step_%d" % index, _synth_step))
	step_stream = _steps[0]
	_death_player = AudioStreamPlayer.new()
	_death_player.stream = screech_stream
	_death_player.volume_db = 2.0
	add_child(_death_player)
	_win_player = AudioStreamPlayer.new()
	_win_player.stream = creak_stream
	add_child(_win_player)
	_drone_player = AudioStreamPlayer.new()
	_drone_player.stream = drone_stream
	_drone_player.bus = ROOM_BUS
	_drone_player.volume_db = -14.0
	add_child(_drone_player)


func start_ambience() -> void:
	if not _drone_player.playing:
		_drone_player.play()


func stop_ambience() -> void:
	_drone_player.stop()


func set_level_ambience(level: int) -> void:
	var lv: int = clampi(level, 0, 2)
	if lv == _amb_level or _drone_levels.size() < 3:
		return
	_amb_level = lv
	var was_playing: bool = _drone_player.playing
	_drone_player.stream = _drone_levels[lv]
	if was_playing:
		_drone_player.play()


func play_step(intensity: float, player: AudioStreamPlayer) -> void:
	if not is_instance_valid(player) or _steps.is_empty():
		return
	# Coprime stride visits all six original takes, never repeating consecutively.
	# Independent of global RNG: sound must not perturb maze/scare simulation.
	var next: int = (_step_count * 5 + 2) % _steps.size()
	_last_step = next
	player.stream = _steps[next]
	player.bus = STEP_BUS
	player.pitch_scale = 0.98 + float((_step_count * 3) % 5) * 0.01
	player.volume_db = lerpf(-14.0, -4.0, clampf(intensity, 0.0, 1.0)) - float(_step_count % 3) * 0.2
	if _pan != null:
		_pan.pan = -0.065 if _step_count % 2 == 0 else 0.065
	_step_count += 1
	player.play()


func play_death() -> void:
	stop_ambience()
	_death_player.play()


func play_win() -> void:
	_win_player.play()


func _slot_or_synth(base: String, synth: Callable) -> AudioStream:
	var baked_path: String = "res://assets/audio/%s.wav" % base
	if ResourceLoader.exists(baked_path):
		var baked := load(baked_path) as AudioStreamWAV
		if baked != null:
			if base.ends_with("_loop"):
				baked.loop_mode = AudioStreamWAV.LOOP_FORWARD
				baked.loop_begin = 0
				baked.loop_end = int(baked.get_length() * baked.mix_rate)
			print("AudioManager: using %s" % baked_path)
			return baked
	for ext: String in ["ogg", "wav"]:
		var path: String = "res://assets/%s.%s" % [base, ext]
		if FileAccess.file_exists(path):
			var s: AudioStream = load(path) as AudioStream
			if s != null:
				print("AudioManager: using %s" % path)
				return s
			push_warning("AudioManager: present but unloadable: %s" % path)
	return synth.call() as AudioStream


# ------------------------------------------------------------- synthesizers

func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in samples.size():
		var v: int = int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		if v < 0:
			v += 65536
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _synth_beacon() -> AudioStreamWAV:
	# 6s exit beacon: soft 520/780Hz pair breathing at 0.5Hz. All integer
	# cycles so the loop has no click. Warm, faintly hopeful, audible ~30m.
	var n: int = RATE * 6
	var s := PackedFloat32Array()
	s.resize(n)
	for i: int in n:
		var t: float = float(i) / float(RATE)
		var v: float = 0.22 * sin(TAU * 520.0 * t)
		v += 0.14 * sin(TAU * 780.0 * t + 0.4)
		v += 0.05 * sin(TAU * 1040.0 * t + 1.1)
		v *= 0.55 + 0.45 * sin(TAU * 0.5 * t)
		s[i] = v * 0.4
	return _to_wav(s, true)


func _synth_hum() -> AudioStreamWAV:
	# 4s ballast hum: 120Hz + harmonics, 0.25Hz breathing. All integer cycles.
	var n: int = RATE * 4
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in n:
		var t: float = float(i) / float(RATE)
		var v: float = 0.30 * sin(TAU * 120.0 * t)
		v += 0.12 * sin(TAU * 240.0 * t + 0.7)
		v += 0.05 * sin(TAU * 360.0 * t + 1.9)
		v += 0.02 * (rng.randf() * 2.0 - 1.0)
		v *= 0.85 + 0.15 * sin(TAU * 0.25 * t)
		s[i] = v * 0.5
	return _to_wav(s, true)


func _synth_drone() -> AudioStreamWAV:
	# 8s room-tone dread bed. Integer cycles: 55*8, 82.5*8.
	var n: int = RATE * 8
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var lp: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(RATE)
		var v: float = 0.25 * sin(TAU * 55.0 * t)
		v += 0.14 * sin(TAU * 82.5 * t + 1.1)
		lp = lp * 0.985 + (rng.randf() * 2.0 - 1.0) * 0.015
		v += lp * 2.2
		v *= 0.8 + 0.2 * sin(TAU * 0.125 * t + 0.5)
		s[i] = v * 0.5
	return _to_wav(s, true)


func _synth_drone_l1() -> AudioStreamWAV:
	# 8s hollow concrete bed: 49/73.5Hz pair, slow breathing, airy wash.
	# Integer cycles (392/588) so the loop has no click.
	var n: int = RATE * 8
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var lp: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(RATE)
		var v: float = 0.22 * sin(TAU * 49.0 * t)
		v += 0.12 * sin(TAU * 73.5 * t + 0.6)
		lp = lp * 0.978 + (rng.randf() * 2.0 - 1.0) * 0.022
		v += lp * 2.6
		v *= 0.75 + 0.25 * sin(TAU * 0.125 * t + 2.1)
		s[i] = v * 0.5
	return _to_wav(s, true)


func _synth_drone_l2() -> AudioStreamWAV:
	# 8s cold machine bed: 62.5/93.75Hz pair plus a faint 125Hz whine.
	# Integer cycles (500/750/1000) so the loop has no click.
	var n: int = RATE * 8
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var lp: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(RATE)
		var v: float = 0.20 * sin(TAU * 62.5 * t)
		v += 0.11 * sin(TAU * 93.75 * t + 2.4)
		v += 0.04 * sin(TAU * 125.0 * t + 0.9)
		lp = lp * 0.988 + (rng.randf() * 2.0 - 1.0) * 0.012
		v += lp * 1.8
		v *= 0.85 + 0.15 * sin(TAU * 0.25 * t + 4.0)
		s[i] = v * 0.5
	return _to_wav(s, true)


func _synth_step() -> AudioStreamWAV:
	# 0.18s muffled carpet thud.
	var n: int = int(float(RATE) * 0.18)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var lp: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(RATE)
		var env: float = exp(-t * 34.0)
		lp = lp * 0.92 + (rng.randf() * 2.0 - 1.0) * 0.08
		s[i] = (lp * 3.0 + 0.5 * sin(TAU * 70.0 * t) * exp(-t * 22.0)) * env
	return _to_wav(s, false)


func _synth_screech() -> AudioStreamWAV:
	# 1.2s detuned metallic wail with pitch fall.
	var n: int = int(float(RATE) * 1.2)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var phase1: float = 0.0
	var phase2: float = 0.0
	var phase3: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(RATE)
		var sweep: float = 1.0 - 0.35 * (t / 1.2)
		phase1 += TAU * 600.0 * sweep / float(RATE)
		phase2 += TAU * 623.0 * sweep / float(RATE)
		phase3 += TAU * 1213.0 * sweep / float(RATE)
		var v: float = 0.30 * sign(sin(phase1)) + 0.30 * sign(sin(phase2)) + 0.18 * sign(sin(phase3))
		v += 0.25 * (rng.randf() * 2.0 - 1.0)
		var env: float = minf(t / 0.03, 1.0) * exp(-t * 1.6)
		s[i] = v * env * 0.4
	return _to_wav(s, false)


func _synth_thunk() -> AudioStreamWAV:
	# 0.25s dull door knock.
	var n: int = int(float(RATE) * 0.25)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in n:
		var t: float = float(i) / float(RATE)
		var v: float = 0.8 * sin(TAU * 90.0 * t) * exp(-t * 26.0)
		v += 0.3 * (rng.randf() * 2.0 - 1.0) * exp(-t * 90.0)
		s[i] = v * 0.7
	return _to_wav(s, false)


func _synth_creak() -> AudioStreamWAV:
	# 0.9s exit-door creak: groaning stick-slip sweep.
	var n: int = int(float(RATE) * 0.9)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(RATE)
		var f: float = 200.0 - 110.0 * (t / 0.9)
		phase += TAU * f * (1.0 + 0.3 * sin(TAU * 13.0 * t)) / float(RATE)
		var v: float = sin(phase) + 0.4 * sin(phase * 2.02) + 0.2 * sin(phase * 0.5)
		var env: float = sin(PI * clampf(t / 0.9, 0.0, 1.0))
		s[i] = v * env * 0.25
	return _to_wav(s, false)


func _synth_gulp() -> AudioStreamWAV:
	# 0.35s drink: three descending glugs.
	var n: int = int(float(RATE) * 0.35)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(RATE)
		var f: float = 300.0 - 160.0 * (t / 0.35)
		phase += TAU * f / float(RATE)
		var gate: float = 0.5 + 0.5 * sin(TAU * 9.0 * t)
		s[i] = sin(phase) * gate * gate * 0.5
	return _to_wav(s, false)


func _synth_drag() -> AudioStreamWAV:
	# 0.5s heavy foot-drag scrape for the entity's stride.
	var n: int = int(float(RATE) * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var lp: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(RATE)
		lp = lp * 0.94 + (rng.randf() * 2.0 - 1.0) * 0.06
		var env: float = minf(t / 0.06, 1.0) * exp(-t * 4.5)
		s[i] = (lp * 4.0 + 0.3 * sin(TAU * 58.0 * t)) * env * 0.6
	return _to_wav(s, false)
