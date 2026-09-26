class_name Player
extends CharacterBody3D
## FPS controller: walk/sprint/crouch, stamina, headbob, flashlight, interact.
## Loudness is gameplay: sprint 18m, walk 7m, crouch 3m noise radii.
## Flashlight is a plain light source: it never stuns, blinds, or repels the entity.

const WALK_SPEED: float = 3.2
const SPRINT_SPEED: float = 5.6
const CROUCH_SPEED: float = 1.6
const NOISE_SPRINT: float = 18.0
const NOISE_WALK: float = 7.0
const NOISE_CROUCH: float = 3.0
const STEP_DIST_WALK: float = 2.2
const STEP_DIST_SPRINT: float = 2.7
const FLASH_RANGE: float = 18.0
const FLASH_BATTERY_DRAIN: float = 1.0 / 480.0  # ~8 min of light per full charge
const FLASH_BATTERY_RECHARGE: float = 1.0 / 60.0  # ~1 min off to refill

var active: bool = false
var remote: bool = false  # puppet replica of the partner (no input/sim/cam)
var downed: bool = false  # dead, escaped or gone — the entity stops targeting
var mouse_sens: float = 0.0022
var stamina: float = 1.0
var crouched: bool = false
var sprinting: bool = false
var _net: Node = null  # NetManager, set by main when in co-op
var _sync_t: int = 0
var _remote_planar: float = 0.0
var _remote_pos: Vector3 = Vector3.ZERO
var _remote_yaw: float = 0.0
var _pitch: float = 0.0
var _bob_phase: float = 0.0
var _step_accum: float = 0.0
var flashlight_on: bool = false
var flash_battery: float = 1.0
var _stand_h: float = 1.8
var _crouch_h: float = 1.15
var _head_stand_y: float = 1.62
var _head_crouch_y: float = 1.05

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var flash_light: SpotLight3D = $Head/Flash
@onready var steps_player: AudioStreamPlayer = $Steps

var audio: AudioManager = null
var game: Node = null
enum View { FIRST, CHASE, FRONT }
var view_mode: int = View.FIRST

var _boom: SpringArm3D
var _cam3: Camera3D
var _boom2: SpringArm3D
var _camf: Camera3D
var _body: Node3D
var _thigh_l: Node3D
var _thigh_r: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _torso: Node3D


func _ready() -> void:
	collision.shape = collision.shape.duplicate()
	if not remote:
		add_to_group("player")
	flash_light.visible = false
	_boom = SpringArm3D.new()
	_boom.spring_length = 3.4
	_boom.margin = 0.3
	head.add_child(_boom)
	_boom.add_excluded_object(get_rid())
	_cam3 = Camera3D.new()
	_cam3.fov = 70.0
	_cam3.far = 200.0
	_boom.add_child(_cam3)
	# Front boom: sits ahead of the player, looks back. Shows what's behind you.
	_boom2 = SpringArm3D.new()
	_boom2.spring_length = 3.0
	_boom2.margin = 0.3
	_boom2.rotation.y = PI
	head.add_child(_boom2)
	_boom2.add_excluded_object(get_rid())
	_camf = Camera3D.new()
	_camf.fov = 70.0
	_camf.far = 200.0
	_boom2.add_child(_camf)
	_build_body()
	_body.visible = remote  # partner avatar is always visible


