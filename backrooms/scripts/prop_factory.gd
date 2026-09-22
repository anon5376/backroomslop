class_name PropFactory
extends RefCounted
## Primitive-built set dressing. No external models, ever.

static var _shared: Dictionary = {}
static var _meshes: Dictionary = {}


# Retain FakeDoor's public contract and cooldown without consuming gameplay RNG.
class AcousticDoor extends FakeDoor:
	var _knocks: int = 0

	func interact() -> void:
		var now: int = Time.get_ticks_msec()
		if now < _next_ok_msec:
			return
		_next_ok_msec = now + 600
		if is_instance_valid(_thunk):
			var phase: int = (absi(int(global_position.x * 13.0 + global_position.z * 7.0)) + _knocks) % 5
			_thunk.pitch_scale = 0.98 + float(phase) * 0.01
			_thunk.volume_db = -1.0 + float(phase % 3) * 0.3
			_thunk.position = Vector3(0.36 + float(phase - 2) * 0.006, 1.02, 0.08)
			_knocks += 1
			_thunk.play()


static func get_shared() -> Dictionary:
	if not _shared.is_empty():
		return _shared
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.09, 0.09, 0.10)
	dark.roughness = 0.85
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.16, 0.15, 0.13)
	plastic.roughness = 0.6
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.42, 0.43, 0.45)
	metal.metallic = 0.75
	metal.roughness = 0.35
	var cardboard := StandardMaterial3D.new()
	cardboard.albedo_color = Color(0.48, 0.36, 0.22)
	cardboard.roughness = 0.95
	var cone_orange := StandardMaterial3D.new()
	cone_orange.albedo_color = Color(0.75, 0.28, 0.08)
	cone_orange.roughness = 0.7
	var door_brown := StandardMaterial3D.new()
	door_brown.albedo_color = Color(0.32, 0.22, 0.13)
	door_brown.roughness = 0.8
	var frame_gray := StandardMaterial3D.new()
	frame_gray.albedo_color = Color(0.20, 0.20, 0.21)
	frame_gray.roughness = 0.5
	frame_gray.metallic = 0.4
	var jug_blue := StandardMaterial3D.new()
	jug_blue.albedo_color = Color(0.35, 0.55, 0.75, 0.75)
	jug_blue.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	jug_blue.roughness = 0.2
	var alu := StandardMaterial3D.new()
	alu.albedo_color = Color(0.58, 0.59, 0.61)
	alu.metallic = 0.6
	alu.roughness = 0.4
	var ivory := StandardMaterial3D.new()
	ivory.albedo_color = Color(0.78, 0.74, 0.62)
	ivory.roughness = 0.6
	_shared = {
		"dark": dark, "plastic": plastic, "metal": metal, "cardboard": cardboard,
		"cone": cone_orange, "door": door_brown, "frame": frame_gray, "jug": jug_blue,
		"alu": alu, "ivory": ivory,
	}
	# Glow ring materials for pickups (built once, shared by all rings).
	var ring_tex := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y: int in 64:
		for x: int in 64:
			var dx: float = (float(x) - 32.0) / 32.0
			var dy: float = (float(y) - 32.0) / 32.0
			var d: float = sqrt(dx * dx + dy * dy)
			var band: float = clampf(1.0 - absf(d - 0.72) / 0.20, 0.0, 1.0)
			ring_tex.set_pixel(x, y, Color(1, 1, 1, band * band))
	ring_tex.generate_mipmaps()
	var ring_img := ImageTexture.create_from_image(ring_tex)
	for entry: Array in [["ring_water", Color(0.35, 1.1, 1.3)], ["ring_bread", Color(1.4, 0.95, 0.35)]]:
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.albedo_texture = ring_img
		rm.albedo_color = entry[1]
		rm.no_depth_test = false
		_shared[entry[0]] = rm
	return _shared


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if not _meshes.has(size):
		var bm := BoxMesh.new()
		bm.size = size
		_meshes[size] = bm
	mi.mesh = _meshes[size]
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var key := Vector4(r_top, r_bot, h, 1.0)
	if not _meshes.has(key):
		var cm := CylinderMesh.new()
		cm.top_radius = r_top
		cm.bottom_radius = r_bot
		cm.height = h
		cm.radial_segments = 16
		cm.rings = 1
		_meshes[key] = cm
	mi.mesh = _meshes[key]
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


# Local batches keep repeated small details to one draw per material, with local culling.
static func _slats(parent: Node3D, size: Vector3, start: Vector3, stride: Vector3, count: int, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i: int in count:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, start + stride * float(i)))
	var instance := MultiMeshInstance3D.new()
	instance.name = "DetailBatch"
	instance.multimesh = mm
	instance.material_override = mat
	instance.visibility_range_end = 32.0
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


