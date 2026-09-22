extends StaticBody3D
## Floor-mounted investigation equipment. Faces +Z; never floats or disappears.
var campaign: Node
var record_id: int = 0
var _status: Label3D
var _lamp: OmniLight3D
var _indicator: StandardMaterial3D
var _reels: Array[Node3D] = []
var _lever: Node3D
var _completed: bool = false
var _metal: StandardMaterial3D
var _dark: StandardMaterial3D
var _paper: StandardMaterial3D
var _brass: StandardMaterial3D

func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	_metal = _material(Color("626963"), 0.55)
	_dark = _material(Color("171e1d"), 0.15)
	_paper = _material(Color("d4c59e"))
	_brass = _material(Color("b48e43"), 0.7)
	_indicator = _material(Color("df9c3e"))
	_indicator.emission_enabled = true
	_indicator.emission = Color("e7a642")
	_indicator.emission_energy_multiplier = 1.8
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.9, 0.60)
	shape.shape = box
	shape.position.y = 0.95
	add_child(shape)
	if record_id == 0:
		_build_recorder()
	elif record_id == 1:
		_build_isolator()
	elif record_id == 2:
		_build_terminal()
	else:
		_build_record_stand()
	# Distinctive numbered enamel plate, attached to the equipment face.
	_box(Vector3(0.88, 0.15, 0.025), Vector3(0, 1.96, 0.24), _dark)
	_label("FIELD / %02d" % (record_id + 1 if record_id < 3 else 0), Vector3(0, 1.96, 0.26), 28, 0.003)
	_status = _label("REFERENCE REQUIRED", Vector3(0, 1.76, 0.34), 23, 0.0025)
	_lamp = OmniLight3D.new()
	_lamp.position = Vector3(0, 1.82, 0.65)
	_lamp.light_color = Color("ffc978")
	_lamp.light_energy = 0.8
	_lamp.omni_range = 4.5
	_lamp.shadow_enabled = false
	add_child(_lamp)
	_box(Vector3(0.12, 0.065, 0.065), Vector3(0.39, 1.81, 0.32), _indicator)
	# Bolted feet and a metal cable conduit keep all stations grounded.
	for x: float in [-0.35, 0.35]:
		_box(Vector3(0.21, 0.05, 0.65), Vector3(x, 0.025, 0), _dark)
		for z: float in [-0.23, 0.23]:
			_cylinder(0.035, 0.02, Vector3(x, 0.06, z), _brass)
	_box(Vector3(0.05, 0.04, 0.55), Vector3(0.25, 0.025, -0.53), _dark)

func interact() -> void:
	if is_instance_valid(campaign):
		campaign.request_interaction(record_id)

func prompt_text() -> String:
	if record_id == 3:
		return "[E] READ / recovered field briefing"
	if record_id < campaign.stage:
		return "[E] READ / recovered transcript %02d" % (record_id + 1)
	if record_id > campaign.stage:
		return "[E] INSPECT / awaiting reference %02d" % (campaign.stage + 1)
	return "[E] " + campaign.ACTIONS[record_id].to_upper()

func set_progress(stage: int) -> void:
	_completed = record_id < stage
	if _status == null:
		return
	var active: bool = record_id == stage or record_id == 3
	_status.text = "RECORD RETAINED" if _completed else ("READY / E TO USE" if active else "INTERLOCK / WAIT")
	var color := Color("82d7b2") if _completed else (Color("ffc978") if active else Color("8a7060"))
	_status.modulate = color
	_lamp.light_color = color
	_lamp.light_energy = 0.8 if active else 0.35
	_indicator.emission = color
	_indicator.albedo_color = color
	if _lever != null:
		_lever.rotation.x = -0.6 if _completed else 0.6

func _process(delta: float) -> void:
	if not _completed:
		for reel: Node3D in _reels:
			reel.rotation.z += delta * 0.6

func _build_recorder() -> void:
	# Archival trolley, two open reels, tape heads, speaker and VU meter.
	for x: float in [-0.36, 0.36]:
		_box(Vector3(0.045, 1.05, 0.045), Vector3(x, 0.54, -0.15), _metal)
	_box(Vector3(0.94, 0.06, 0.64), Vector3(0, 0.83, 0), _metal)
	_box(Vector3(0.87, 0.90, 0.42), Vector3(0, 1.29, -0.03), _metal)
	_box(Vector3(0.78, 0.79, 0.025), Vector3(0, 1.30, 0.19), _dark)
	for x: float in [-0.23, 0.23]:
		var pivot := Node3D.new()
		pivot.position = Vector3(x, 1.49, 0.23)
		add_child(pivot)
		_reels.append(pivot)
		var reel := _cylinder(0.17, 0.028, Vector3.ZERO, _brass, pivot)
		reel.rotation.x = PI / 2.0
		for spoke: int in 3:
			var arm := _box(Vector3(0.26, 0.025, 0.018), Vector3(0, 0, 0.026), _dark, pivot)
			arm.rotation.z = spoke * PI / 3.0
		var hub := _cylinder(0.035, 0.035, Vector3(0, 0, 0.04), _metal, pivot)
		hub.rotation.x = PI / 2.0
	_box(Vector3(0.47, 0.012, 0.014), Vector3(0, 1.33, 0.26), _paper)
	_box(Vector3(0.14, 0.10, 0.05), Vector3(0, 1.28, 0.24), _metal)
	_box(Vector3(0.23, 0.13, 0.02), Vector3(-0.20, 1.08, 0.23), _paper)
	_label("VU / -06", Vector3(-0.2, 1.08, 0.25), 20, 0.002)
	for i: int in 6:
		_box(Vector3(0.22, 0.012, 0.03), Vector3(0.19, 1.0 + i * 0.027, 0.23), _metal)
	for i: int in 4:
		_box(Vector3(0.1, 0.055, 0.06), Vector3(-0.22 + i * 0.15, 0.90, 0.24), _brass if i == 0 else _paper)
	_label("VENN / REF. LEADER", Vector3(0, 0.73, 0.32), 26, 0.0024)

