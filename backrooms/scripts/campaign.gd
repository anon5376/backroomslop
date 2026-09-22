extends Node
## THE RETURN CHANNEL. Shared, host-authoritative investigation; local field journal.
## Integration: root child Campaign, can_exit(), objectives_changed(stage).
const Interactable = preload("res://scripts/campaign_interactable.gd")
signal objectives_changed(stage: int)
# Global station cells; each id lives on STATION_LEVEL[id] (mirror of the maze keys).
const CELLS: Array[Vector2i] = [Vector2i(21, 89), Vector2i(96, 21), Vector2i(96, 21), Vector2i(95, 96)]
const STATION_LEVEL: Array[int] = [0, 1, 2, 0]
const TITLES: Array[String] = ["01 / THE VOICE ON THE LEADER", "02 / A ROOM THAT LISTENS", "03 / THE RETURN CHANNEL", "00 / FIELD BRIEFING"]
const ACTIONS: Array[String] = ["Recover the reference tape", "Isolate the listening circuit", "Transmit the release pulse", "Read the field briefing"]
const OBJECTIVES: Array[String] = [
	"01  RECOVER THE REFERENCE\nLEVEL 0 / yellow offices, middle room on the far wall.\nFind the amber reel-to-reel recorder.",
	"02  BREAK THE FEEDBACK\nLEVEL 1 / down the east stairwell, then the north hall.\nIsolate the amber maintenance panel.",
	"03  SEND ONE LAST REPLY\nLEVEL 2 / down again, past the pipes, north hall.\nUse the return-channel console.",
	"RETURN CHANNEL OPEN\nLEVEL 2 / east hall, past the pipes.\nLeave through the white door. The recording goes with you."
]
const RECORDS: Array[String] = [
	"WEST OFFICE / magnetic tape, reverse side\nOperator: Mara Venn\n\nWe came for a distress call. Six seconds long: 'Leave the line open. I am still here.' Every receiver heard a different voice. Mine sounded like my brother, who never worked here.\n\nI recorded the room with the microphone unplugged. The voice was still on the tape. Under it: the click of our own recorder, exactly six seconds ahead of us.\n\nThis isn't a person calling from another room. It's the room rehearsing us. I have cut a reference loop from the blank leader. Carry that silence to the service panel. It is the only sound here that wasn't borrowed.\n\nRECOVERED: reference loop. Take the east stairwell DOWN, past the server hall. Ivo's panel waits on LEVEL 1, north hall.",
	"SERVICE / carbon copy behind the isolator\nMaintenance technician: Ivo Pell\n\nMara was right. The wire marked EMERGENCY RETURN does not lead outside. It feeds every microphone back into the building. Every answer gives it another room. Every footstep teaches it where a person ought to be.\n\nThe thing in the corridors is not guarding the exit. It is the shape of everyone who answered. Do not let it finish learning you.\n\nI used Mara's blank leader as a reference and opened the listening circuit. For six seconds I heard rain. Real rain: no fluorescent buzz behind it. Then the recorder spoke in my voice. I had left the return transmitter running.\n\nISOLATED: listening circuit. The reference is clean. Take the east stairs DOWN again. The return console is on LEVEL 2, north hall, past the pipes. Send the silence once. Do not repeat it.",
	"SERVER / return-channel terminal receipt\nTransmission: one blank reference / acknowledgement received\n\nThe console tries your voice first. Then Mara's. Then a voice so small you almost answer. You let the blank leader run to its end.\n\nFor the first time, nothing answers. The white door loses the sound of the room behind it. There is only rain.\n\nA final strip of paper emerges:\n'RECEIVED OUTSIDE. TWO OPERATORS REPORTED MISSING. RECORD RETAINED. THANK YOU FOR NOT ERASING US.'\n\nMara and Ivo were not the call. They were the people who stopped answering it. You have not rescued their voices; you have carried out the proof that they were here.\n\nRELEASE PULSE ACCEPTED. Take the recording through the white door in the east hall. You owe the room no reply.",
	"RECOVERY ASSIGNMENT / Return Channel\nFiled by the Listening Office, no date\n\nA six-second distress signal has been repeating beneath an abandoned office building. Two investigators, Mara Venn and Ivo Pell, went in to trace it. Neither returned. Their equipment is still transmitting.\n\nRecover their reference tape in the WEST offices of LEVEL 0. Take the east stairwell DOWN to the concrete halls of LEVEL 1 and break the feedback in the north hall. Descend once more to LEVEL 2: send the reply from the north console, then leave through the white door in the east hall. There is no way back up. The ordinary EXIT signs are not evidence.\n\nMara marked the equipment with amber lamps and numbered plates: 01, 02, 03. Follow those, not the voices.\n\nFIELD NOTES\nE uses the object in your sights (within 3.2m). J opens this journal. The journal is local; recovered objectives are shared with your partner. Reading does NOT pause the corridors. Close with J or Esc.\n\nWalk softly. Bring water. Bring back something that does not speak."
]