static func _cable(parent: Node3D, points: Array[Vector3], radius: float, mat: Material) -> void:
	for i: int in range(points.size() - 1):
		var delta: Vector3 = points[i + 1] - points[i]
		var wire := _cyl(parent, radius, radius, delta.length(), (points[i] + points[i + 1]) * 0.5, mat)
		wire.quaternion = Quaternion(Vector3.UP, delta.normalized())


static func _panel(parent: Node3D, center: Vector3, size: Vector2, mat: Material) -> void:
	# Proud rails around a recessed field; no extra interaction/collision surfaces.
	_box(parent, Vector3(size.x, size.y, 0.012), center, mat)
	for x: float in [-1.0, 1.0]:
		_box(parent, Vector3(0.025, size.y + 0.04, 0.024), center + Vector3(x * size.x * 0.5, 0, 0.008), mat)
	for y: float in [-1.0, 1.0]:
		_box(parent, Vector3(size.x, 0.025, 0.024), center + Vector3(0, y * size.y * 0.5, 0.008), mat)


static func _cushion(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	# Three octagonal primitive layers form a chamfered upholstered silhouette.
	var shape := Node3D.new()
	shape.position = pos
	shape.scale = Vector3(size.x, 1.0, size.z)
	parent.add_child(shape)
	for layer: int in 3:
		var mesh := CylinderMesh.new()
		mesh.radial_segments = 8
		mesh.rings = 1
		mesh.height = size.y * (0.6 if layer == 1 else 0.2)
		mesh.top_radius = 0.46 if layer == 2 else 0.54
		mesh.bottom_radius = 0.46 if layer == 0 else 0.54
		var part := MeshInstance3D.new()
		part.mesh = mesh
		part.material_override = mat
		part.rotation.y = PI / 8.0
		part.position.y = float(layer - 1) * size.y * 0.4
		shape.add_child(part)


static func build_chair() -> Node3D:
	"""Office chair: 5-star base, gas lift, armrests, slatted back. Origin at floor."""
	var s := get_shared()
	var root := Node3D.new()
	root.name = "Chair"
	# 5-star base + casters.
	_cyl(root, 0.05, 0.05, 0.07, Vector3(0, 0.06, 0), s["dark"])
	for li: int in 5:
		var pivot := Node3D.new()
		root.add_child(pivot)
		pivot.rotation.y = TAU * float(li) / 5.0
		# Tapered spider arms: outer foot droops, thicker at the hub.
		var arm := _cyl(pivot, 0.026, 0.014, 0.30, Vector3(0.14, 0.032, 0), s["dark"])
		arm.rotation.z = PI / 2.0
		arm.rotation.y = -PI / 2.0
		_box(pivot, Vector3(0.045, 0.055, 0.045), Vector3(0.29, 0.028, 0), s["plastic"])  # caster
		_cyl(pivot, 0.012, 0.012, 0.05, Vector3(0.29, 0.0, 0), s["plastic"]).rotation.x = PI / 2.0  # wheel
	_cyl(root, 0.024, 0.032, 0.30, Vector3(0, 0.24, 0), s["metal"])  # gas lift
	_cyl(root, 0.05, 0.05, 0.04, Vector3(0, 0.40, 0), s["metal"])  # lift collar
	_cushion(root, Vector3(0.46, 0.09, 0.44), Vector3(0, 0.465, 0), s["plastic"])  # seat
	# Lumbar shell behind the seat.
	_cushion(root, Vector3(0.42, 0.30, 0.07), Vector3(0, 0.80, -0.235), s["plastic"])
	# Back posts + three slats.
	_box(root, Vector3(0.05, 0.52, 0.05), Vector3(-0.19, 0.72, -0.21), s["dark"])
	_box(root, Vector3(0.05, 0.52, 0.05), Vector3(0.19, 0.72, -0.21), s["dark"])
	_box(root, Vector3(0.43, 0.13, 0.05), Vector3(0, 0.92, -0.21), s["plastic"])
	_box(root, Vector3(0.43, 0.10, 0.05), Vector3(0, 0.68, -0.21), s["plastic"])
	_box(root, Vector3(0.40, 0.06, 0.04), Vector3(0, 1.05, -0.21), s["plastic"])  # headrest
	# Armrests.
	for ax: float in [-0.25, 0.25]:
		_box(root, Vector3(0.04, 0.20, 0.04), Vector3(ax, 0.58, 0), s["dark"])
		_box(root, Vector3(0.06, 0.04, 0.30), Vector3(ax, 0.70, 0), s["plastic"])
		_box(root, Vector3(0.03, 0.05, 0.22), Vector3(ax, 0.53, 0.0), s["dark"])  # arm brace
	return root


static func build_fake_door(thunk_stream: AudioStream, slab_mat: Material = null) -> StaticBody3D:
	"""Doorframe + slab proud of the wall. Never opens. interact() -> thunk."""
	var s := get_shared()
	var root := AcousticDoor.new()
	root.name = "FakeDoor"
	root.add_to_group("fake_doors")
	# Thin collision slab in front of the wall so the interact ray hits us first.
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.1, 2.2, 0.18)
	cs.shape = bs
	cs.position = Vector3(0, 1.1, 0.02)
	root.add_child(cs)
	# Stepped casing: outer trim, inner stop beads proud of the slab face.
	_box(root, Vector3(0.12, 2.2, 0.14), Vector3(-0.56, 1.1, 0.0), s["frame"])
	_box(root, Vector3(0.12, 2.2, 0.14), Vector3(0.56, 1.1, 0.0), s["frame"])
	_box(root, Vector3(1.24, 0.12, 0.14), Vector3(0, 2.24, 0.0), s["frame"])
	_box(root, Vector3(1.34, 0.03, 0.18), Vector3(0, 2.325, 0.0), s["frame"])  # crown drip cap
	_box(root, Vector3(1.30, 0.05, 0.16), Vector3(0, 0.025, 0.0), s["dark"])  # threshold saddle
	_box(root, Vector3(1.0, 2.12, 0.08), Vector3(0, 1.06, -0.02), slab_mat if slab_mat != null else s["door"])
	# Recessed panels + proud bead mouldings on the slab face.
	_panel(root, Vector3(-0.22, 1.5, 0.025), Vector2(0.36, 0.68), slab_mat if slab_mat != null else s["door"])
	_panel(root, Vector3(0.22, 1.5, 0.025), Vector2(0.36, 0.68), slab_mat if slab_mat != null else s["door"])
	_panel(root, Vector3(-0.22, 0.6, 0.025), Vector2(0.36, 0.52), slab_mat if slab_mat != null else s["door"])
	_panel(root, Vector3(0.22, 0.6, 0.025), Vector2(0.36, 0.52), slab_mat if slab_mat != null else s["door"])
	for hy: float in [0.6, 1.6]:
		_box(root, Vector3(0.05, 0.12, 0.12), Vector3(-0.52, hy, 0.0), s["dark"])  # hinges
		_box(root, Vector3(0.06, 0.03, 0.13), Vector3(-0.52, hy + 0.075, 0.0), s["dark"])  # hinge knuckles
	_box(root, Vector3(0.90, 0.22, 0.02), Vector3(0, 0.14, 0.03), s["metal"])  # kick plate
	# Knob: escutcheon plate, lever and rose for a stronger silhouette.
	_box(root, Vector3(0.05, 0.16, 0.015), Vector3(0.38, 1.02, 0.05), s["metal"])
	var knob := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.045
	sph.height = 0.09
	sph.radial_segments = 16
	sph.rings = 8
	knob.mesh = sph
	knob.material_override = s["metal"]
	knob.position = Vector3(0.38, 1.02, 0.06)
	root.add_child(knob)
	_box(root, Vector3(0.14, 0.028, 0.02), Vector3(0.45, 1.02, 0.07), s["metal"])  # lever handle
	var player3d := AudioStreamPlayer3D.new()
	player3d.stream = thunk_stream
	player3d.max_distance = 12.0
	player3d.position = Vector3(0.36, 1.02, 0.08)
	root.add_child(player3d)
	root.setup(player3d)
	return root