func _process(delta: float) -> void:
	if not remote:
		return
	# Puppet replica: ease toward the last synced state, animate from it.
	global_position = global_position.lerp(_remote_pos, minf(delta * 12.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _remote_yaw, minf(delta * 12.0, 1.0))
	if _remote_planar > 0.4:
		_bob_phase += delta * (7.0 if sprinting else 5.2)
	_remote_planar = maxf(0.0, _remote_planar - delta * 6.0)
	_tick_body_anim(delta, _remote_planar)


func apply_remote_state(pos: Vector3, yaw: float, p_crouched: bool, p_sprinting: bool, planar: float) -> void:
	_remote_pos = pos
	_remote_yaw = yaw
	crouched = p_crouched
	sprinting = p_sprinting
	_remote_planar = planar


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		rotate_y(-mm.relative.x * mouse_sens)
		_pitch = clampf(_pitch - mm.relative.y * mouse_sens, -1.45, 1.45)
		head.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if remote:
		return
	if not active:
		velocity = Vector3.ZERO
		return
	# Crouch toggle.
	if Input.is_action_just_pressed("crouch"):
		crouched = not crouched
	# 1st / chase / front view cycle.
	if Input.is_action_just_pressed("toggle_view"):
		cycle_view()
	# Height blend.
	var target_h: float = _crouch_h if crouched else _stand_h
	var cap := collision.shape as CapsuleShape3D
	if cap != null:
		cap.height = lerpf(cap.height, target_h, minf(delta * 10.0, 1.0))
		collision.position.y = cap.height * 0.5
	head.position.y = lerpf(head.position.y, _head_crouch_y if crouched else _head_stand_y, minf(delta * 10.0, 1.0))
	# Move.
	var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish: Vector3 = (global_transform.basis * Vector3(input_vec.x, 0.0, input_vec.y))
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()
	var want_sprint: bool = Input.is_action_pressed("sprint") and not crouched and input_vec.y < -0.1
	sprinting = want_sprint and stamina > 0.05 and wish.length() > 0.1
	var speed: float = CROUCH_SPEED if crouched else (SPRINT_SPEED if sprinting else WALK_SPEED)
	speed *= _move_factor()
	if sprinting:
		stamina = maxf(0.0, stamina - delta / 14.0 * _stamina_drain_mul())
	elif wish.length() < 0.1 or not want_sprint:
		stamina = minf(1.0, stamina + delta / 2.5 * _stamina_regen_mul())
	var target_v := wish * speed
	velocity.x = lerpf(velocity.x, target_v.x, minf(delta * 12.0, 1.0))
	velocity.z = lerpf(velocity.z, target_v.z, minf(delta * 12.0, 1.0))
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	# Headbob + footsteps.
	var planar: float = Vector2(velocity.x, velocity.z).length()
	if planar > 0.4 and is_on_floor():
		_bob_phase += delta * (7.0 if sprinting else 5.2)
		head.position.x = sin(_bob_phase * 0.5) * (0.035 if sprinting else 0.02)
		camera.position.y = sin(_bob_phase) * (0.045 if sprinting else 0.028)
		_step_accum += planar * delta
		var stride: float = STEP_DIST_SPRINT if sprinting else STEP_DIST_WALK
		if _step_accum >= stride:
			_step_accum = 0.0
			_footstep()
	else:
		head.position.x = lerpf(head.position.x, 0.0, minf(delta * 6.0, 1.0))
		camera.position.y = lerpf(camera.position.y, 0.0, minf(delta * 6.0, 1.0))
	# FOV: setting base + sprint kick, eased on all three cameras.
	var base_fov: float = float(game.get("fov")) if game != null and game.get("fov") != null else 75.0
	var want_fov: float = base_fov + (8.0 if sprinting else 0.0)
	var fov_k: float = minf(delta * 6.0, 1.0)
	camera.fov = lerpf(camera.fov, want_fov, fov_k)
	_cam3.fov = lerpf(_cam3.fov, want_fov, fov_k)
	_camf.fov = lerpf(_camf.fov, want_fov, fov_k)
	# Flashlight: F toggles a plain light. Battery drains slowly while on,
	# recharges while off. It has no effect on the entity.
	if Input.is_action_just_pressed("flash") and flash_battery > 0.0:
		flashlight_on = not flashlight_on
	if flashlight_on:
		flash_battery = maxf(0.0, flash_battery - FLASH_BATTERY_DRAIN * delta)
		if flash_battery <= 0.0:
			flashlight_on = false
	else:
		flash_battery = minf(1.0, flash_battery + FLASH_BATTERY_RECHARGE * delta)
	flash_light.visible = flashlight_on
	# Interact. With the pack open, E drinks and Q eats instead.
	if Input.is_action_just_pressed("interact"):
		if game != null and game.has_method("is_inventory_open") and bool(game.call("is_inventory_open")):
			game.call("drink_inv")
		else:
			_try_interact()
	if Input.is_action_just_pressed("eat_bread"):
		if game != null and game.has_method("is_inventory_open") and bool(game.call("is_inventory_open")):
			game.call("eat_inv")
	# Co-op: broadcast my avatar state at ~15 Hz.
	if _net != null and _net.is_mp():
		_sync_t += 1
		if _sync_t % 4 == 0:
			_net.send_avatar_state(global_position, rotation.y, crouched, sprinting, planar)
	_tick_body_anim(delta, planar)


func cycle_view() -> void:
	view_mode = (view_mode + 1) % 3
	camera.current = view_mode == View.FIRST
	_cam3.current = view_mode == View.CHASE
	_camf.current = view_mode == View.FRONT
	_body.visible = view_mode != View.FIRST


func _footstep() -> void:
	var radius: float = current_noise_radius()
	if audio != null:
		audio.play_step(1.0 if sprinting else (0.4 if crouched else 0.7), steps_player)
	# The entity listens on this group call. In co-op the client's entity is a
	# puppet, so its footsteps also go to the host where the real AI listens.
	if _net != null and _net.is_mp() and not _net.am_server():
		_net.send_noise(global_position, radius)
	get_tree().call_group("entity", "hear_noise", global_position, radius)


func current_noise_radius() -> float:
	if sprinting:
		return NOISE_SPRINT
	if crouched:
		return NOISE_CROUCH
	return NOISE_WALK


func flash_ready_frac() -> float:
	return flash_battery


func interaction_hit() -> Dictionary:
	var cam: Camera3D = camera
	if view_mode == View.CHASE:
		cam = _cam3
	elif view_mode == View.FRONT:
		cam = _camf
	var origin: Vector3 = head.global_position
	var from: Vector3 = cam.global_position
	var reach: float = 3.2
	var to: Vector3 = from - cam.global_basis.z * (from.distance_to(origin) + reach)
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [get_rid()])
	query.collide_with_areas = false
	var space := get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty() or origin.distance_to(hit.position) > reach:
		return {}
	# Camera visibility cannot grant interaction through a wall beside the actor.
	var obstruction := PhysicsRayQueryParameters3D.create(origin, hit.position, 0xFFFFFFFF, [get_rid(), hit.collider.get_rid()])
	obstruction.collide_with_areas = false
	if not space.intersect_ray(obstruction).is_empty():
		return {}
	return hit

