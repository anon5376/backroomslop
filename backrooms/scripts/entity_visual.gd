extends Node3D
## Presentation only. +Z is forward, matching Stalker's unchanged steering.
## The hollow, split-keel anatomy is built from profiled surfaces, not boxes.
## No processing, physics, RNG, target selection or replicated state lives here.

const UPPER_LEG: float = 0.54
const LOWER_LEG: float = 0.56
const STRIDE: float = 1.65
const STANCE: float = 0.58

var spine: Node3D
var chest: Node3D
var head: Node3D
var jaw: Node3D
var eye_material: StandardMaterial3D
var eye_light: OmniLight3D
var arms: Array[Node3D] = []
var elbows: Array[Node3D] = []
var wrists: Array[Node3D] = []
var fingers: Array[Node3D] = []
var thighs: Array[Node3D] = []
var knees: Array[Node3D] = []
var feet: Array[Node3D] = []
var ribs: Array[Node3D] = []
var foot_anchors: Array[Vector3] = []
var swing_starts: Array[Vector3] = []
var foot_yaws: Array[float] = [0.0, 0.0]
var planted: Array[bool] = [true, true]
var phase: float = 0.0
var clock: float = 0.0
var hunt_blend: float = 0.0
var move_blend: float = 0.0
var _last_position: Vector3
var _initialized: bool = false
var _speed: float = 0.0
var _head_yaw: float = 0.0
var _last_state: int = -1
var _anticipation: float = 0.0
var _skin: ShaderMaterial
var _bone: StandardMaterial3D
var _dark: StandardMaterial3D
var _mesh_cache: Dictionary = {}