var stage: int = 0
var started: bool = false
var scrap_journal: Array[int] = []
var main: Node
var game: Node
var player: Player
var net: Node
var stations: Array[StaticBody3D] = []
var journal: Array[int] = [3]
var _pending_record: int = -1
var _layer: CanvasLayer
var _hud: PanelContainer
var _objective: Label
var _route: Label
var _compass: Label
var _prompt: Label
var _reader: PanelContainer
var _text: RichTextLabel
var _tabs: HBoxContainer
var _notice: Label
var _read_open: bool = false
var _was_active: bool = false
var _last_state: int = -1
var _route_timer: float = 0.0
var _sync_timer: float = 0.0
var _exit_plate: Label3D

const SCRAP_TITLES: Array[String] = [
	"N1 / BREAK ROOM MEMO", "N2 / ARCHIVE SLIP", "N3 / WEST MARGIN",
	"N4 / SERVICE TAG", "N5 / LOBBY WARNING", "N6 / SERVER POST-IT",
]
const SCRAP_TEXTS: Array[String] = [
	"BREAK ROOM / taped inside a tray\nMara Venn\n\nThe vending machine hums in B-flat. The room hums back in A. Six seconds apart, like everything else here.\n\nDo not eat here after the lights stutter. The food is still food. You are briefly less yourself, and the room can tell.",
	"ARCHIVE / box 12, misfiled\nIvo Pell\n\nBox 12 contains the sound of box 12. I opened it twice. The first time: tape hiss. The second time: my own hands, opening it the first time.\n\nI have stopped shelving. The boxes reshelve themselves when the fluorescents drop. Count them if you must. Count them once.",
	"WEST OFFICE / wallpaper margin\nMara Venn\n\nCount the stripes between two doors. Odd going. Even returning. The pattern skips one stripe every hour and blames your eyes.\n\nNever trust an even corridor. Mark your turns. Ivo carves arrows; I drop glowsticks. The room erases his. It keeps mine, which frightens me more.",
	"SERVICE / tied to a valve wheel\nIvo Pell\n\nThe knocking follows the maintenance schedule. There is no maintenance. There is no night shift. There is knocking.\n\nIf it knocks back at you — three, then two — leave that corridor. It has learned the rhythm of your step and it is practicing.",
	"LOBBY / marker on drywall, unknown hand\n\nIT ONLY MOVES WHEN THE LIGHTS LIE.\n\nWalk when they tell the truth. Freeze when they stutter. Count to six. If the buzz comes back wrong — higher, like a held breath — do not be where it last saw you.\n\n(I did not write this. Ivo did not write this. It was here when we arrived. It is still wet.)",
	"SERVER / stuck to rack 04\nMara Venn\n\nThe servers dream in coolant. Last night they dreamed my brother's voice and I almost answered. Coolant smells like rain now.\n\nThe return channel is real. One blank transmission, no reply, and the white door forgets how to be a wall. Send the silence once. Do not repeat it.",
]

func _ready() -> void:
	add_to_group("campaign")
	main = get_parent()
	game = main.get("game")
	player = main.get("player")
	net = main.get("net")
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not InputMap.has_action("journal"):
		InputMap.add_action("journal")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_J
		InputMap.action_add_event("journal", key)
	_build_overlay()
	game.run_started.connect(_begin)

