class_name UIManager
extends CanvasLayer
## All UI is built in code: VHS overlay + REC chrome, HUD, menu, pause,
## win/death screens. process_mode ALWAYS so pause menus work while paused.

var game: GameManager = null
var player: Player = null
var entity: Stalker = null
var net: Node = null  # NetManager, untyped to avoid load-order coupling

var _vhs_layer: CanvasLayer
var _vhs_mat: ShaderMaterial
var _rec_label: Label
var _clock_base: int = 0  # seconds since 02:00:00 at run start
var _hud: Control
var _objective_label: Label
var _stamina_bar: ProgressBar
var _flash_label: Label
var _food_bar: ProgressBar
var _water_bar: ProgressBar
var _fps_label: Label
var _seed_label: Label
var _time_label: Label
var _fps_t: float = 0.0
var _menu: CenterContainer
var _seed_edit: LineEdit
var _sens_slider: HSlider
var _fov_slider: HSlider
var _preset_opt: OptionButton
var _best_label: Label
var _start_btn: Button
var _mp_status: Label
var _join_edit: LineEdit
var _pause: CenterContainer
var _pause_restart: Button
var _pause_sens: HSlider
var _pause_fov: HSlider
var _pause_vhs: CheckBox
var _intro_label: Label
var _intro_t: float = 0.0
var _hunt_flash: ColorRect
var _hunt_t: float = 0.0
var _vignette: TextureRect
var _volume_sliders: Array[HSlider] = []
var _volume_readouts: Array[Label] = []
var _end: CenterContainer
var _end_title: Label
var _end_sub: Label
var _end_stats: Label
var _end_row: HBoxContainer
var _coop_label: Label
var _spect: CenterContainer
var _spect_label: Label
var _loading: CenterContainer
var _inv: CenterContainer
var _inv_water_l: Label
var _inv_bread_l: Label
var _inv_hud: Label
var _loading_stage: Label
var _burst: float = 0.0
var _burst_decay: float = 1.0
var _crosshair: Label
var _interact_prompt: Label

const INK := Color("131510")
const PAPER := Color("e7dfc9")
const AMBER := Color("c9a66b")
const MUTED := Color("aaa58f")


func _sync_settings_controls() -> void:
	if game == null:
		return
	_sens_slider.set_value_no_signal(game.sensitivity)
	_pause_sens.set_value_no_signal(game.sensitivity)
	_fov_slider.set_value_no_signal(game.fov)
	_pause_fov.set_value_no_signal(game.fov)
	_preset_opt.select(0 if game.preset == "High" else 1)
	_pause_vhs.set_pressed_no_signal(game.vhs_enabled)
	_sync_volume_controls()


func _sync_volume_controls() -> void:
	if game == null or game.audio == null:
		return
	var volume: float = game.audio.get_master_volume()
	for slider: HSlider in _volume_sliders:
		# Preserve saved fractional values; syncing must never save or emit again.
		slider.set_value_no_signal(volume)
	for readout: Label in _volume_readouts:
		readout.text = "0% (muted)" if volume <= 0.0 else "%d%%" % roundi(volume * 100.0)


func _on_volume_changed(value: float) -> void:
	if game == null or game.audio == null:
		return
	game.audio.set_master_volume(value)
	_sync_volume_controls()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_interact_prompt) or not is_instance_valid(_crosshair):
		return
	_interact_prompt.text = ""
	_crosshair.visible = _hud.visible and not _pause.visible and not _inv.visible and player != null and player.active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not _crosshair.visible:
		return
	var hit: Dictionary = player.interaction_hit()
	if hit.is_empty():
		return
	var target: Object = hit["collider"]
	# Campaign owns its objectives, journal and contextual prompts.
	if target is Pickup:
		_interact_prompt.text = "[E]  TAKE " + ("ALMOND WATER" if target.kind == "water" else "DRY BREAD")
	elif target is FakeDoor:
		_interact_prompt.text = "[E]  TRY DOOR"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_vhs()
	_build_hud()
	_build_menu()
	_build_pause()
	_build_end()
	_build_loading()
	_build_inventory()
	_build_spectate()
	_hud.visible = false
	_menu.visible = false
	_pause.visible = false
	_end.visible = false
	_spect.visible = false
	_coop_label.visible = false


