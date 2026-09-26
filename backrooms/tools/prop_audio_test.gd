extends SceneTree
## Headless contract checks; restores the user's config byte-for-byte.
var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("FAIL prop_audio: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var path := "user://audio.cfg"
	var existed := FileAccess.file_exists(path)
	var saved := FileAccess.get_file_as_bytes(path) if existed else PackedByteArray()
	var bus_count := AudioServer.bus_count
	var audio := AudioManager.new()
	root.add_child(audio)
	var original_volume := audio.get_master_volume()
	var room := AudioServer.get_bus_index(AudioManager.ROOM_BUS)
	check(room > 0 and AudioServer.get_bus_effect_count(room) == 2, "room effects")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(AudioManager.STEP_BUS)) == AudioManager.ROOM_BUS, "step routing")
	var props: Array[Node3D] = [PropFactory.build_chair(), PropFactory.build_cabinet(), PropFactory.build_cooler(), PropFactory.build_desk(null), PropFactory.build_server_rack(StandardMaterial3D.new()), PropFactory.build_crate(), PropFactory.build_cone(), PropFactory.build_exit_sign(), PropFactory.build_gateway(StandardMaterial3D.new()), PropFactory.build_exit_door(), PropFactory.build_pickup("water", audio.gulp_stream), PropFactory.build_pickup("bread", audio.thunk_stream)]
	for prop: Node3D in props:
		check(prop.get_child_count() >= 3, "geometry " + prop.name)
		root.add_child(prop)
	var door := PropFactory.build_fake_door(audio.thunk_stream)
	root.add_child(door)
	check(door is FakeDoor, "door contract")
	check((door.get_child(0) as CollisionShape3D).shape.size == Vector3(1.1, 2.2, 0.18), "door collider")
	await process_frame
	var foley: AudioStreamPlayer3D = (door as FakeDoor)._thunk
	check(foley.bus == AudioManager.ROOM_BUS, "3D routing")
	seed(812)
	var expected := randi()
	seed(812)
	door.interact()
	check(randi() == expected, "door consumed global RNG")
	check(foley.pitch_scale >= 0.98 and foley.pitch_scale <= 1.021, "door pitch")
	var pitch := foley.pitch_scale
	door.interact()
	check(foley.pitch_scale == pitch, "door cooldown")
	var player := AudioStreamPlayer.new()
	root.add_child(player)
	var sequence: Array[float] = []
	for repeat: int in 2:
		audio._step_count = 0
		var last: AudioStream = null
		for i: int in 12:
			seed(99)
			expected = randi()
			seed(99)
			audio.play_step(0.7, player)
			check(randi() == expected, "step consumed global RNG")
			check(player.stream != last, "consecutive step repeat")
			last = player.stream
			if repeat == 0:
				sequence.append(player.pitch_scale)
			else:
				check(player.pitch_scale == sequence[i], "deterministic pitch")
	check(player.bus == AudioManager.STEP_BUS, "step bus")
	for district: String in AudioManager.ACOUSTICS:
		audio._district = district
		audio._process(10.0)
		var target: Vector4 = AudioManager.ACOUSTICS[district]
		check(absf(audio._reverb.wet - target.x) < 0.001, "reverb " + district)
		check(absf(audio._lowpass.cutoff_hz - target.w) < 1.0, "lowpass " + district)
	audio.set_master_volume(0.4)
	check(is_equal_approx(audio.get_master_volume(), 0.4), "volume API")
	var config := ConfigFile.new()
	check(config.load(path) == OK and is_equal_approx(float(config.get_value("audio", "master_volume", -1)), 0.4), "volume persistence")
	audio.set_master_volume(0.0)
	check(AudioServer.is_bus_mute(0), "mute")
	audio.set_master_volume(NAN)
	check(audio.get_master_volume() == 0.0, "invalid volume")
	audio.set_master_volume(4.0)
	check(audio.get_master_volume() == 1.0 and not AudioServer.is_bus_mute(0), "volume clamp")
	check(audio._drone_levels.size() == 3, "three level drones")
	check(audio._drone_levels[0] != audio._drone_levels[1] and audio._drone_levels[1] != audio._drone_levels[2], "drones distinct per level")
	audio.set_level_ambience(2)
	check(audio._drone_player.stream == audio._drone_levels[2], "ambience switches to L2 bed")
	audio.set_level_ambience(9)
	check(audio._drone_player.stream == audio._drone_levels[2], "ambience clamps level")
	for prop: Node3D in props:
		prop.free()
	door.free()
	player.free()
	audio.free()
	check(AudioServer.bus_count == bus_count, "bus cleanup")
	var reload_audio := AudioManager.new()
	root.add_child(reload_audio)
	check(reload_audio.get_master_volume() == 1.0, "volume reload")
	reload_audio.set_master_volume(original_volume)
	reload_audio.free()
	if existed:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	else:
		DirAccess.remove_absolute(path)
	check(AudioServer.bus_count == bus_count, "reload bus cleanup")
	if failures == 0:
		print("PROP_AUDIO TEST: ALL PASS")
	quit(0 if failures == 0 else 1)
