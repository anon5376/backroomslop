extends Node
## Headless presentation contracts: anatomy, contacts, IK, teleports and replicas.
const EntityScene := preload("res://scenes/entity.tscn")
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		print("ENTITY VISUAL PASS ", label)
	else:
		failures += 1
		printerr("ENTITY VISUAL FAIL ", label)

func _run() -> void:
	var entity: Stalker = EntityScene.instantiate()
	add_child(entity)
	entity.set_physics_process(false)
	var visual = entity._visual
	check(entity.get_node("CollisionShape3D").shape is CapsuleShape3D, "original collider retained")
	check(visual.ribs.size() == 10 and visual.fingers.size() == 24, "open ribs and three articulated segments per finger")
	check(visual.arms.size() == 2 and visual.feet.size() == 2 and visual.wrists.size() == 2, "complete articulated rig")
	var mesh_nodes: Array[Node] = visual.find_children("*", "MeshInstance3D", true, false)
	var profiled: bool = true
	var finite_normals: bool = true
	var outward_normals: bool = true
	for node: MeshInstance3D in mesh_nodes:
		profiled = profiled and node.mesh is ArrayMesh
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i: int in vertices.size():
			finite_normals = finite_normals and normals[i].is_finite()
			if absf(vertices[i].y) < 0.1:
				outward_normals = outward_normals and Vector3(vertices[i].x, 0, vertices[i].z).dot(normals[i]) > 0.0
	check(profiled and mesh_nodes.size() > 100, "profiled anatomy replaces primitive meshes")
	check(finite_normals and outward_normals, "surface normals are finite and outward")
	visual.animate(1.0 / 60.0, 0, Vector3.ZERO, false, Vector3.FORWARD)
	var idle_foot: Vector3 = visual.feet[0].global_position
	var idle_rib: float = visual.ribs[0].rotation.z
	for i: int in 60:
		visual.animate(1.0 / 60.0, 1, Vector3.ZERO, false, Vector3(1, 0, 2))
	check(visual.feet[0].global_position.distance_to(idle_foot) < 0.0001, "stationary stalk feet stay planted")
	check(absf(visual.ribs[0].rotation.z - idle_rib) > 0.001, "breathing articulates ribs")
	check(visual.head.rotation.y > 0.3, "head anticipates target without steering body")
	check(entity.rotation == Vector3.ZERO and entity.state == Stalker.State.DORMANT, "presentation does not mutate AI or heading")
	var contacts: int = 0
	var stable_contacts: int = 0
	var finite_pose: bool = true
	var correct_lengths: bool = true
	var max_lift: float = 0.0
	for frame: int in 300:
		entity.position.z += 4.8 / 60.0
		var before: Vector3 = visual.feet[0].global_position
		var was_planted: bool = visual.planted[0]
		if visual.animate(1.0 / 60.0, 2, Vector3(0, 0, 4.8), false, Vector3(0.5, 0, 1)):
			contacts += 1
		if was_planted and visual.planted[0] and visual.feet[0].global_position.distance_to(before - Vector3(0, 0, 4.8 / 60.0)) < 0.0002:
			stable_contacts += 1
		for i: int in 2:
			finite_pose = finite_pose and visual.feet[i].global_transform.is_finite() and visual.knees[i].global_transform.is_finite()
			correct_lengths = correct_lengths and absf(visual.thighs[i].global_position.distance_to(visual.knees[i].global_position) - visual.UPPER_LEG) < 0.001
			correct_lengths = correct_lengths and absf(visual.knees[i].global_position.distance_to(visual.feet[i].global_position) - visual.LOWER_LEG) < 0.001
			max_lift = maxf(max_lift, visual.feet[i].position.y)
	check(contacts >= 20 and stable_contacts > 40, "distance-driven hunt alternates contacts with world-space stance")
	check(finite_pose and correct_lengths, "two-bone IK retains segment lengths throughout hunt")
	check(visual.hunt_blend > 0.99 and visual.jaw.rotation.x < -0.3, "hunt opens jaw and blends aggressive pose")
	var hunt_lift: float = _sample_lift(entity, 2)
	var stalk_lift: float = _sample_lift(entity, 1)
	check(hunt_lift > stalk_lift + 0.07, "hunt lift differs from low stalking step")
	entity.position += Vector3(20, 0, -30)
	visual.animate(1.0 / 60.0, 1, Vector3.ZERO, true, Vector3.ZERO)
	check(visual.feet[0].global_position.distance_to(entity.global_position) < 0.4 and visual.planted[0], "teleport resets anchors without stretched limbs")
	var phase_before: float = visual.phase
	for frame: int in 120:
		if frame % 4 == 0:
			entity.position.z += 4.8 / 15.0
		visual.animate(1.0 / 60.0, 2, Vector3.ZERO, true, Vector3.ZERO)
	check(visual.move_blend > 0.5 and absf(visual.phase - phase_before) > 0.01, "15 Hz network displacement animates zero-velocity replica")
	entity.puppet = true
	entity.active = false
	var clock_before: float = visual.clock
	entity._physics_process(0.1)
	check(visual.clock == clock_before, "inactive replica preserves lifecycle freeze")
	entity.active = true
	entity._physics_process(0.1)
	check(visual.clock > clock_before and entity.velocity == Vector3.ZERO, "active replica animates without running AI")
	entity.queue_free()
	await get_tree().process_frame
	check(not is_instance_valid(entity), "entity and procedural rig dispose cleanly")
	print("ENTITY VISUAL RESULT ", failures, " failures")
	get_tree().quit(1 if failures else 0)

func _sample_lift(entity: Stalker, state: int) -> float:
	var highest: float = 0.0
	for frame: int in 120:
		entity.position.z += 1.2 / 60.0
		entity._visual.animate(1.0 / 60.0, state, Vector3(0, 0, 1.2), false, Vector3.ZERO)
		for foot: Node3D in entity._visual.feet:
			highest = maxf(highest, foot.global_position.y - entity.global_position.y)
	return highest