static func build_exit_sign() -> Node3D:
	var s := get_shared()
	var root := Node3D.new()
	root.name = "ExitSign"
	# Housing with a top cap and end caps so the sign reads from the side.
	_box(root, Vector3(0.9, 0.32, 0.1), Vector3(0, 0, 0), s["dark"])
	_box(root, Vector3(0.94, 0.03, 0.13), Vector3(0, 0.175, 0), s["metal"])  # top cap
	_box(root, Vector3(0.94, 0.03, 0.13), Vector3(0, -0.175, 0), s["dark"])  # bottom cap
	var label := Label3D.new()
	label.text = "EXIT"
	label.font_size = 96
	label.pixel_size = 0.004
	label.modulate = Color(0.4, 2.2, 0.6)
	label.shaded = false
	label.double_sided = false
	label.position = Vector3(0, 0, 0.06)
	root.add_child(label)
	var back := label.duplicate() as Label3D
	back.rotation_degrees = Vector3(0, 180, 0)
	back.position = Vector3(0, 0, -0.06)
	root.add_child(back)
	return root


static func build_exit_door() -> Node3D:
	"""Freestanding exit: ajar door, white void glow both sides, EXIT sign, trigger Area."""
	var s := get_shared()
	var root := Node3D.new()
	root.name = "ExitDoor"
	_box(root, Vector3(0.14, 2.3, 0.5), Vector3(-0.6, 1.15, 0), s["frame"])
	_box(root, Vector3(0.14, 2.3, 0.5), Vector3(0.6, 1.15, 0), s["frame"])
	_box(root, Vector3(1.34, 0.14, 0.5), Vector3(0, 2.34, 0), s["frame"])
	# Ajar slab on a hinge pivot.
	var pivot := Node3D.new()
	pivot.position = Vector3(-0.5, 0, 0.1)
	pivot.rotation.y = -0.5
	root.add_child(pivot)
	_box(pivot, Vector3(1.0, 2.2, 0.07), Vector3(0.5, 1.1, 0), s["door"])
	_box(pivot, Vector3(0.80, 0.06, 0.05), Vector3(0.5, 1.05, 0.06), s["metal"])  # push bar
	_box(pivot, Vector3(0.90, 0.25, 0.02), Vector3(0.5, 0.16, 0.045), s["metal"])  # kick plate
	for hy: float in [0.5, 1.7]:
		_box(pivot, Vector3(0.06, 0.12, 0.10), Vector3(0.02, hy, 0), s["dark"])  # hinges
	_box(root, Vector3(1.10, 0.03, 0.20), Vector3(0, 0.015, 0.1), s["metal"])  # threshold
	# Ivory arch trim around the frame: the exit reads as a destination.
	_box(root, Vector3(0.10, 2.44, 0.56), Vector3(-0.74, 1.22, 0), s["ivory"])
	_box(root, Vector3(0.10, 2.44, 0.56), Vector3(0.74, 1.22, 0), s["ivory"])
	_box(root, Vector3(1.58, 0.10, 0.56), Vector3(0, 2.47, 0), s["ivory"])
	# The white void: unshaded hot quads facing both ways.
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.albedo_color = Color(3.0, 3.0, 2.7)
	for side: int in [0, 180]:
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.0, 2.2)
		quad.mesh = qm
		quad.material_override = glow_mat
		quad.rotation_degrees = Vector3(0, side, 0)
		quad.position = Vector3(0, 1.1, 0.1 if side == 0 else -0.1)
		root.add_child(quad)
	var sign := build_exit_sign()
	sign.position = Vector3(0, 2.62, 0)
	root.add_child(sign)
	for rx: float in [-0.35, 0.35]:
		_cyl(root, 0.012, 0.012, 0.22, Vector3(rx, 2.51, 0), s["dark"])  # sign rods
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.6, 1.0, 0.7)
	lamp.light_energy = 1.2
	lamp.omni_range = 7.0
	lamp.position = Vector3(0, 2.2, 0.6)
	root.add_child(lamp)
	# Light spill on the floor, both approaches.
	var spill_mat := StandardMaterial3D.new()
	spill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spill_mat.albedo_color = Color(1.9, 2.0, 1.7)
	var spill_i: int = 0
	for sz: float in [-1.4, 1.4]:
		var spill := MeshInstance3D.new()
		spill.name = "ExitSpill_%d" % spill_i
		spill_i += 1
		var sq := QuadMesh.new()
		sq.size = Vector2(2.0, 2.4)
		spill.mesh = sq
		spill.material_override = spill_mat
		spill.rotation.x = -PI / 2.0
		spill.position = Vector3(0, 0.02, sz)
		root.add_child(spill)
	var area := Area3D.new()
	area.name = "ExitArea"
	area.add_to_group("exit_area")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.6, 2.6, 2.6)
	cs.shape = bs
	cs.position = Vector3(0, 1.2, 0)
	area.add_child(cs)
	root.add_child(area)
	return root