func setup(p_game: GameManager, p_player: Player, p_entity: Stalker, p_net: Node = null) -> void:
	game = p_game
	player = p_player
	entity = p_entity
	net = p_net
	_sync_settings_controls()


func _process(delta: float) -> void:
	if _burst > 0.0:
		_burst = maxf(0.0, _burst - delta * _burst_decay)
	var hunting: bool = entity != null and entity.state == Stalker.State.HUNT and game != null and game.is_playing()
	var grain: float = 0.10
	if player != null and entity != null and game != null and game.is_playing():
		var d: float = player.global_position.distance_to(entity.global_position)
		if d < 18.0:
			grain += 0.30 * (1.0 - d / 18.0)
		if game.thirst <= 0.0:
			grain += 0.15
	_vhs_mat.set_shader_parameter("grain", grain)
	_vhs_mat.set_shader_parameter("tracking", 0.7 if hunting else 0.35)
	_vhs_mat.set_shader_parameter("burst", _burst)
	if _intro_t > 0.0:
		_intro_t -= delta
		if _intro_t <= 0.0:
			_intro_label.visible = false
	if _hunt_t > 0.0:
		_hunt_t = maxf(0.0, _hunt_t - delta)
		_hunt_flash.color.a = 0.20 * (_hunt_t / 1.2)
	if _hud.visible and game != null:
		_time_label.text = _fmt_time(game.elapsed)
		_fps_t += delta
		if _fps_t >= 0.5:
			_fps_t = 0.0
			_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
		_rec_label.text = "REC ● 1996-03-14 " + _fmt_clock(game.elapsed)
		if player != null:
			_stamina_bar.value = player.stamina
			_flash_label.text = "FLASH READY [F]" if player.flash_ready_frac() >= 1.0 else "FLASH ..."
		_food_bar.value = game.hunger
		_water_bar.value = game.thirst
		_food_bar.modulate = Color(1, 0.35, 0.3) if game.hunger < 0.25 else Color.WHITE
		_water_bar.modulate = Color(1, 0.35, 0.3) if game.thirst < 0.25 else Color.WHITE
		_inv_hud.text = "W:%d B:%d GLOW:%d [R]" % [game.inv_water, game.inv_bread, game.glowsticks]


func static_burst(dur: float) -> void:
	_burst = 1.0
	_burst_decay = 1.0 / maxf(dur, 0.05)


func hunt_flash() -> void:
	# Red pulse on the hunt, independent of the VHS overlay toggle.
	_hunt_t = 1.2


func set_vhs_enabled(b: bool) -> void:
	_vhs_layer.visible = b


func show_hud(seed_value: int) -> void:
	_menu.visible = false
	_loading.visible = false
	_pause.visible = false
	_end.visible = false
	_inv.visible = false
	_spect.visible = false
	_hud.visible = true
	_intro_label.visible = true
	_intro_t = 7.0
	_hunt_t = 0.0
	_hunt_flash.color.a = 0.0
	_objective_label.visible = get_tree().current_scene.get_node_or_null("Campaign") == null
	_seed_label.text = "SEED %d" % seed_value
	_coop_label.visible = net != null and net.is_mp()


func show_level_banner(level_name: String) -> void:
	_intro_label.text = "%s\nThe way back is gone. Keep moving." % level_name
	_intro_label.visible = true
	_intro_t = 7.0