func _build_isolator() -> void:
	# Narrow industrial switch cabinet, ceramic fuses and a physical disconnect.
	_box(Vector3(0.84, 1.70, 0.44), Vector3(0, 0.88, -0.03), _metal)
	_box(Vector3(0.73, 1.12, 0.035), Vector3(0, 1.02, 0.21), _dark)
	for x: float in [-0.22, 0.0, 0.22]:
		_cylinder(0.047, 0.27, Vector3(x, 1.32, 0.27), _paper)
		for y: float in [1.15, 1.49]:
			_box(Vector3(0.1, 0.055, 0.08), Vector3(x, y, 0.25), _brass)
		_box(Vector3(0.014, 0.28, 0.016), Vector3(x, 1.61, 0.24), _brass)
	_lever = Node3D.new()
	_lever.position = Vector3(0, 0.82, 0.28)
	add_child(_lever)
	_box(Vector3(0.07, 0.34, 0.07), Vector3(0, 0.13, 0), _metal, _lever)
	_box(Vector3(0.3, 0.08, 0.1), Vector3(0, 0.3, 0), _brass, _lever)
	_label("RETURN / ISOLATE", Vector3(0, 0.51, 0.25), 26, 0.0024)
	for i: int in 6:
		_box(Vector3(0.55, 0.012, 0.03), Vector3(0, 0.17 + i * 0.037, 0.21), _dark)

func _build_terminal() -> void:
	# CRT on a floor console; keyboard keys, printer slot and receipt.
	_box(Vector3(0.78, 0.98, 0.54), Vector3(0, 0.51, -0.05), _metal)
	_box(Vector3(1.0, 0.12, 0.63), Vector3(0, 1.03, 0.04), _dark)
	_box(Vector3(0.84, 0.61, 0.45), Vector3(0, 1.43, -0.03), _metal)
	_box(Vector3(0.72, 0.45, 0.035), Vector3(0, 1.43, 0.21), _dark)
	var glass := _material(Color("173c35"))
	glass.emission_enabled = true
	glass.emission = Color("285d47")
	_box(Vector3(0.63, 0.35, 0.025), Vector3(0, 1.44, 0.236), glass)
	_label("RETURN_03\nONE TRANSMISSION\n> SILENCE", Vector3(0, 1.43, 0.26), 24, 0.0022)
	for row: int in 3:
		for key: int in 9:
			_box(Vector3(0.055, 0.016, 0.04), Vector3(-0.29 + key * 0.073, 1.101, 0.13 + row * 0.065), _paper)
	_box(Vector3(0.47, 0.055, 0.028), Vector3(0, 0.83, 0.23), _dark)
	var receipt := _box(Vector3(0.34, 0.27, 0.018), Vector3(0, 0.71, 0.265), _paper)
	receipt.rotation.x = -0.17
	_label("RETAIN\nDO NOT REPEAT", Vector3(0, 0.72, 0.3), 18, 0.002)

func _build_record_stand() -> void:
	# Briefing binder secured to a lectern, with a clipped carbon-copy sheet.
	_box(Vector3(0.55, 0.12, 0.5), Vector3(0, 0.1, 0), _metal)
	_box(Vector3(0.07, 1.18, 0.08), Vector3(0, 0.67, -0.08), _metal)
	_box(Vector3(0.86, 0.75, 0.09), Vector3(0, 1.38, 0.09), _dark)
	_box(Vector3(0.67, 0.6, 0.03), Vector3(0, 1.37, 0.155), _paper)
	_box(Vector3(0.25, 0.055, 0.055), Vector3(0, 1.69, 0.17), _metal)
	_label("LISTENING OFFICE\n\nRETURN CHANNEL\n\nFIELD BRIEFING\n\nVENN / PELL", Vector3(0, 1.37, 0.18), 24, 0.0024)

func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = 0.7
	return mat

func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = pos
	parent.add_child(instance)
	return instance

func _cylinder(radius: float, height: float, pos: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = pos
	parent.add_child(instance)
	return instance

func _label(text: String, pos: Vector3, font: int, pixels: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.font_size = font
	label.pixel_size = pixels
	label.modulate = Color("e5d4a6")
	label.outline_size = 2
	label.no_depth_test = false
	add_child(label)
	return label