func build() -> void:
	_skin = ShaderMaterial.new()
	_skin.shader = preload("res://shaders/entity_static.gdshader")
	_skin.set_shader_parameter("base_color", Color(0.025, 0.028, 0.032))
	_skin.set_shader_parameter("static_amount", 0.16)
	_bone = StandardMaterial3D.new()
	_bone.albedo_color = Color(0.24, 0.25, 0.22)
	_bone.roughness = 0.78
	_dark = StandardMaterial3D.new()
	_dark.albedo_color = Color(0.004, 0.006, 0.008)
	_dark.roughness = 1.0
	eye_material = StandardMaterial3D.new()
	eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_material.albedo_color = Color(0.45, 0.04, 0.03)
	# Pelvic arches leave a visible central gap; the narrow trunk opens into ribs.
	for side: float in [-1.0, 1.0]:
		_curve(self, [Vector3(0, 0.90, -0.03), Vector3(side * 0.16, 0.99, -0.04), Vector3(side * 0.19, 0.88, 0.02), Vector3(side * 0.10, 0.82, 0.04)], 0.045, _skin)
	spine = joint(self, "Spine", Vector3(0, 0.91, -0.025))
	_shape(spine, "Waist", Vector3(0, 0.19, 0), Vector3(0.12, 0.43, 0.14), _skin)
	for i: int in 8:
		var y: float = 0.05 + i * 0.073
		_shape(spine, "Vertebra%d" % i, Vector3(0, y, -0.065 - sin(i * 0.4) * 0.025), Vector3(0.085, 0.048, 0.10), _bone)
		_link(spine, Vector3(0, y, -0.09), Vector3(0, y + 0.035, -0.17), 0.021, 0.002, _skin)
	chest = joint(spine, "RibCage", Vector3(0, 0.40, 0))
	# Paired ribs sweep out, forward, then inward. The sternum is split, not a slab.
	for side: float in [-1.0, 1.0]:
		for i: int in 5:
			var rib := joint(chest, "Rib_%s_%d" % [str(side), i], Vector3(0, 0.055 + i * 0.073, -0.055))
			var width: float = 0.18 + sin(float(i + 1) / 6.0 * PI) * 0.075
			_curve(rib, [Vector3.ZERO, Vector3(side * width * 0.65, 0.034, -0.03), Vector3(side * width, 0.013, 0.05), Vector3(side * width * 0.84, -0.035, 0.17), Vector3(side * 0.055, -0.055, 0.20)], 0.020 + i * 0.001, _skin)
			ribs.append(rib)
		_link(chest, Vector3(side * 0.04, 0.025, 0.14), Vector3(side * 0.06, 0.39, 0.12), 0.018, 0.027, _bone)
		_curve(chest, [Vector3(side * 0.04, 0.40, 0), Vector3(side * 0.18, 0.43, -0.015), Vector3(side * 0.30, 0.35, -0.015)], 0.035, _skin)
		_shape(chest, "Scapula", Vector3(side * 0.15, 0.28, -0.095), Vector3(0.13, 0.23, 0.055), _skin)
	# A forward-canted neck and a long, cleft mask, with recessed sockets.
	_curve(chest, [Vector3(0, 0.37, -0.025), Vector3(0, 0.49, -0.04), Vector3(0, 0.54, 0.035)], 0.045, _skin)
	head = joint(chest, "Head", Vector3(0, 0.51, 0.025))
	_shape(head, "Occiput", Vector3(0, 0.145, -0.045), Vector3(0.19, 0.31, 0.19), _skin)
	for side: float in [-1.0, 1.0]:
		var plate := _shape(head, "MaskPlate", Vector3(side * 0.063, 0.14, 0.058), Vector3(0.10, 0.27, 0.12), _bone)
		plate.rotation.z = side * 0.11
		_shape(head, "EyeSocket", Vector3(side * 0.057, 0.165, 0.115), Vector3(0.078, 0.053, 0.025), _dark)
		var eye := _shape(head, "EyeSlit", Vector3(side * 0.057, 0.165, 0.13), Vector3(0.039, 0.009, 0.009), eye_material)
		eye.rotation.z = side * 0.16
		_curve(head, [Vector3(side * 0.015, 0.195, 0.12), Vector3(side * 0.066, 0.202, 0.125), Vector3(side * 0.115, 0.18, 0.072)], 0.018, _skin)
		_link(head, Vector3(side * 0.11, 0.12, 0.045), Vector3(side * 0.066, 0.033, 0.12), 0.027, 0.012, _skin)
	_link(head, Vector3(0, 0.19, 0.116), Vector3(0, 0.075, 0.147), 0.015, 0.004, _skin)
	# Hunt eye-light: ember glow spilling from the sockets. No shadow, one light.
	eye_light = OmniLight3D.new()
	eye_light.name = "EyeLight"
	eye_light.light_color = Color(1.0, 0.12, 0.08)
	eye_light.light_energy = 0.0
	eye_light.omni_range = 6.0
	eye_light.omni_attenuation = 1.0
	eye_light.shadow_enabled = false
	eye_light.position = Vector3(0, 0.165, 0.30)
	head.add_child(eye_light)
	_shape(head, "MouthCavity", Vector3(0, 0.034, 0.064), Vector3(0.115, 0.085, 0.09), _dark)
	jaw = joint(head, "Jaw", Vector3(0, 0.054, 0.015))
	_curve(jaw, [Vector3(-0.078, 0, 0), Vector3(-0.066, -0.066, 0.09), Vector3(0, -0.08, 0.124), Vector3(0.066, -0.066, 0.09), Vector3(0.078, 0, 0)], 0.018, _bone)
	for i: int in 7:
		var x: float = (i - 3) * 0.016
		_link(head, Vector3(x, 0.054, 0.117), Vector3(x, 0.028 - (i % 2) * 0.01, 0.12), 0.006, 0.001, _bone)
		_link(jaw, Vector3(x, -0.065, 0.105), Vector3(x, -0.045 + (i % 2) * 0.006, 0.108), 0.005, 0.001, _bone)
	for i: int in 2:
		_build_arm(i)
		_build_leg(i)