func show_menu() -> void:
	_sync_settings_controls()
	_inv.visible = false
	_hud.visible = false
	_loading.visible = false
	_pause.visible = false
	_end.visible = false
	_spect.visible = false
	_menu.visible = true
	_seed_edit.text = str(game.last_seed) if game != null else "0"
	_best_label.text = _best_text()
	_start_btn.disabled = false
	set_mp_status(NetManager.last_note)
	NetManager.last_note = ""
	# Rejoin support: a scene reload while hosting/joining re-arms the session.
	var p: Dictionary = NetManager.take_pending()
	if not p.is_empty() and net != null:
		if p["mode"] == "host":
			var err: String = net.host_game()
			set_mp_status("Hosting again on %s — waiting for your partner..." % net.local_ip() if err == "" else err)
		elif p["mode"] == "client":
			var jerr: String = net.join_game(p["ip"])
			set_mp_status("Reconnecting..." if jerr == "" else jerr)


func show_loading(stage: String) -> void:
	_menu.visible = false
	_pause.visible = false
	_end.visible = false
	_hud.visible = false
	_loading.visible = true
	set_loading_stage(stage)


func set_loading_stage(stage: String) -> void:
	_loading_stage.text = stage


func show_pause() -> void:
	_sync_settings_controls()
	_pause_restart.visible = net == null or not net.is_mp()
	_pause.visible = true


func show_death(cause: String, seed_value: int, elapsed: float) -> void:
	_hud.visible = false
	_inv.visible = false
	_spect.visible = false
	_end.visible = true
	_end_row.visible = true
	_end_title.text = "SIGNAL LOST"
	if cause == "caught":
		_end_sub.text = "Answered. It finished learning you."
	elif cause == "collapsed":
		_end_title.text = "SIGNAL LOST"
		_end_sub.text = "You collapsed in the humming dark. Eat. Drink."
	else:
		_end_sub.text = "You are gone."
	_end_stats.text = "Survived %s   ·   Seed %d" % [_fmt_time(elapsed), seed_value]


func show_win(ms: int, seed_value: int) -> void:
	_hud.visible = false
	_inv.visible = false
	_spect.visible = false
	_end.visible = true
	_end_row.visible = true
	_end_title.text = "ESCAPED"
	_end_sub.text = "You found the exit. It watched you leave."
	var scraps: int = 0
	var camp: Node = get_tree().current_scene.get_node_or_null("Campaign")
	if camp != null and camp.get("scrap_journal") != null:
		scraps = (camp.get("scrap_journal") as Array).size()
	_end_stats.text = "Time %s   ·   Seed %d   ·   Notes %d/6" % [_fmt_time(float(ms) / 1000.0), seed_value, scraps]
	if game != null and ms <= game.best_time_ms:
		_end_stats.text += "   ·   NEW BEST"


func set_mp_status(text: String) -> void:
	if _mp_status == null:
		return
	_mp_status.text = text
	_mp_status.visible = text != ""


func coop_note(text: String) -> void:
	# Transient co-op line above the HUD objective.
	if _coop_label == null:
		return
	_coop_label.text = text
	_coop_label.visible = true


func show_spectate(on: bool) -> void:
	_spect.visible = on


func show_mp_down(cause: String, seed_value: int, elapsed: float) -> void:
	_hud.visible = false
	_inv.visible = false
	_end.visible = true
	_end_row.visible = false
	_end_title.text = "SIGNAL LOST"
	_end_sub.text = "It touched you." if cause == "caught" else "You collapsed in the humming dark."
	_end_stats.text = "Survived %s   ·   Seed %d   ·   spectating — the run continues" % [_fmt_time(elapsed), seed_value]
	_spect.visible = true
	_spect_label.text = "SPECTATING"


func show_mp_escaped() -> void:
	_hud.visible = false
	_inv.visible = false
	_spect.visible = true
	_spect_label.text = "YOU MADE IT OUT — WAITING FOR YOUR PARTNER..."


