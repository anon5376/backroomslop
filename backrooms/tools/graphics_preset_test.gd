extends SceneTree
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
func _run() -> void:
	var original_scale := root.scaling_3d_scale
	var original_mode := root.scaling_3d_mode
	GameManager.pending_seed = -1
	var scene := preload("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	for preset: String in ["High", "Low", "High", "Low"]:
		scene.apply_graphics_preset(preset)
		var expected: float = 0.67 if preset == "Low" else 1.0
		check(is_equal_approx(root.scaling_3d_scale, expected), "%s immediate active scale expected %.2f actual %.2f" % [preset, expected, root.scaling_3d_scale])
		await process_frame
		var expected_mode: int = Viewport.SCALING_3D_MODE_FSR2 if preset == "Low" and scene._supports_forward_effects() else Viewport.SCALING_3D_MODE_BILINEAR
		check(root.scaling_3d_mode == expected_mode, "%s renderer-supported scaling mode" % preset)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			check(image != null and not image.is_empty(), "%s rendered viewport readable" % preset)
		check(is_equal_approx(root.scaling_3d_scale, expected), "%s scale persists next frame" % preset)
		check(scene.env.glow_enabled == (preset == "High"), "%s glow state" % preset)
		if preset == "Low":
			check(not scene.env.sdfgi_enabled and not scene.env.volumetric_fog_enabled, "Low disables expensive environment effects")
		else:
			check(not scene.env.sdfgi_enabled and not scene.env.volumetric_fog_enabled and not scene.env.ssil_enabled, "High skips SDFGI/volumetrics/SSIL")
			check(scene.env.ssao_enabled == scene._supports_forward_effects(), "High keeps SSAO where supported")
	scene.free()
	root.scaling_3d_scale = original_scale
	root.scaling_3d_mode = original_mode
	print("GRAPHICS PRESET TEST: %s" % ["ALL PASS" if failures == 0 else "%d FAILURES" % failures])
	quit(0 if failures == 0 else 1)