func _build_arm(index: int) -> void:
	var side: float = -1.0 if index == 0 else 1.0
	var upper: float = 0.57 if index == 0 else 0.49
	var lower: float = 0.51 if index == 0 else 0.45
	var arm := joint(chest, "Shoulder%d" % index, Vector3(side * 0.29, 0.34, -0.01))
	arms.append(arm)
	_shape(arm, "ShoulderCap", Vector3.ZERO, Vector3(0.15, 0.16, 0.15), _skin)
	_link(arm, Vector3(0, -0.025, 0), Vector3(side * 0.018, -upper, 0), 0.063, 0.027, _skin)
	_link(arm, Vector3(side * 0.023, -0.10, 0.045), Vector3(side * 0.026, -upper + 0.04, 0.025), 0.013, 0.009, _bone)
	var elbow := joint(arm, "Elbow", Vector3(side * 0.018, -upper, 0))
	elbows.append(elbow)
	_shape(elbow, "ElbowHinge", Vector3.ZERO, Vector3(0.08, 0.075, 0.09), _bone)
	_link(elbow, Vector3(0, 0, -0.025), Vector3(0, 0.065, -0.105), 0.025, 0.002, _skin)
	for fork: float in [-1.0, 1.0]:
		_curve(elbow, [Vector3(fork * 0.017, -0.015, 0), Vector3(fork * 0.030, -lower * 0.4, 0.014), Vector3(fork * 0.015, -lower, 0)], 0.018, _skin)
	var wrist := joint(elbow, "Wrist", Vector3(0, -lower, 0))
	wrists.append(wrist)
	_shape(wrist, "Palm", Vector3(0, -0.053, 0), Vector3(0.11, 0.13, 0.05), _skin)
	for digit: int in 4:
		var length: float = 0.065 + sin((digit + 1) * 0.65) * 0.025
		var knuckle := joint(wrist, "Finger%d" % digit, Vector3((digit - 1.5) * 0.027, -0.105, 0))
		knuckle.rotation.z = (digit - 1.5) * 0.12
		for segment: int in 3:
			fingers.append(knuckle)
			_link(knuckle, Vector3.ZERO, Vector3(0, -length, 0), 0.011 - segment * 0.0025, 0.007 - segment * 0.002, _skin if segment < 2 else _bone)
			if segment < 2:
				_shape(knuckle, "Knuckle", Vector3.ZERO, Vector3.ONE * 0.023, _bone)
				knuckle = joint(knuckle, "Phalanx", Vector3(0, -length, 0))
				length *= 0.82
		var tendon_x: float = (digit - 1.5) * 0.027
		_link(wrist, Vector3(tendon_x * 0.4, 0, -0.025), Vector3(tendon_x, -0.10, -0.025), 0.005, 0.004, _bone)
	var thumb := joint(wrist, "Thumb", Vector3(-side * 0.047, -0.032, 0))
	thumb.rotation.z = -side * 0.72
	_link(thumb, Vector3.ZERO, Vector3(0, -0.075, 0), 0.015, 0.010, _skin)
	var tip := joint(thumb, "ThumbTip", Vector3(0, -0.075, 0))
	tip.rotation.x = -0.65
	_link(tip, Vector3.ZERO, Vector3(0, -0.055, 0), 0.01, 0.001, _bone)


func _build_leg(index: int) -> void:
	var side: float = -1.0 if index == 0 else 1.0
	var thigh := joint(self, "Hip%d" % index, Vector3(side * 0.125, 0.90, 0))
	thighs.append(thigh)
	_shape(thigh, "HipJoint", Vector3.ZERO, Vector3(0.10, 0.12, 0.11), _skin)
	_link(thigh, Vector3.ZERO, Vector3(0, -UPPER_LEG, 0), 0.069, 0.030, _skin)
	var knee := joint(thigh, "Knee", Vector3(0, -UPPER_LEG, 0))
	knees.append(knee)
	_shape(knee, "KneeShield", Vector3(0, 0, 0.025), Vector3(0.09, 0.12, 0.09), _bone)
	_link(knee, Vector3.ZERO, Vector3(0, -LOWER_LEG, 0), 0.042, 0.022, _skin)
	_link(knee, Vector3(side * 0.028, -0.06, -0.025), Vector3(side * 0.020, -LOWER_LEG, -0.01), 0.011, 0.007, _bone)
	var foot := joint(knee, "Ankle", Vector3(0, -LOWER_LEG, 0))
	feet.append(foot)
	_shape(foot, "Heel", Vector3(0, 0, -0.018), Vector3(0.09, 0.09, 0.13), _skin)
	_shape(foot, "Instep", Vector3(0, 0.004, 0.07), Vector3(0.10, 0.095, 0.22), _skin)
	for toe: int in 3:
		var x: float = (toe - 1) * 0.034
		_curve(foot, [Vector3(x, -0.008, 0.11), Vector3(x * 1.18, -0.016, 0.18), Vector3(x * 1.25, -0.023, 0.22 - absf(x))], 0.012, _bone)
	foot_anchors.append(Vector3.ZERO)
	swing_starts.append(Vector3.ZERO)