func show_mp_win(i_died: bool, seed_value: int, elapsed: float) -> void:
	_hud.visible = false
	_inv.visible = false
	_spect.visible = false
	_end.visible = true
	_end_row.visible = false
	_end_title.text = "ESCAPED"
	_end_sub.text = "Your partner escaped. Your signal did not return." if i_died else "You escaped. The expedition is over."
	_end_stats.text = "Time %s   ·   Seed %d%s" % [_fmt_time(elapsed), seed_value, "   ·   local signal lost" if i_died else ""]


func show_mp_loss(seed_value: int, elapsed: float) -> void:
	_hud.visible = false
	_inv.visible = false
	_spect.visible = false
	_end.visible = true
	_end_row.visible = false
	_end_title.text = "SIGNAL LOST"
	_end_sub.text = "The backrooms keep you both now."
	_end_stats.text = "Survived %s   ·   Seed %d" % [_fmt_time(elapsed), seed_value]


func _fmt_time(t: float) -> String:
	var m: int = int(t) / 60
	var s: int = int(t) % 60
	var ms: int = int(t * 1000.0) % 1000
	return "%d:%02d.%03d" % [m, s, ms]


func _fmt_clock(elapsed: float) -> String:
	var total: int = 2 * 3600 + int(elapsed)
	return "%02d:%02d:%02d" % [total / 3600 % 24, total / 60 % 60, total % 60]


func _best_text() -> String:
	if game == null or game.best_time_ms < 0:
		return "Best escape: —"
	return "Best escape: %s" % _fmt_time(float(game.best_time_ms) / 1000.0)


# ------------------------------------------------------------------ builders

func _build_vhs() -> void:
	_vhs_layer = CanvasLayer.new()
	_vhs_layer.layer = 5
	add_child(_vhs_layer)
	_vhs_mat = ShaderMaterial.new()
	_vhs_mat.shader = load("res://shaders/vhs_overlay.gdshader") as Shader
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _vhs_mat
	_vhs_layer.add_child(rect)
	_rec_label = Label.new()
	_rec_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_rec_label.offset_left = -380.0
	_rec_label.offset_top = 12.0
	_rec_label.offset_right = -16.0
	_rec_label.offset_bottom = 40.0
	_rec_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rec_label.add_theme_font_size_override("font_size", 20)
	_rec_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_rec_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vhs_layer.add_child(_rec_label)
	var cam := Label.new()
	cam.text = "CAM 03"
	cam.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cam.offset_left = -140.0
	cam.offset_top = -48.0
	cam.offset_right = -16.0
	cam.offset_bottom = -16.0
	cam.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cam.add_theme_font_size_override("font_size", 20)
	cam.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	cam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vhs_layer.add_child(cam)