func can_exit() -> bool:
	return started and stage == 3

func _begin() -> void:
	started = true
	stage = 0
	journal = [3]
	_build_level_stations()
	_update_visuals()
	if _is_client():
		_request_snapshot.rpc_id(1)


func _build_level_stations() -> void:
	# Only this level's stations exist; the exit plate only where the exit is.
	for s: StaticBody3D in stations:
		if is_instance_valid(s):
			s.queue_free()
	stations.clear()
	for i: int in CELLS.size():
		stations.append(null)
	if is_instance_valid(_exit_plate):
		_exit_plate.queue_free()
		_exit_plate = null
	var level: int = int(game.get("level_index"))
	for id: int in CELLS.size():
		if STATION_LEVEL[id] != level:
			continue
		var station := Interactable.new()
		station.name = "SignalStation_%d" % id
		station.campaign = self
		station.record_id = id
		station.position = game.maze.cell_to_world(CELLS[id]) + Vector3(0, 0, -0.95)
		game.world_root.add_child(station)
		stations[id] = station
	if level == MazeGenerator.FINAL_LEVEL:
		_exit_plate = Label3D.new()
		_exit_plate.text = "RETURN CHANNEL\nLOCKED / 0 OF 3"
		_exit_plate.font_size = 36
		_exit_plate.pixel_size = 0.006
		_exit_plate.position = game.maze.exit_world_pos + Vector3(-2.0, 1.7, 0)
		_exit_plate.rotation.y = -PI / 2.0
		game.world_root.add_child(_exit_plate)

func _is_client() -> bool:
	return net != null and net.is_mp() and not net.am_server()

func request_interaction(id: int) -> void:
	if not _local_alive() or _read_open or id < 0 or id >= CELLS.size():
		return
	if id == 3 or id < stage:
		_open_record(id)
		return
	if id > stage:
		_open_text("CIRCUIT INTERLOCK", "This station needs the previous reference.\n\n" + OBJECTIVES[stage] + "\n\nThe numbered plates show the order: 01 LEVEL 0 → 02 LEVEL 1 → 03 LEVEL 2.")
		return
	_pending_record = id
	if _is_client():
		_activate_request.rpc_id(1, id)
	else:
		_server_activate(net.my_id() if net != null else 1, id)

## Same ordered transition used by both solo and network validation.
static func next_stage(current: int, objective: int) -> int:
	return current + 1 if current >= 0 and current < 3 and objective == current else current

@rpc("any_peer", "call_remote", "reliable")
func _activate_request(id: int) -> void:
	if not _is_client():
		_server_activate(multiplayer.get_remote_sender_id(), id)

func _server_activate(peer: int, id: int) -> bool:
	if _is_client() or not started or id < 0 or id >= 3 or id != stage:
		return false
	if id >= stations.size() or stations[id] == null or not is_instance_valid(stations[id]):
		return false  # station lives on another level
	var actor: Player = player
	if net != null and peer != net.my_id():
		if peer != net.remote_id or bool(main.get("remote_downed")) or bool(main.get("remote_gone")):
			return false
		actor = main.get("remote_avatar") as Player
	else:
		if not _local_alive():
			return false
	if actor == null or not is_instance_valid(actor) or actor.downed:
		return false
	# A client cannot activate distant objectives, through walls, or out of order.
	var eye: Vector3 = actor.global_position + Vector3(0, 1.5, 0)
	var target: Vector3 = stations[id].global_position + Vector3(0, 1.35, 0.2)
	if eye.distance_to(target) > 4.0:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, target)
	query.exclude = [actor.get_rid()]
	query.collide_with_areas = false
	var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider != stations[id]:
		return false
	_apply_stage(next_stage(stage, id))
	if net != null and net.is_mp() and net.remote_id != 0:
		_sync_stage.rpc(stage)
	return true

@rpc("authority", "call_remote", "reliable")
func _sync_stage(value: int) -> void:
	if value < stage or value > 3 or value < 0:
		return
	_apply_stage(value)