func animate(delta: float, state: int, motion: Vector3, replica: bool, look_direction: Vector3) -> bool:
	if delta <= 0.0:
		return false
	clock += delta
	var origin: Vector3 = global_position
	var displacement: Vector3 = origin - _last_position
	displacement.y = 0.0
	# Spawns, flicker teleports and long inactive intervals must not drag old feet.
	var reset: bool = not _initialized or displacement.length() > 1.5 or delta > 0.25
	if reset:
		_reset_feet()
		_speed = 0.0
	_last_position = origin
	_initialized = true
	var speed: float = Vector2(motion.x, motion.z).length()
	if replica:
		speed = minf(displacement.length() / maxf(delta, 0.001), 6.0) if not reset else 0.0
	_speed = lerpf(_speed, speed, 1.0 - exp(-delta * 12.0))
	var hot: bool = state == 2
	hunt_blend = lerpf(hunt_blend, 1.0 if hot else 0.0, 1.0 - exp(-delta * 7.0))
	move_blend = lerpf(move_blend, clampf(_speed / 1.5, 0.0, 1.0), 1.0 - exp(-delta * 10.0))
	if state != _last_state:
		_anticipation = 1.0
		_last_state = state
	_anticipation = maxf(0.0, _anticipation - delta * 2.3)
	var breath: float = sin(clock * lerpf(1.65, 4.1, hunt_blend))
	var gait: float = sin(phase * TAU)
	spine.rotation = Vector3(-0.025 - hunt_blend * 0.23 + breath * 0.012, gait * move_blend * 0.055, sin(clock * 0.7) * 0.018 + gait * move_blend * 0.035)
	spine.position.y = 0.91 - hunt_blend * 0.035 + breath * 0.006 - absf(gait) * move_blend * 0.025
	chest.rotation.y = -gait * move_blend * 0.085
	for i: int in ribs.size():
		var side: float = -1.0 if i < 5 else 1.0
		ribs[i].rotation.z = side * breath * (0.012 + (i % 5) * 0.002)
	# Head leads body steering; quantized micro-saccades retain the original unease
	# without stop-motion feet. Clamp to anatomical limits rather than rotating AI.
	var desired_yaw: float = 0.0
	if look_direction.length_squared() > 0.001:
		desired_yaw = clampf(atan2(look_direction.x, look_direction.z), -0.85, 0.85)
	_head_yaw = lerp_angle(_head_yaw, desired_yaw, 1.0 - exp(-delta * 13.0))
	var saccade: float = sin(floor(clock * 3.0) * 2.399) * 0.035
	head.rotation = Vector3(hunt_blend * 0.18 - _anticipation * 0.10 + breath * 0.012, _head_yaw + saccade, lerpf(0.16 + sin(clock * 0.58) * 0.12, -0.045, hunt_blend))
	jaw.rotation.x = -hunt_blend * (0.48 + breath * 0.06) - _anticipation * 0.08
	eye_material.albedo_color = Color(0.45, 0.04, 0.03).lerp(Color(4.0, 0.15, 0.1), hunt_blend)
	if is_instance_valid(eye_light):
		var stalk_ember: float = 0.3 if (state == 1 or state == 3) else 0.0
		eye_light.light_energy = 1.5 * hunt_blend + stalk_ember
	for i: int in 2:
		var side: float = -1.0 if i == 0 else 1.0
		arms[i].rotation = Vector3(-0.10 - hunt_blend * 0.85 + side * gait * move_blend * 0.29 + breath * 0.018, side * hunt_blend * 0.12, -side * (0.13 + hunt_blend * 0.12))
		elbows[i].rotation.x = -0.12 - hunt_blend * 0.42 - maxf(0.0, -side * gait) * move_blend * 0.24
		wrists[i].rotation = Vector3(-0.18 - hunt_blend * 0.23 + sin(clock * 1.1 + i) * 0.04, 0, side * 0.16)
	for i: int in fingers.size():
		fingers[i].rotation.x = -0.12 - hunt_blend * (0.27 + (i % 3) * 0.11) + sin(clock * 1.7 + floorf(i / 3.0) * 0.7) * 0.065
	var landed: bool = false
	if _speed > 0.08:
		phase = fposmod(phase + delta * _speed / STRIDE, 1.0)
	for i: int in 2:
		landed = _animate_leg(i, state, reset) or landed
	return landed


