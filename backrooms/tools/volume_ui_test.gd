extends SceneTree
## Production UI contract; no world generation or gameplay save writes.
## Always restore audio.cfg bytes (or absence) and the original Master bus state.
const PATH := "user://audio.cfg"
var failures: int = 0
var assertions: int = 0
var main: Node
var existed: bool
var saved: PackedByteArray
var original_db: float
var original_mute: bool
var signals_seen: Array[int] = [0, 0]
var finished: bool = false

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: volume_ui " + message)

func _boot() -> void:
	GameManager.pending_seed = -1
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	# No generated world is needed to exercise the real solo pause transition.
	main.game.set_process(false)
	main.player.set_physics_process(false)
	main.entity.set_physics_process(false)

func _state(expected: float, context: String) -> void:
	var ui: UIManager = main.ui
	check(is_equal_approx(main.audio.get_master_volume(), expected), context + " API")
	var bus: int = AudioServer.get_bus_index("Master")
	var linear: float = maxf(expected, 0.0001)
	check(absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(linear)) < 0.001, context + " Master dB")
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(bus)) - linear) < 0.00001, context + " Master linear gain")
	check(AudioServer.is_bus_mute(bus) == (expected == 0.0), context + " Master mute")
	var config := ConfigFile.new()
	check(config.load(PATH) == OK, context + " config readable")
	check(is_equal_approx(float(config.get_value("audio", "master_volume", -1.0)), expected), context + " persisted volume")
	check(config.get_value("volume_ui_test", "sentinel", "") == "preserve", context + " unrelated config entry")
	for i: int in 2:
		check(is_equal_approx(ui._volume_sliders[i].value, expected), context + " slider %d" % i)
		var text: String = "0% (muted)" if expected == 0.0 else "%d%%" % roundi(expected * 100.0)
		check(ui._volume_readouts[i].text == text, context + " readout %d" % i)

func _key(slider: HSlider, code: Key) -> void:
	slider.grab_focus()
	check(slider.has_focus(), "slider accepts focus")
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	event = InputEventKey.new()
	event.keycode = code
	root.push_input(event)

func _run() -> void:
	existed = FileAccess.file_exists(PATH)
	if existed:
		var file := FileAccess.open(PATH, FileAccess.READ)
		if file == null:
			check(false, "cannot back up original config; abort without writing")
			quit(1)
			return
		saved = file.get_buffer(file.get_length())
		file.close()
	var bus: int = AudioServer.get_bus_index("Master")
	original_db = AudioServer.get_bus_volume_db(bus)
	original_mute = AudioServer.is_bus_mute(bus)
	create_timer(30.0).timeout.connect(func() -> void:
		if not finished:
			check(false, "30 second watchdog")
			_finish())
	var fixture := ConfigFile.new()
	fixture.set_value("audio", "master_volume", 0.375)
	fixture.set_value("volume_ui_test", "sentinel", "preserve")
	if fixture.save(PATH) != OK:
		check(false, "write temporary config")
		_finish()
		return
	var fixture_bytes := FileAccess.get_file_as_bytes(PATH)
	_boot()
	await process_frame
	await process_frame
	var ui: UIManager = main.ui
	check(ui._volume_sliders.size() == 2 and ui._volume_readouts.size() == 2, "both production rows built")
	if ui._volume_sliders.size() != 2 or ui._volume_readouts.size() != 2:
		_finish()
		return
	var menu: HSlider = ui._volume_sliders[0]
	var pause_slider: HSlider = ui._volume_sliders[1]
	check(ui._menu.is_ancestor_of(menu) and ui._pause.is_ancestor_of(pause_slider), "controls belong to menu and pause")
	check(menu.is_visible_in_tree() and not pause_slider.is_visible_in_tree(), "startup menu visibility")
	_state(0.375, "saved fractional initialization")
	check(FileAccess.get_file_as_bytes(PATH) == fixture_bytes, "initialization does not rewrite saved config")
	menu.value_changed.connect(func(_v: float) -> void: signals_seen[0] += 1)
	pause_slider.value_changed.connect(func(_v: float) -> void: signals_seen[1] += 1)
	menu.value = 0.42
	_state(0.42, "menu value change")
	check(signals_seen == [1, 0], "menu change emits once; counterpart emits nothing")
	_key(menu, KEY_HOME)
	_state(0.0, "menu Home mutes")
	check(signals_seen == [2, 0], "menu input no signal loop")
	main.game.state = GameManager.GState.PLAYING
	ui.show_hud(0)
	main.game.pause()
	await process_frame
	await process_frame
	check(paused and main.game.state == GameManager.GState.PAUSED, "production solo pause pauses tree")
	check(pause_slider.is_visible_in_tree() and pause_slider.can_process(), "pause slider visible and processes while paused")
	check(not main.player.can_process(), "simulation remains paused")
	_key(pause_slider, KEY_END)
	_state(1.0, "paused End unmutes")
	check(signals_seen == [2, 1], "paused input emits once; menu sync silent")
	pause_slider.value = 0.63
	_state(0.63, "pause value change")
	check(signals_seen == [2, 2], "pause change no signal loop")
	_key(pause_slider, KEY_HOME)
	_state(0.0, "paused Home mutes")
	check(signals_seen == [2, 3], "paused mute no signal loop")
	main.game.resume()
	main.game.state = GameManager.GState.MENU
	main.player.active = false
	ui.show_menu()
	_state(0.0, "menu reopen retains mute")
	check(not paused and signals_seen == [2, 3], "resume and reopen do not emit volume signals")
	main.free()
	_boot()
	await process_frame
	_state(0.0, "fresh production scene restores saved mute")
	main.ui._volume_sliders[0].value = 0.58
	_state(0.58, "fresh scene menu unmutes")
	main.free()
	_boot()
	await process_frame
	_state(0.58, "fresh production scene restores nonzero setting")
	_finish()

func _finish() -> void:
	if finished:
		return
	finished = true
	paused = false
	if is_instance_valid(main):
		main.free()
	if existed:
		var file := FileAccess.open(PATH, FileAccess.WRITE)
		check(file != null, "open original config for restoration")
		if file != null:
			file.store_buffer(saved)
			file.close()
		check(FileAccess.get_file_as_bytes(PATH) == saved, "original config restored byte-for-byte")
	else:
		if FileAccess.file_exists(PATH):
			check(DirAccess.remove_absolute(PATH) == OK, "remove temporary config")
		check(not FileAccess.file_exists(PATH), "original config absence restored")
	var bus: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, original_db)
	AudioServer.set_bus_mute(bus, original_mute)
	check(is_equal_approx(AudioServer.get_bus_volume_db(bus), original_db) and AudioServer.is_bus_mute(bus) == original_mute, "original Master bus state restored")
	print("VOLUME_UI TEST: %s (%d assertions)" % ["ALL PASS" if failures == 0 else "%d FAILED" % failures, assertions])
	quit(0 if failures == 0 else 1)