func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.offset_left = -7
	_crosshair.offset_top = -12
	_crosshair.add_theme_font_size_override("font_size", 18)
	_crosshair.modulate = Color(0.9, 0.85, 0.7, 0.65)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_crosshair)
	_interact_prompt = Label.new()
	_interact_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_interact_prompt.offset_left = -220
	_interact_prompt.offset_right = 220
	_interact_prompt.offset_top = 30
	_interact_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_prompt.add_theme_font_size_override("font_size", 14)
	_interact_prompt.add_theme_color_override("font_color", AMBER)
	_interact_prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	_interact_prompt.add_theme_constant_override("shadow_offset_x", 1)
	_interact_prompt.add_theme_constant_override("shadow_offset_y", 1)
	_interact_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_interact_prompt)
	_objective_label = Label.new()
	_objective_label.text = "FIND THE EXIT"
	_objective_label.position = Vector2(16, 12)
	_objective_label.add_theme_font_size_override("font_size", 22)
	_hud.add_child(_objective_label)
	_seed_label = Label.new()
	_seed_label.text = "SEED 0"
	_seed_label.position = Vector2(16, 44)
	_seed_label.add_theme_font_size_override("font_size", 16)
	_hud.add_child(_seed_label)
	_time_label = Label.new()
	_time_label.text = "0:00.000"
	_time_label.position = Vector2(16, 68)
	_time_label.add_theme_font_size_override("font_size", 16)
	_hud.add_child(_time_label)
	_stamina_bar = ProgressBar.new()
	_stamina_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stamina_bar.offset_left = -150.0
	_stamina_bar.offset_top = -48.0
	_stamina_bar.offset_right = 150.0
	_stamina_bar.offset_bottom = -34.0
	_stamina_bar.min_value = 0.0
	_stamina_bar.max_value = 1.0
	_stamina_bar.value = 1.0
	_stamina_bar.show_percentage = false
	_hud.add_child(_stamina_bar)
	_meter_caption(-49.0, "STAMINA")
	_flash_label = Label.new()
	_flash_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_flash_label.offset_left = -150.0
	_flash_label.offset_top = -76.0
	_flash_label.offset_right = 150.0
	_flash_label.offset_bottom = -52.0
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash_label.add_theme_font_size_override("font_size", 14)
	_hud.add_child(_flash_label)
	_food_bar = _meter_bar(-104.0, "FOOD")
	_water_bar = _meter_bar(-128.0, "WATER")
	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.offset_left = -140.0
	_fps_label.offset_top = 44.0
	_fps_label.offset_right = -16.0
	_fps_label.offset_bottom = 68.0
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_fps_label)
	_inv_hud = Label.new()
	_inv_hud.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_inv_hud.offset_left = -180.0
	_inv_hud.offset_top = -52.0
	_inv_hud.offset_right = -16.0
	_inv_hud.offset_bottom = -28.0
	_inv_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_inv_hud.add_theme_font_size_override("font_size", 15)
	_inv_hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_inv_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_inv_hud)
	_coop_label = Label.new()
	_coop_label.position = Vector2(16, 92)
	_coop_label.add_theme_font_size_override("font_size", 15)
	_coop_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_coop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coop_label.visible = false
	_hud.add_child(_coop_label)
	_intro_label = Label.new()
	_intro_label.text = "LEVEL 0 · THE LOBBY\nRecover signal 01, then take the east stairs down.\nE use · J journal · G drop glowstick · crouch to hide"
	_intro_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_intro_label.offset_left = -400
	_intro_label.offset_right = 400
	_intro_label.offset_top = 90
	_intro_label.offset_bottom = 170
	_intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_label.add_theme_font_size_override("font_size", 18)
	_intro_label.add_theme_color_override("font_color", Color("efc782"))
	_intro_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_intro_label)
	_hunt_flash = ColorRect.new()
	_hunt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hunt_flash.color = Color(0.55, 0.02, 0.02, 0.0)
	_hunt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hunt_flash)
	# Always-on subtle vignette: transparent center, darkened corners.
	var vig := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for vy: int in 256:
		for vx: int in 256:
			var dx: float = (float(vx) - 128.0) / 128.0
			var dy: float = (float(vy) - 128.0) / 128.0
			var d: float = sqrt(dx * dx + dy * dy)
			var a: float = clampf((d - 0.62) / 0.75, 0.0, 1.0)
			vig.set_pixel(vx, vy, Color(0, 0, 0, a * a * 0.45))
	vig.generate_mipmaps()
	_vignette = TextureRect.new()
	_vignette.name = "Vignette"
	_vignette.texture = ImageTexture.create_from_image(vig)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_vignette)
	_hud.move_child(_vignette, 0)


func _meter_bar(top_off: float, meter_label: String) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -150.0
	bar.offset_top = top_off
	bar.offset_right = 150.0
	bar.offset_bottom = top_off + 12.0
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	_hud.add_child(bar)
	_meter_caption(top_off - 3.0, meter_label)
	return bar


func _meter_caption(top: float, text: String) -> void:
	var caption := Label.new()
	caption.text = text
	caption.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	caption.offset_left = -250
	caption.offset_right = -160
	caption.offset_top = top
	caption.offset_bottom = top + 20
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", PAPER)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(caption)