@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot() -> void:
	if not _is_client() and started and net != null and multiplayer.get_remote_sender_id() == net.remote_id:
		_sync_stage.rpc_id(net.remote_id, stage)

func _apply_stage(value: int) -> void:
	var changed: bool = value != stage
	stage = value
	_update_visuals()
	if changed:
		objectives_changed.emit(stage)
	if _pending_record >= 0 and _pending_record < stage:
		var id: int = _pending_record
		_pending_record = -1
		_open_record(id)

func _update_visuals() -> void:
	for station: StaticBody3D in stations:
		if station != null and is_instance_valid(station):
			station.set_progress(stage)
	if is_instance_valid(_exit_plate):
		_exit_plate.text = "RETURN CHANNEL\nOPEN / TAKE THE RECORD" if can_exit() else "RETURN CHANNEL\nLOCKED / %d OF 3" % stage
		_exit_plate.modulate = Color(0.5, 1.0, 0.75) if can_exit() else Color(1.0, 0.68, 0.3)
	if is_instance_valid(_objective):
		_objective.text = OBJECTIVES[stage]

func _local_alive() -> bool:
	return started and game != null and game.state == GameManager.GState.PLAYING and not game.mp_dead and not game.mp_escaped

func _process(delta: float) -> void:
	if not started:
		return
	var alive: bool = _local_alive()
	if _last_state != game.state or not alive:
		if _read_open:
			_close_reader()
		_last_state = game.state
	_hud.visible = alive and not _read_open and not game.is_inventory_open()
	_prompt.visible = alive and not _read_open and not game.is_inventory_open()
	_prompt.text = ""
	if alive and not _read_open and not game.is_inventory_open():
		var target: Object = focused_interactable()
		if target != null:
			_prompt.text = target.prompt_text()
		elif player.global_position.distance_to(game.maze.exit_world_pos) < 5.0:
			if int(game.get("level_index")) == MazeGenerator.FINAL_LEVEL:
				if not can_exit():
					_prompt.text = "EXIT INTERLOCK / Recover all three signal references. [J]"
			else:
				_prompt.text = "STAIRWELL DOWN / No way back. Walk in to descend."
	_route_timer -= delta
	if alive and _route_timer <= 0.0:
		_route_timer = 0.4
		_update_route()
		_update_compass()
	# Retry snapshot after asynchronous world builds; objectives are monotonic.
	_sync_timer += delta
	if _is_client() and _sync_timer >= 2.0:
		_sync_timer = 0.0
		_request_snapshot.rpc_id(1)

func focused_interactable() -> Object:
	var hit: Dictionary = player.interaction_hit()
	if not hit.is_empty() and hit.collider.has_method("prompt_text"):
		return hit.collider
	return null

static func route_distances(maze: MazeGenerator, goal: Vector2i) -> PackedInt32Array:
	var width: int = MazeGenerator.GRID_W
	var height: int = MazeGenerator.GRID_H
	var blocked: PackedByteArray = maze.get_blocked()
	var distances := PackedInt32Array()
	distances.resize(width * height)
	distances.fill(-1)
	if goal.x < 0 or goal.y < 0 or goal.x >= width or goal.y >= height:
		return distances
	var index: int = goal.y * width + goal.x
	if blocked[index] != 0:
		return distances
	var queue: Array[Vector2i] = [goal]
	distances[index] = 0
	var cursor: int = 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for step: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
				continue
			var next_index: int = next.y * width + next.x
			if blocked[next_index] == 0 and distances[next_index] == -1:
				distances[next_index] = distances[cell.y * width + cell.x] + 1
				queue.append(next)
	return distances

func _goal_cell() -> Vector2i:
	# Current station when it shares this level, else the stairs (or exit).
	var maze: MazeGenerator = game.maze
	if stage < 3 and STATION_LEVEL[stage] == int(game.get("level_index")):
		return CELLS[stage]
	return maze.exit_cell


