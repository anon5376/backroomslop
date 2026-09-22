extends SceneTree

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var mats := TextureFactory.load_materials(rng)
	var failures: int = 0
	for key: String in ["wall", "wallB", "wall2", "wall3", "floor", "floor_service", "floor_server", "ceiling"]:
		var material: StandardMaterial3D = mats[key]
		var valid: bool = material.normal_enabled and material.roughness_texture != null
		for tex: Texture2D in [material.albedo_texture, material.normal_texture, material.roughness_texture]:
			valid = valid and tex != null and tex.get_width() == 1024 and tex.get_height() == 1024 and tex.resource_path.begins_with("res://assets/materials/")
		print("%s: %s maps loaded" % ["PASS" if valid else "FAIL", key])
		if not valid:
			failures += 1
	print("MATERIAL TEST: %s" % ("ALL PASS" if failures == 0 else "FAILED"))
	quit(failures)