func _try_interact() -> void:
	var hit: Dictionary = interaction_hit()
	if not hit.is_empty():
		var col: Object = hit["collider"]
		if col != null and col.has_method("interact"):
			col.call("interact")


func _move_factor() -> float:
	if game != null and game.has_method("get_move_factor"):
		return float(game.call("get_move_factor"))
	return 1.0


func _stamina_drain_mul() -> float:
	if game != null and game.has_method("get_stamina_drain_mul"):
		return float(game.call("get_stamina_drain_mul"))
	return 1.0


func _stamina_regen_mul() -> float:
	if game != null and game.has_method("get_stamina_regen_mul"):
		return float(game.call("get_stamina_regen_mul"))
	return 1.0


func _build_body() -> void:
	# Visible explorer body for 3rd person: hoodie, jeans, boots.
	var hoodie := StandardMaterial3D.new()
	hoodie.albedo_color = Color(0.13, 0.14, 0.20)
	hoodie.roughness = 0.9
	var jeans := StandardMaterial3D.new()
	jeans.albedo_color = Color(0.12, 0.16, 0.26)
	jeans.roughness = 0.95
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.72, 0.55, 0.42)
	skin.roughness = 0.7
	var boot := StandardMaterial3D.new()
	boot.albedo_color = Color(0.09, 0.08, 0.07)
	boot.roughness = 0.85
	var pack := StandardMaterial3D.new()
	pack.albedo_color = Color(0.25, 0.27, 0.18)
	pack.roughness = 0.9
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_torso = _pivot(_body, Vector3(0, 0.95, 0))
	_part(_torso, Vector3(0.40, 0.58, 0.24), Vector3(0, 0.26, 0), hoodie)  # torso
	_part(_torso, Vector3(0.22, 0.24, 0.22), Vector3(0, 0.69, 0), skin)  # head
	_part(_torso, Vector3(0.24, 0.26, 0.12), Vector3(0, 0.68, -0.15), hoodie)  # hood
	_part(_torso, Vector3(0.30, 0.40, 0.15), Vector3(0, 0.26, -0.19), pack)  # backpack
	_part(_torso, Vector3(0.38, 0.07, 0.23), Vector3(0, -0.01, 0), boot)  # belt
	_thigh_l = _pivot(_body, Vector3(-0.12, 0.95, 0))
	_thigh_r = _pivot(_body, Vector3(0.12, 0.95, 0))
	for side: Array in [[_thigh_l, true], [_thigh_r, false]]:
		_part(side[0], Vector3(0.13, 0.50, 0.13), Vector3(0, -0.25, 0), jeans)
	_arm_l = _pivot(_torso, Vector3(-0.27, 0.47, 0))
	_arm_r = _pivot(_torso, Vector3(0.27, 0.47, 0))
	_part(_arm_l, Vector3(0.10, 0.62, 0.10), Vector3(0, -0.31, 0), hoodie)
	_part(_arm_r, Vector3(0.10, 0.62, 0.10), Vector3(0, -0.31, 0), hoodie)
	_part(_arm_l, Vector3(0.09, 0.12, 0.09), Vector3(0, -0.66, 0), skin)  # hands
	_part(_arm_r, Vector3(0.09, 0.12, 0.09), Vector3(0, -0.66, 0), skin)
	_knee_l = _pivot(_thigh_l, Vector3(0, -0.50, 0))
	_knee_r = _pivot(_thigh_r, Vector3(0, -0.50, 0))
	_part(_knee_l, Vector3(0.11, 0.48, 0.11), Vector3(0, -0.24, 0), jeans)
	_part(_knee_r, Vector3(0.11, 0.48, 0.11), Vector3(0, -0.24, 0), jeans)
	_part(_knee_l, Vector3(0.12, 0.10, 0.26), Vector3(0, -0.47, 0.04), boot)  # boots
	_part(_knee_r, Vector3(0.12, 0.10, 0.26), Vector3(0, -0.47, 0.04), boot)


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _tick_body_anim(delta: float, planar_speed: float) -> void:
	if not is_instance_valid(_body):
		return
	var k: float = clampf(planar_speed / SPRINT_SPEED, 0.0, 1.0)
	if crouched:
		_body.position.y = lerpf(_body.position.y, -0.32, minf(delta * 8.0, 1.0))
		_thigh_l.rotation.x = lerpf(_thigh_l.rotation.x, -0.7, minf(delta * 8.0, 1.0))
		_thigh_r.rotation.x = lerpf(_thigh_r.rotation.x, -0.7, minf(delta * 8.0, 1.0))
		_knee_l.rotation.x = lerpf(_knee_l.rotation.x, 1.1, minf(delta * 8.0, 1.0))
		_knee_r.rotation.x = lerpf(_knee_r.rotation.x, 1.1, minf(delta * 8.0, 1.0))
		_torso.rotation.x = lerpf(_torso.rotation.x, 0.3, minf(delta * 8.0, 1.0))
		_body.rotation.y = lerpf(_body.rotation.y, 0.0, minf(delta * 8.0, 1.0))
		return
	_body.position.y = lerpf(_body.position.y, 0.0, minf(delta * 8.0, 1.0))
	var swing: float = sin(_bob_phase) * 0.65 * k
	_thigh_l.rotation.x = swing
	_thigh_r.rotation.x = -swing
	# Knees bend on the back-swing only.
	_knee_l.rotation.x = maxf(0.0, -swing) * 1.3
	_knee_r.rotation.x = maxf(0.0, swing) * 1.3
	_arm_l.rotation.x = -swing * 0.7
	_arm_r.rotation.x = swing * 0.7
	_torso.rotation.x = 0.06 * k + (0.08 if sprinting else 0.0)
	_body.rotation.y = sin(_bob_phase * 0.5) * 0.05 * k