func _build_inventory() -> void:
	var vbox := _panel_box("SUPPLY PACK", 28)
	_inv = _center_of(vbox)
	_inv_water_l = Label.new()
	_inv_water_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_inv_water_l)
	_inv_bread_l = Label.new()
	_inv_bread_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_inv_bread_l)
	var drink_btn := Button.new()
	drink_btn.text = "Drink water [E]"
	drink_btn.pressed.connect(_on_drink_pressed)
	vbox.add_child(drink_btn)
	var eat_btn := Button.new()
	eat_btn.text = "Eat bread [Q]"
	eat_btn.pressed.connect(_on_eat_pressed)
	vbox.add_child(eat_btn)
	var hint := Label.new()
	hint.text = "R or Esc closes. The game does not pause."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	refresh_inventory()


func _on_drink_pressed() -> void:
	if game != null:
		game.drink_inv()


func _on_eat_pressed() -> void:
	if game != null:
		game.eat_inv()


func toggle_inventory() -> void:
	if game == null:
		return
	_inv.visible = not _inv.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _inv.visible else Input.MOUSE_MODE_CAPTURED
	refresh_inventory()


func close_inventory() -> void:
	_inv.visible = false


func is_inventory_open() -> bool:
	return _inv.visible


func refresh_inventory() -> void:
	if game == null or _inv_water_l == null:
		return
	_inv_water_l.text = "Almond water: %d" % game.inv_water
	_inv_bread_l.text = "Dry bread: %d" % game.inv_bread


func _panel_box(title: String, font_size: int) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	# Caller stores the CenterContainer; VBox is fetched via get_child chain.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 0)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color("131510f5")
	plate.border_color = Color("7c6947")
	plate.set_border_width_all(1)
	plate.border_width_top = 3
	plate.shadow_color = Color(0, 0, 0, 0.65)
	plate.shadow_size = 24
	panel.add_theme_stylebox_override("panel", plate)
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", PAPER)
	theme.set_color("font_color", "Button", PAPER)
	theme.set_color("font_hover_color", "Button", AMBER)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var button_style := StyleBoxFlat.new()
		button_style.bg_color = Color("2b2d23") if state == "hover" else Color("20231c")
		button_style.border_color = AMBER if state == "focus" else Color("5a533d")
		button_style.set_border_width_all(1)
		button_style.content_margin_left = 16
		button_style.content_margin_right = 16
		button_style.content_margin_top = 10
		button_style.content_margin_bottom = 10
		theme.set_stylebox(state, "Button", button_style)
	panel.theme = theme
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	var title_label := Label.new()
	title_label.add_theme_color_override("font_color", AMBER)
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", font_size)
	vbox.add_child(title_label)
	center.visible = false
	# Stash the center on the vbox for the caller.
	vbox.set_meta("center", center)
	return vbox


func _center_of(vbox: VBoxContainer) -> CenterContainer:
	var c: CenterContainer = vbox.get_meta("center") as CenterContainer
	vbox.remove_meta("center")
	return c