static func build_stairs_down() -> Node3D:
	"""Open stairwell shaft: railed black pit, hanging DOWN sign, trigger Area."""
	var s := get_shared()
	var root := Node3D.new()
	root.name = "StairsDown"
	# The pit: unshaded near-black quad sunk just over the floor.
	var pit_mat := StandardMaterial3D.new()
	pit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pit_mat.albedo_color = Color(0.004, 0.004, 0.005)
	var pit := MeshInstance3D.new()
	var pq := QuadMesh.new()
	pq.size = Vector2(1.8, 1.8)
	pit.mesh = pq
	pit.material_override = pit_mat
	pit.rotation.x = -PI / 2.0
	pit.position = Vector3(0, 0.02, 0)
	root.add_child(pit)
	# First tread edges sink from the south rim into the pit.
	for i: int in 3:
		_box(root, Vector3(1.8, 0.09, 0.28), Vector3(0, 0.28 - float(i) * 0.09, 0.78 - float(i) * 0.26), s["frame"])
	# Hazard rim + railing posts on three sides (south side is the way in).
	var hazard_y := 0.035
	_box(root, Vector3(2.1, 0.02, 0.14), Vector3(0, hazard_y, -0.98), s["cone"])
	_box(root, Vector3(0.14, 0.02, 2.1), Vector3(-0.98, hazard_y, 0), s["cone"])
	_box(root, Vector3(0.14, 0.02, 2.1), Vector3(0.98, hazard_y, 0), s["cone"])
	for px: float in [-0.95, 0.95]:
		for pz: float in [-0.95, 0.0, 0.95]:
			if pz > 0.5:
				continue  # open south side
			_box(root, Vector3(0.07, 1.05, 0.07), Vector3(px, 0.52, pz), s["metal"])
	for px: float in [-0.95, 0.95]:
		_box(root, Vector3(0.06, 0.06, 1.9), Vector3(px, 1.05, 0), s["metal"])
	_box(root, Vector3(1.96, 0.06, 0.06), Vector3(0, 1.05, -0.95), s["metal"])
	# Hanging sign + dim red lamp so the shaft reads from far away.
	_box(root, Vector3(0.06, 0.5, 0.06), Vector3(-0.8, 2.45, -0.95), s["dark"])
	_box(root, Vector3(0.06, 0.5, 0.06), Vector3(0.8, 2.45, -0.95), s["dark"])
	var sign := Label3D.new()
	sign.text = "DOWN"
	sign.font_size = 96
	sign.pixel_size = 0.008
	sign.modulate = Color(1.0, 0.62, 0.15)
	sign.shaded = false
	sign.position = Vector3(0, 2.2, -0.95)
	root.add_child(sign)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.25, 0.15)
	lamp.light_energy = 0.9
	lamp.omni_range = 6.0
	lamp.position = Vector3(0, 2.1, 0)
	root.add_child(lamp)
	var area := Area3D.new()
	area.name = "StairsArea"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 2.6, 2.2)
	cs.shape = bs
	cs.position = Vector3(0, 1.2, 0)
	area.add_child(cs)
	root.add_child(area)
	return root