func _update_route() -> void:
	var maze: MazeGenerator = game.maze
	var here: Vector2i = maze.world_to_cell(player.global_position)
	var goal: Vector2i = _goal_cell()
	var distances: PackedInt32Array = route_distances(maze, goal)
	if here.x < 0 or here.x >= MazeGenerator.GRID_W or here.y < 0 or here.y >= MazeGenerator.GRID_H:
		_route.text = "ROUTE UNAVAILABLE · return to a clear corridor\n[J] FIELD JOURNAL"
		return
	var distance: int = distances[here.y * MazeGenerator.GRID_W + here.x]
	if distance < 0:
		_route.text = "ROUTE UNAVAILABLE · step into a clear corridor\n[J] FIELD JOURNAL"
		return
	var direction: String = "AT SIGNAL"
	var best: int = distance
	for entry: Array in [[Vector2i(0, -1), "NORTH"], [Vector2i(1, 0), "EAST"], [Vector2i(0, 1), "SOUTH"], [Vector2i(-1, 0), "WEST"]]:
		var cell: Vector2i = here + entry[0]
		if cell.x < 0 or cell.x >= MazeGenerator.GRID_W or cell.y < 0 or cell.y >= MazeGenerator.GRID_H:
			continue
		var d: int = distances[cell.y * MazeGenerator.GRID_W + cell.x]
		if d >= 0 and d < best:
			best = d
			direction = entry[1]
	var forward: Vector3 = -player.global_transform.basis.z
	var facing: String = "NORTH" if absf(forward.z) >= absf(forward.x) and forward.z < 0 else "SOUTH"
	if absf(forward.x) > absf(forward.z):
		facing = "EAST" if forward.x > 0 else "WEST"
	_route.text = "ROUTE %s · %dm walk\nFacing %s   /   [J] FIELD JOURNAL" % [direction, int(maxi(distance, 0) * MazeGenerator.CELL), facing]

func _update_compass() -> void:
	if not is_instance_valid(_compass):
		return
	var maze: MazeGenerator = game.maze
	var goal: Vector2i = _goal_cell()
	var fwd: Vector3 = -player.global_transform.basis.z
	var heading: float = rad_to_deg(atan2(fwd.x, -fwd.z))
	var to: Vector3 = maze.cell_to_world(goal) - player.global_position
	var bearing: float = rad_to_deg(atan2(to.x, -to.z))
	_compass.text = compass_tape(heading, bearing)


static func compass_tape(heading_deg: float, target_deg: float) -> String:
	# 25-char heading tape, 7.5 degrees per slot. Cardinals + target star.
	var out: String = ""
	var dead_on: bool = absf(wrapf(target_deg - heading_deg, -180.0, 180.0)) < 3.75
	for i: int in range(-12, 13):
		if i == 0:
			out += "*" if dead_on else "|"
			continue
		var ang: float = wrapf(heading_deg + float(i) * 7.5, 0.0, 360.0)
		var ch: String = "."
		for card: Array in [[0.0, "N"], [90.0, "E"], [180.0, "S"], [270.0, "W"]]:
			if absf(wrapf(ang - float(card[0]), -180.0, 180.0)) < 3.75:
				ch = String(card[1])
		if absf(wrapf(ang - target_deg, -180.0, 180.0)) < 3.75:
			ch = "*"
		out += ch
	return out


func _input(event: InputEvent) -> void:
	if not started or (event is InputEventKey and event.echo):
		return
	if _read_open:
		if event.is_action_pressed("journal") or event.is_action_pressed("pause"):
			_close_reader()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("restart"):
			# Do not stack supply pack or pause panels over the field journal.
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("journal") and _local_alive():
		if game.is_inventory_open():
			game.ui.close_inventory()
		_open_journal()
		get_viewport().set_input_as_handled()

func _open_record(id: int) -> void:
	if not journal.has(id):
		journal.append(id)
	_open_text(TITLES[id], RECORDS[id])


func collect_scrap(id: int) -> void:
	"""Margin notes are local: reading them never touches shared progress."""
	if not _local_alive() or id < 0 or id >= SCRAP_TEXTS.size():
		return
	if not scrap_journal.has(id):
		scrap_journal.append(id)
	_open_text(SCRAP_TITLES[id], SCRAP_TEXTS[id])