func _build_volume_row(vbox: VBoxContainer) -> void:
	# Shared Master volume row: slider + percent/mute readout. Menu and pause
	# rows stay in lockstep through AudioManager's persisted volume API.
	var row := HBoxContainer.new()
	vbox.add_child(row)
	var label := Label.new()
	label.text = "Master volume"
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.0  # continuous so a saved fractional volume stays exact
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 22)
	slider.value_changed.connect(_on_volume_changed)
	row.add_child(slider)
	_volume_sliders.append(slider)
	var readout := Label.new()
	readout.custom_minimum_size = Vector2(88, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_font_size_override("font_size", 13)
	readout.add_theme_color_override("font_color", MUTED)
	row.add_child(readout)
	_volume_readouts.append(readout)


func _build_menu() -> void:
	var vbox := _panel_box("BACKROOMS: SIGNAL LOST", 30)
	_menu = _center_of(vbox)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	vbox.add_child(seed_row)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "Seed (blank = random)"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_edit)
	var dice := Button.new()
	dice.text = "Random"
	dice.pressed.connect(func() -> void: _seed_edit.text = str(randi()))
	seed_row.add_child(dice)
	var sens_row := HBoxContainer.new()
	vbox.add_child(sens_row)
	var sens_label := Label.new()
	sens_label.text = "Sensitivity"
	sens_row.add_child(sens_label)
	_sens_slider = HSlider.new()
	_sens_slider.min_value = 0.0005
	_sens_slider.max_value = 0.006
	_sens_slider.step = 0.0001
	_sens_slider.value = 0.0022
	_sens_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sens_row.add_child(_sens_slider)
	var fov_row := HBoxContainer.new()
	vbox.add_child(fov_row)
	var fov_label := Label.new()
	fov_label.text = "Field of view"
	fov_row.add_child(fov_label)
	_fov_slider = HSlider.new()
	_fov_slider.min_value = 60.0
	_fov_slider.max_value = 90.0
	_fov_slider.step = 1.0
	_fov_slider.value = 75.0
	_fov_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fov_row.add_child(_fov_slider)
	_build_volume_row(vbox)
	var preset_row := HBoxContainer.new()
	vbox.add_child(preset_row)
	var preset_label := Label.new()
	preset_label.text = "Graphics"
	preset_row.add_child(preset_label)
	_preset_opt = OptionButton.new()
	_preset_opt.add_item("High", 0)
	_preset_opt.add_item("Low", 1)
	_preset_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_row.add_child(_preset_opt)
	_best_label = Label.new()
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_best_label)
	_start_btn = Button.new()
	_start_btn.text = "ENTER THE BACKROOMS"
	_start_btn.custom_minimum_size = Vector2(0, 44)
	_start_btn.pressed.connect(_on_start_pressed)
	vbox.add_child(_start_btn)
	# --- Co-op (2 players, direct IP).
	var coop_title := Label.new()
	coop_title.text = "CO-OP (2 PLAYERS)"
	coop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coop_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(coop_title)
	var coop_row := HBoxContainer.new()
	coop_row.add_theme_constant_override("separation", 8)
	vbox.add_child(coop_row)
	var host_btn := Button.new()
	host_btn.text = "Host"
	host_btn.pressed.connect(_on_host_pressed)
	coop_row.add_child(host_btn)
	_join_edit = LineEdit.new()
	_join_edit.placeholder_text = "Partner IP"
	_join_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coop_row.add_child(_join_edit)
	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(_on_join_pressed)
	coop_row.add_child(join_btn)
	_mp_status = Label.new()
	_mp_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mp_status.add_theme_font_size_override("font_size", 13)
	_mp_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_mp_status.visible = false
	vbox.add_child(_mp_status)
	var help := Label.new()
	help.text = "WASD move · Shift sprint (loud) · Ctrl crouch · F flash · E use · V view · R pack · J journal · G glowstick · Esc pause"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 13)
	vbox.add_child(help)