static func build_cabinet() -> Node3D:
	var s := get_shared()
	var root := Node3D.new()
	root.name = "Cabinet"
	_box(root, Vector3(0.55, 1.8, 0.7), Vector3(0, 0.9, 0), s["metal"])
	_box(root, Vector3(0.50, 0.06, 0.65), Vector3(0, 0.03, 0), s["dark"])  # plinth
	_box(root, Vector3(0.58, 0.04, 0.73), Vector3(0, 1.82, 0), s["frame"])  # top rim
	for i: int in 4:
		var cy: float = 0.35 + float(i) * 0.4
		_box(root, Vector3(0.49, 0.36, 0.014), Vector3(0, cy, 0.358), s["frame"])
		_box(root, Vector3(0.45, 0.32, 0.015), Vector3(0, cy, 0.37), s["metal"])
		_box(root, Vector3(0.16, 0.065, 0.012), Vector3(0, cy + 0.08, 0.385), s["dark"])  # label holder
		_box(root, Vector3(0.13, 0.04, 0.012), Vector3(0, cy + 0.08, 0.393), s["cardboard"])
		_box(root, Vector3(0.22, 0.025, 0.035), Vector3(0, cy - 0.08, 0.40), s["frame"])  # pull
		for x: float in [-0.10, 0.10]:
			_box(root, Vector3(0.025, 0.06, 0.04), Vector3(x, cy - 0.06, 0.385), s["frame"])
	return root


static func build_crate(size: float = 0.7) -> Node3D:
	var s := get_shared()
	var root := Node3D.new()
	root.name = "Crate"
	_box(root, Vector3(size, size, size), Vector3(0, size / 2.0, 0), s["cardboard"])
	if not _shared.has("tape"):
		var tape := StandardMaterial3D.new()
		tape.albedo_color = Color(0.62, 0.57, 0.46)
		tape.roughness = 0.9
		_shared["tape"] = tape
		s = get_shared()
	_box(root, Vector3(size, 0.012, 0.09), Vector3(0, size + 0.004, 0), s["tape"])
	_box(root, Vector3(0.09, size, 0.012), Vector3(0, size / 2.0, size / 2.0 + 0.004), s["tape"])
	return root