func _open_scrap(id: int) -> void:
	if id >= 0 and id < SCRAP_TEXTS.size():
		_open_text(SCRAP_TITLES[id], SCRAP_TEXTS[id])

func _open_journal() -> void:
	# Progress is shared; choosing to read recovered transcripts stays local.
	for id: int in stage:
		if not journal.has(id):
			journal.append(id)
	_open_record(journal.back())

func _open_text(title: String, body: String) -> void:
	if not _local_alive():
		return
	if not _read_open:
		_was_active = player.active
	_read_open = true
	player.active = false
	player.velocity = Vector3.ZERO
	_reader.visible = true
	_hud.visible = false
	_prompt.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_text.text = "[font_size=24][color=#efc782]" + title + "[/color][/font_size]\n\n" + body
	_text.scroll_to_line(0)
	for child: Node in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	for id: int in journal:
		var button := Button.new()
		button.text = "BRIEF" if id == 3 else "%02d" % (id + 1)
		button.pressed.connect(_open_record.bind(id))
		_tabs.add_child(button)
	var scrap_ids: Array[int] = scrap_journal.duplicate()
	scrap_ids.sort()
	for id: int in scrap_ids:
		var sbutton := Button.new()
		sbutton.text = "N%d" % (id + 1)
		sbutton.pressed.connect(_open_scrap.bind(id))
		_tabs.add_child(sbutton)

func _close_reader() -> void:
	_read_open = false
	_reader.visible = false
	if _local_alive():
		player.active = _was_active
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "FieldJournal"
	_layer.layer = 7
	add_child(_layer)
	_hud = PanelContainer.new()
	_hud.position = Vector2(16, 126)
	_hud.custom_minimum_size = Vector2(335, 0)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_theme_stylebox_override("panel", _style())
	_layer.add_child(_hud)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 10)
	_hud.add_child(box)
	_objective = Label.new()
	_objective.custom_minimum_size.x = 310
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.add_theme_font_size_override("font_size", 15)
	_objective.add_theme_color_override("font_color", Color("efc782"))
	box.add_child(_objective)
	_route = Label.new()
	_route.add_theme_font_size_override("font_size", 13)
	box.add_child(_route)
	_compass = Label.new()
	_compass.add_theme_font_size_override("font_size", 13)
	_compass.add_theme_color_override("font_color", Color("9fb8a8"))
	box.add_child(_compass)
	_prompt = Label.new()
	_layer.add_child(_prompt)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -370
	_prompt.offset_right = 370
	_prompt.offset_top = -188
	_prompt.offset_bottom = -158
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.add_theme_color_override("font_color", Color("efc782"))
	_prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	_prompt.add_theme_constant_override("shadow_outline_size", 5)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reader = PanelContainer.new()
	_layer.add_child(_reader)
	_reader.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reader.anchor_left = 0.28
	_reader.anchor_right = 0.91
	_reader.anchor_top = 0.18
	_reader.anchor_bottom = 0.76
	_reader.add_theme_stylebox_override("panel", _style())
	var pages := VBoxContainer.new()
	pages.add_theme_constant_override("separation", 10)
	_reader.add_child(pages)
	_tabs = HBoxContainer.new()
	pages.add_child(_tabs)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 18)
	_text.add_theme_color_override("default_color", Color("e4e1cd"))
	pages.add_child(_text)
	_notice = Label.new()
	_notice.text = "LIVE FIELD JOURNAL / The corridors do not pause."
	_notice.add_theme_font_size_override("font_size", 13)
	_notice.add_theme_color_override("font_color", Color("efc782"))
	pages.add_child(_notice)
	var close := Button.new()
	close.text = "Return to the room [J / Esc]"
	close.pressed.connect(_close_reader)
	pages.add_child(close)
	_reader.visible = false
	_hud.visible = false
	_prompt.visible = false

func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.04, 0.96)
	style.border_color = Color(0.55, 0.43, 0.23, 0.85)
	style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style