func _reset_feet() -> void:
	phase = 0.0
	for i: int in 2:
		var side: float = -1.0 if i == 0 else 1.0
		foot_anchors[i] = to_global(Vector3(side * 0.14, 0.055, 0.04))
		swing_starts[i] = foot_anchors[i]
		foot_yaws[i] = global_rotation.y
		planted[i] = true


func _animate_leg(index: int, state: int, reset: bool) -> bool:
	var side: float = -1.0 if index == 0 else 1.0
	var cycle: float = fposmod(phase + index * 0.5, 1.0)
	var in_stance: bool = cycle < STANCE or _speed <= 0.08 or reset
	var landed: bool = false
	var target: Vector3 = foot_anchors[index]
	var roll: float = 0.0
	if not in_stance:
		if planted[index]:
			swing_starts[index] = foot_anchors[index]
			planted[index] = false
		var t: float = (cycle - STANCE) / (1.0 - STANCE)
		var reach: float = lerpf(0.20, 0.44, clampf(_speed / 4.8, 0.0, 1.0))
		var landing: Vector3 = to_global(Vector3(side * 0.14, 0.055, reach))
		target = swing_starts[index].lerp(landing, t * t * (3.0 - 2.0 * t))
		target.y += sin(t * PI) * (0.19 if state == 2 else 0.075)
		foot_anchors[index] = target
		foot_yaws[index] = lerp_angle(foot_yaws[index], global_rotation.y, t)
		roll = sin(t * TAU) * 0.18
	elif not planted[index]:
		# Snap only the last few millimetres of swing to the floor on contact.
		target.y = global_position.y + 0.055
		foot_anchors[index] = target
		planted[index] = true
		landed = true
	var local_target: Vector3 = to_local(target)
	# Replant on large turns or corrections before an anchored leg overextends.
	var hip: Vector3 = Vector3(side * 0.125, 0.90 - hunt_blend * 0.035, 0)
	if (local_target - hip).length() > UPPER_LEG + LOWER_LEG - 0.01:
		local_target = Vector3(side * 0.14, 0.055, 0.03)
		foot_anchors[index] = to_global(local_target)
		foot_yaws[index] = global_rotation.y
		planted[index] = true
	# Analytic two-bone IK. Left knee folds back, right knee forward.
	var offset: Vector3 = local_target - hip
	var distance: float = clampf(offset.length(), 0.05, UPPER_LEG + LOWER_LEG - 0.001)
	var direction: Vector3 = offset.normalized()
	var pole: Vector3 = Vector3(side * 0.15, 0, -1.0 if index == 0 else 1.0)
	pole = (pole - direction * pole.dot(direction)).normalized()
	var along: float = (UPPER_LEG * UPPER_LEG - LOWER_LEG * LOWER_LEG + distance * distance) / (2.0 * distance)
	var bend: float = sqrt(maxf(0.0, UPPER_LEG * UPPER_LEG - along * along))
	var knee_position: Vector3 = hip + direction * along + pole * bend
	thighs[index].transform = Transform3D(_down_basis(knee_position - hip), hip)
	knees[index].global_transform = global_transform * Transform3D(_down_basis(local_target - knee_position), knee_position)
	feet[index].global_transform = Transform3D(Basis(Vector3.UP, foot_yaws[index]) * Basis(Vector3.RIGHT, roll), to_global(local_target))
	return landed