static func build_cooler() -> Node3D:
	var s := get_shared()
	var root := Node3D.new()
	root.name = "Cooler"
	_box(root, Vector3(0.4, 1.05, 0.4), Vector3(0, 0.525, 0), s["plastic"])
	_cyl(root, 0.16, 0.16, 0.5, Vector3(0, 1.3, 0), s["jug"])
	_cyl(root, 0.05, 0.05, 0.05, Vector3(0, 1.06, 0), s["plastic"])  # neck ring
	_box(root, Vector3(0.06, 0.10, 0.05), Vector3(0, 0.78, 0.21), s["dark"])  # spigot
	_box(root, Vector3(0.20, 0.02, 0.12), Vector3(0, 0.70, 0.22), s["metal"])  # drip tray
	if not _shared.has("water"):
		var water := StandardMaterial3D.new()
		water.albedo_color = Color(0.30, 0.55, 0.80, 0.55)
		water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water.roughness = 0.1
		_shared["water"] = water
		s = get_shared()
	_cyl(root, 0.135, 0.135, 0.28, Vector3(0, 1.22, 0), s["water"])  # water line
	_cyl(root, 0.12, 0.16, 0.07, Vector3(0, 1.58, 0), s["jug"])
	_cyl(root, 0.16, 0.08, 0.09, Vector3(0, 1.08, 0), s["jug"])
	for y: float in [1.15, 1.4, 1.51]:
		_cyl(root, 0.164, 0.164, 0.018, Vector3(0, y, 0), s["jug"])
	_box(root, Vector3(0.32, 0.35, 0.015), Vector3(0, 0.30, 0.208), s["dark"])
	_slats(root, Vector3(0.29, 0.015, 0.018), Vector3(0, 0.17, 0.22), Vector3(0, 0.035, 0), 8, s["frame"])
	_box(root, Vector3(0.44, 0.045, 0.44), Vector3(0, 0.045, 0), s["dark"])
	_box(root, Vector3(0.44, 0.035, 0.44), Vector3(0, 1.035, 0), s["frame"])
	_cable(root, [Vector3(0.14, 0.4, -0.21), Vector3(0.14, 0.07, -0.23), Vector3(0.05, 0.025, -0.28)], 0.009, s["dark"])
	return root


static func build_gateway(frame_mat: Material) -> Node3D:
	"""Hazard-striped portal frame spanning a 3m corridor. Spans local X."""
	var root := Node3D.new()
	root.name = "Gateway"
	_box(root, Vector3(0.3, 2.7, 0.3), Vector3(-1.65, 1.35, 0), frame_mat)
	_box(root, Vector3(0.3, 2.7, 0.3), Vector3(1.65, 1.35, 0), frame_mat)
	_box(root, Vector3(3.6, 0.3, 0.3), Vector3(0, 2.7, 0), frame_mat)
	for y: float in [0.6, 1.2, 1.8, 2.4]:
		_box(root, Vector3(0.08, 0.45, 0.32), Vector3(-1.65, y, 0), frame_mat)
		_box(root, Vector3(0.08, 0.45, 0.32), Vector3(1.65, y, 0), frame_mat)
	_box(root, Vector3(3.6, 0.07, 0.32), Vector3(0, 2.57, 0), frame_mat)
	_box(root, Vector3(3.6, 0.07, 0.32), Vector3(0, 2.85, 0), frame_mat)
	return root


static func build_server_rack(blink_mat: Material) -> Node3D:
	"""2m server cabinet with blinking status strips. Origin at floor, faces +Z."""
	var s := get_shared()
	var root := Node3D.new()
	root.name = "ServerRack"
	_box(root, Vector3(0.8, 2.0, 0.7), Vector3(0, 1.0, 0), s["dark"])
	_box(root, Vector3(0.84, 0.08, 0.74), Vector3(0, 0.04, 0), s["frame"])  # plinth
	_box(root, Vector3(0.84, 0.04, 0.74), Vector3(0, 2.02, 0), s["frame"])  # top cap
	for i: int in 5:
		var uy: float = 0.35 + float(i) * 0.33
		_box(root, Vector3(0.7, 0.28, 0.02), Vector3(0, uy, 0.36), s["plastic"])
		var led := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.5, 0.05)
		led.mesh = qm
		led.material_override = blink_mat
		led.position = Vector3(0, uy, 0.375)
		root.add_child(led)
		_box(root, Vector3(0.40, 0.025, 0.02), Vector3(0, uy - 0.09, 0.37), s["metal"])  # handle
		_box(root, Vector3(0.03, 0.03, 0.02), Vector3(0.30, uy + 0.09, 0.37), s["metal"])  # key switch
		_slats(root, Vector3(0.022, 0.048, 0.013), Vector3(-0.27, uy + 0.085, 0.38), Vector3(0.035, 0, 0), 15, s["dark"])
	for x: float in [-0.37, 0.37]:
		_box(root, Vector3(0.035, 1.88, 0.045), Vector3(x, 1.0, 0.365), s["metal"])
		_slats(root, Vector3(0.018, 0.022, 0.013), Vector3(x, 0.2, 0.395), Vector3(0, 0.08, 0), 21, s["dark"])
	for x: float in [-0.22, 0.0, 0.22]:
		_cable(root, [Vector3(x, 1.75, -0.36), Vector3(x + 0.04, 1.45, -0.39), Vector3(x + 0.04, 0.2, -0.39), Vector3(x, 0.1, -0.3)], 0.012, s["cone"] if x == 0.0 else s["plastic"])
	_box(root, Vector3(0.70, 0.05, 0.16), Vector3(0, 2.10, -0.1), s["frame"])  # cable tray
	_cable(root, [Vector3(-0.3, 2.13, -0.1), Vector3(0.0, 2.18, -0.12), Vector3(0.3, 2.13, -0.1)], 0.018, s["dark"])
	_cable(root, [Vector3(-0.3, 2.13, -0.06), Vector3(0.05, 2.17, -0.08), Vector3(0.3, 2.13, -0.06)], 0.014, s["plastic"])
	return root