func _build_pause() -> void:
	var vbox := _panel_box("PAUSED", 30)
	_pause = _center_of(vbox)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(func() -> void: game.resume())
	vbox.add_child(resume)
	var sens_row := HBoxContainer.new()
	vbox.add_child(sens_row)
	var sens_label := Label.new()
	sens_label.text = "Sensitivity"
	sens_row.add_child(sens_label)
	_pause_sens = HSlider.new()
	_pause_sens.min_value = 0.0005
	_pause_sens.max_value = 0.006
	_pause_sens.step = 0.0001
	_pause_sens.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sens_row.add_child(_pause_sens)
	_pause_sens.value_changed.connect(func(v: float) -> void: game.apply_settings(v, game.preset, game.vhs_enabled))
	var pfov_row := HBoxContainer.new()
	vbox.add_child(pfov_row)
	var pfov_label := Label.new()
	pfov_label.text = "Field of view"
	pfov_row.add_child(pfov_label)
	_pause_fov = HSlider.new()
	_pause_fov.min_value = 60.0
	_pause_fov.max_value = 90.0
	_pause_fov.step = 1.0
	_pause_fov.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pfov_row.add_child(_pause_fov)
	_pause_fov.value_changed.connect(func(v: float) -> void: game.apply_settings(game.sensitivity, game.preset, game.vhs_enabled, v))
	_build_volume_row(vbox)
	_pause_vhs = CheckBox.new()
	_pause_vhs.text = "VHS effect"
	_pause_vhs.toggled.connect(func(b: bool) -> void: game.apply_settings(game.sensitivity, game.preset, b))
	vbox.add_child(_pause_vhs)
	_pause_restart = Button.new()
	_pause_restart.text = "Restart (same seed)"
	_pause_restart.pressed.connect(func() -> void: game.restart_same_seed())
	vbox.add_child(_pause_restart)
	var menu_btn := Button.new()
	menu_btn.text = "Quit to menu"
	menu_btn.pressed.connect(func() -> void: game.quit_to_menu())
	vbox.add_child(menu_btn)


func _build_end() -> void:
	var vbox := _panel_box("", 44)
	_end = _center_of(vbox)
	_end_title = vbox.get_child(0) as Label
	_end_sub = Label.new()
	_end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_end_sub)
	_end_stats = Label.new()
	_end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_end_stats)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	_end_row = row
	var new_btn := Button.new()
	new_btn.text = "New seed"
	new_btn.pressed.connect(func() -> void: game.restart_new_seed())
	row.add_child(new_btn)
	var same_btn := Button.new()
	same_btn.text = "Same seed [R]"
	same_btn.pressed.connect(func() -> void: game.restart_same_seed())
	row.add_child(same_btn)
	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.pressed.connect(func() -> void: game.quit_to_menu())
	vbox.add_child(menu_btn)


func _build_loading() -> void:
	var vbox := _panel_box("ENTERING...", 36)
	_loading = _center_of(vbox)
	_loading_stage = Label.new()
	_loading_stage.text = "Tuning the fluorescents..."
	_loading_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_stage.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_loading_stage)


func _build_spectate() -> void:
	_spect = CenterContainer.new()
	_spect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_spect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_spect)
	_spect_label = Label.new()
	_spect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spect_label.add_theme_font_size_override("font_size", 22)
	_spect_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4, 0.9))
	_spect.add_child(_spect_label)
	_spect.visible = false


func _on_host_pressed() -> void:
	if net == null:
		return
	var err: String = net.host_game()
	if err != "":
		set_mp_status(err)
		return
	set_mp_status("Hosting on %s — waiting for your partner (start solo works too)" % net.local_ip())


func _on_join_pressed() -> void:
	if net == null:
		return
	var ip: String = _join_edit.text.strip_edges()
	if ip == "":
		set_mp_status("Type your partner's IP first.")
		return
	var err: String = net.join_game(ip)
	set_mp_status("Connecting to %s..." % ip if err == "" else err)


func _on_start_pressed() -> void:
	var t: String = _seed_edit.text.strip_edges()
	var seed_value: int = int(t) if t.is_valid_int() else randi()
	game.apply_settings(_sens_slider.value, "High" if _preset_opt.selected == 0 else "Low", game.vhs_enabled, _fov_slider.value)
	if net != null and net.is_mp():
		if net.mode == "host" and net.remote_id == 0:
			# Nobody came: ENTER falls back to a plain solo run.
			net.leave()
			game.start_game(seed_value)
			return
		if net.mode != "host":
			set_mp_status("Only the host starts the run.")
			return
		net.begin_run(seed_value)  # both machines start from this seed
	else:
		game.start_game(seed_value)