func joint(parent: Node3D, label: String, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = label
	node.position = pos
	parent.add_child(node)
	return node


func _down_basis(direction: Vector3) -> Basis:
	var y: Vector3 = -direction.normalized()
	var reference: Vector3 = Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x: Vector3 = y.cross(reference).normalized()
	return Basis(x, y, x.cross(y).normalized())


func _shape(parent: Node3D, label: String, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.mesh = _profile_mesh(0.12, 0.12, true)
	mesh.material_override = material
	mesh.position = pos
	mesh.scale = size
	parent.add_child(mesh)
	return mesh


func _link(parent: Node3D, a: Vector3, b: Vector3, start_radius: float, end_radius: float, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _profile_mesh(start_radius, end_radius, false)
	mesh.material_override = material
	mesh.transform = Transform3D(_down_basis(b - a).scaled_local(Vector3(1, a.distance_to(b), 1)), (a + b) * 0.5)
	parent.add_child(mesh)


func _curve(parent: Node3D, points: Array, radius: float, material: Material) -> void:
	for i: int in points.size() - 1:
		_link(parent, points[i], points[i + 1], radius * (1.0 - float(i) / points.size() * 0.35), radius * (1.0 - float(i + 1) / points.size() * 0.35), material)


func _profile_mesh(start_radius: float, end_radius: float, rounded: bool) -> ArrayMesh:
	var key := Vector3(start_radius, end_radius, 1.0 if rounded else 0.0)
	if _mesh_cache.has(key):
		return _mesh_cache[key] as ArrayMesh
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	const SIDES: int = 10
	const RINGS: int = 7
	for ring: int in RINGS:
		var t: float = float(ring) / (RINGS - 1)
		var radius: float = lerpf(start_radius, end_radius, t) * (0.82 + sin(t * PI) * 0.18)
		if rounded:
			radius = maxf(0.012, sin(t * PI) * 0.5)
		for sector: int in SIDES + 1:
			var u: float = float(sector) / SIDES
			var angle: float = u * TAU
			# Subtle longitudinal fluting breaks the perfect-cylinder highlight.
			var flute: float = 1.0 + cos(angle * 3.0) * 0.055 * sin(t * PI)
			vertices.append(Vector3(cos(angle) * radius * flute, 0.5 - t, sin(angle) * radius * flute))
			uvs.append(Vector2(u, t))
	for ring: int in RINGS - 1:
		for sector: int in SIDES:
			var a: int = ring * (SIDES + 1) + sector
			var b: int = a + SIDES + 1
			indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	# End caps also close the narrow tips so silhouettes never expose open tubes.
	for sector: int in range(1, SIDES - 1):
		indices.append_array(PackedInt32Array([0, sector + 1, sector]))
		var base: int = (RINGS - 1) * (SIDES + 1)
		indices.append_array(PackedInt32Array([base, base + sector, base + sector + 1]))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in vertices.size():
		surface.set_uv(uvs[i])
		surface.set_smooth_group(0)
		surface.add_vertex(vertices[i])
	# Godot uses clockwise front faces; reverse each construction triangle.
	for triangle: int in range(0, indices.size(), 3):
		surface.add_index(indices[triangle])
		surface.add_index(indices[triangle + 2])
		surface.add_index(indices[triangle + 1])
	surface.generate_normals()
	var result: ArrayMesh = surface.commit()
	_mesh_cache[key] = result
	return result