static func build_table() -> Node3D:
	"""Break-room table: scarred top, four legs, one leftover tray. Origin at floor."""
	var s := get_shared()
	var root := Node3D.new()
	root.name = "Table"
	_box(root, Vector3(1.5, 0.07, 0.9), Vector3(0, 0.73, 0), s["door"])
	for lx: float in [-0.65, 0.65]:
		for lz: float in [-0.35, 0.35]:
			_box(root, Vector3(0.07, 0.70, 0.07), Vector3(lx, 0.35, lz), s["frame"])
	_box(root, Vector3(0.45, 0.03, 0.32), Vector3(-0.35, 0.785, 0.1), s["plastic"])  # tray
	_cyl(root, 0.035, 0.03, 0.09, Vector3(0.42, 0.81, -0.15), s["cone"])  # mug
	return root


static func build_shelf() -> Node3D:
	"""Archive shelf: steel uprights, 3 shelves, archive boxes. Faces +Z."""
	var s := get_shared()
	var root := Node3D.new()
	root.name = "Shelf"
	for sx: float in [-0.7, 0.7]:
		_box(root, Vector3(0.06, 1.9, 0.45), Vector3(sx, 0.95, 0), s["frame"])
	for sy: float in [0.15, 0.85, 1.55]:
		_box(root, Vector3(1.46, 0.05, 0.45), Vector3(0, sy, 0), s["frame"])
	var bx: float = -0.55
	while bx < 0.6:
		var bh: float = 0.28 + fmod(absf(bx) * 7.0, 0.14)
		_box(root, Vector3(0.22, bh, 0.34), Vector3(bx, 0.175 + bh / 2.0, 0), s["cardboard"])
		_box(root, Vector3(0.20, 0.24, 0.32), Vector3(bx + 0.05, 0.995, 0), s["door"])
		bx += 0.30
	return root


static func build_scrap_stand() -> Node3D:
	"""Floor stand holding one margin note at reading height. Faces +Z."""
	var s := get_shared()
	var root := Node3D.new()
	root.name = "ScrapStand"
	_box(root, Vector3(0.4, 0.05, 0.3), Vector3(0, 0.025, 0), s["dark"])
	_box(root, Vector3(0.06, 1.15, 0.06), Vector3(0, 0.6, -0.05), s["frame"])
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.83, 0.77, 0.62)
	paper.roughness = 0.95
	var sheet := _box(root, Vector3(0.30, 0.40, 0.015), Vector3(0, 1.25, 0), paper)
	sheet.rotation.x = -0.25
	return root


static func build_way_plate(text: String) -> Node3D:
	"""Amber wayfinding plate, numbered like the field stations. Faces +Z, arrow along +X."""
	var s := get_shared()
	var root := Node3D.new()
	root.name = "WayPlate"
	_box(root, Vector3(0.95, 0.30, 0.06), Vector3(0, 0, 0), s["dark"])
	_box(root, Vector3(0.99, 0.34, 0.03), Vector3(0, 0, -0.02), s["frame"])
	var label := Label3D.new()
	label.text = text
	label.font_size = 72
	label.pixel_size = 0.004
	label.modulate = Color(1.0, 0.72, 0.30)
	label.outline_size = 4
	label.position = Vector3(0, 0, 0.05)
	root.add_child(label)
	return root


static func build_cone() -> Node3D:
	var s := get_shared()
	var root := Node3D.new()
	root.name = "Cone"
	_box(root, Vector3(0.34, 0.04, 0.34), Vector3(0, 0.02, 0), s["cone"])
	# Chamfered base plate reads as a molded rubber foot, not a raw box.
	_box(root, Vector3(0.30, 0.035, 0.30), Vector3(0, 0.058, 0), s["cone"])
	_cyl(root, 0.03, 0.15, 0.52, Vector3(0, 0.3, 0), s["cone"])
	if not _shared.has("stripe"):
		var stripe := StandardMaterial3D.new()
		stripe.albedo_color = Color(0.85, 0.85, 0.82)
		stripe.roughness = 0.4
		_shared["stripe"] = stripe
		s = get_shared()
	_cyl(root, 0.082, 0.095, 0.09, Vector3(0, 0.32, 0), s["stripe"])
	# Dark scuffed tip.
	_cyl(root, 0.0305, 0.036, 0.05, Vector3(0, 0.545, 0), s["dark"])
	return root


