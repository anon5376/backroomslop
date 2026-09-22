class_name Pickup
extends StaticBody3D
## E-to-grab survival item. kind is "water" (Restores thirst) or "bread"
## (restores hunger). Bobs and spins; frees itself after granting the effect,
## reparenting its one-shot sound so it survives.

var kind: String = "water"
var net_id: int = -1  # deterministic build-order id, same on both peers
var _sfx: AudioStreamPlayer3D = null
var _visual: Node3D = null
var _t: float = 0.0


func _init() -> void:
	# Rays include layer 2; actor movement only collides with the solid-world layer.
	collision_layer = 2
	collision_mask = 0


func setup(p_kind: String, visual: Node3D, sfx: AudioStreamPlayer3D) -> void:
	kind = p_kind
	_visual = visual
	_sfx = sfx


func _process(delta: float) -> void:
	_t += delta
	if is_instance_valid(_visual):
		_visual.position.y = 0.35 + sin(_t * 2.2) * 0.06
		_visual.rotation.y += delta * 0.8


func interact() -> void:
	var g: Node = get_tree().get_first_node_in_group("game")
	var net: Node = g.get("net") if g != null else null
	if net != null and net.is_mp():
		# Co-op: the host validates and despawns via signal. This node stays
		# visible until the despawn arrives (immediately for the host).
		net.request_grab(net_id)
		return
	if g != null:
		if g.has_method("add_pickup"):
			g.add_pickup(kind)
	if is_instance_valid(_sfx):
		var gp: Vector3 = _sfx.global_position
		remove_child(_sfx)
		get_tree().current_scene.add_child(_sfx)
		_sfx.global_position = gp
		_sfx.play()
		_sfx.finished.connect(_sfx.queue_free)
	queue_free()
