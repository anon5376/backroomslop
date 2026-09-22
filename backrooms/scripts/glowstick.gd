class_name Glowstick
extends Node3D
## Dropped path marker: emissive tube + small light. Permanent until the
## run ends; main caps the alive count and frees the oldest first.

const COLORS: Array[Color] = [
	Color(0.35, 1.0, 0.45),  # Mara green
	Color(1.0, 0.72, 0.30),  # amber
	Color(0.40, 0.70, 1.0),  # coolant blue
]


static func build(color_i: int) -> Glowstick:
	var g := Glowstick.new()
	var tint: Color = COLORS[posmod(color_i, COLORS.size())]
	var tube := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.025
	cm.height = 0.28
	cm.radial_segments = 10
	tube.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = tint * 1.6
	tube.material_override = mat
	tube.rotation.z = PI / 2.0
	tube.rotation.y = randf() * TAU
	g.add_child(tube)
	var lamp := OmniLight3D.new()
	lamp.light_color = tint
	lamp.light_energy = 0.7
	lamp.omni_range = 2.5
	lamp.omni_attenuation = 1.0
	lamp.shadow_enabled = false
	lamp.position = Vector3(0, 0.15, 0)
	g.add_child(lamp)
	return g