static func build_pickup(kind: String, stream: AudioStream) -> Pickup:
	"""Water = translucent jug bottle; bread = flat brown loaf. Origin at floor."""
	var s := get_shared()
	var root := Pickup.new()
	root.name = "PickupWater" if kind == "water" else "PickupBread"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.4, 0.7, 0.4)
	cs.shape = bs
	cs.position = Vector3(0, 0.35, 0)
	root.add_child(cs)
	var visual := Node3D.new()
	visual.position = Vector3(0, 0.35, 0)
	root.add_child(visual)
	if kind == "water":
		_cyl(visual, 0.09, 0.10, 0.30, Vector3(0, 0, 0), s["jug"])
		_box(visual, Vector3(0.21, 0.10, 0.21), Vector3(0, 0.02, 0), s["frame"])
		_cyl(visual, 0.04, 0.04, 0.06, Vector3(0, 0.18, 0), s["plastic"])
	else:
		_box(visual, Vector3(0.24, 0.10, 0.15), Vector3(0, 0, 0), s["door"])
		_box(visual, Vector3(0.20, 0.02, 0.04), Vector3(0, 0.055, 0), s["cardboard"])
	var ring := MeshInstance3D.new()
	ring.name = "GlowRing"
	var rq := QuadMesh.new()
	rq.size = Vector2(0.55, 0.55)
	ring.mesh = rq
	ring.material_override = s["ring_water" if kind == "water" else "ring_bread"]
	ring.rotation.x = -PI / 2.0
	ring.position = Vector3(0, 0.02, 0)
	root.add_child(ring)
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = stream
	sfx.max_distance = 8.0
	root.add_child(sfx)
	root.setup(kind, visual, sfx)
	return root


static func build_desk(screen_tex: Texture2D) -> Node3D:
	"""Office desk with a dead-but-glowing monitor. Origin at floor."""
	var s := get_shared()
	var root := Node3D.new()
	root.name = "Desk"
	_box(root, Vector3(1.4, 0.06, 0.7), Vector3(0, 0.74, 0), s["door"])
	for lx: float in [-0.6, 0.6]:
		for lz: float in [-0.28, 0.28]:
			_cyl(root, 0.038, 0.022, 0.70, Vector3(lx, 0.37, lz), s["dark"])
			_cyl(root, 0.028, 0.03, 0.03, Vector3(lx, 0.015, lz), s["plastic"])
	_box(root, Vector3(1.28, 0.40, 0.04), Vector3(0, 0.50, -0.28), s["door"])  # modesty panel
	_cable(root, [Vector3(0, 1.0, -0.28), Vector3(0.1, 0.72, -0.29), Vector3(0.35, 0.60, -0.30), Vector3(0.62, 0.58, -0.30)], 0.007, s["dark"])
	_box(root, Vector3(0.40, 0.62, 0.50), Vector3(0.45, 0.31, 0.0), s["door"])  # drawer unit
	for dy: float in [0.18, 0.38, 0.55]:
		_box(root, Vector3(0.20, 0.025, 0.02), Vector3(0.45, dy, 0.26), s["metal"])  # pulls
	_box(root, Vector3(0.5, 0.34, 0.06), Vector3(0, 1.0, -0.15), s["plastic"])
	_box(root, Vector3(0.06, 0.20, 0.06), Vector3(0, 0.88, -0.15), s["dark"])  # monitor neck
	var screen_mat := StandardMaterial3D.new()
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mat.albedo_texture = screen_tex
	screen_mat.albedo_color = Color(1.4, 1.4, 1.4)
	var screen := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.44, 0.28)
	screen.mesh = qm
	screen.material_override = screen_mat
	screen.position = Vector3(0, 1.0, -0.11)
	root.add_child(screen)
	_box(root, Vector3(0.2, 0.03, 0.16), Vector3(0, 0.79, -0.15), s["dark"])
	_box(root, Vector3(0.45, 0.025, 0.16), Vector3(-0.05, 0.785, 0.12), s["dark"])  # keyboard
	_cyl(root, 0.04, 0.035, 0.10, Vector3(-0.45, 0.82, 0.10), s["cone"])  # mug
	_cyl(root, 0.033, 0.033, 0.003, Vector3(-0.45, 0.871, 0.10), s["dark"])  # hollow mouth
	_box(root, Vector3(1.36, 0.02, 0.66), Vector3(0, 0.78, 0), s["door"])  # eased top edge
	for row: int in 3:
		_slats(root, Vector3(0.027, 0.008, 0.026), Vector3(-0.24, 0.802, 0.07 + float(row) * 0.035), Vector3(0.035, 0, 0), 12, s["plastic"])
	_slats(root, Vector3(0.024, 0.10, 0.012), Vector3(-0.18, 1.0, -0.188), Vector3(0.04, 0, 0), 10, s["dark"])
	_cable(root, [Vector3(0, 0.94, -0.19), Vector3(0.06, 0.80, -0.26), Vector3(0.18, 0.78, -0.36), Vector3(0.18, 0.38, -0.36), Vector3(0.24, 0.06, -0.31)], 0.008, s["dark"])
	return root
