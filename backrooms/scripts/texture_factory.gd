class_name TextureFactory
extends RefCounted
## Procedural fallback textures. Everything is generated with Image polling
## so the game looks right with zero downloaded assets. 256px = 1 world repeat.

const SIZE: int = 256


static func make_wallpaper(rng: RandomNumberGenerator) -> ImageTexture:
	# Wallpaper A: yellow backrooms classic.
	return _wallpaper_with(rng, Color(0.72, 0.63, 0.36), Color(0.45, 0.36, 0.20))


static func make_wallpaper_b(rng: RandomNumberGenerator) -> ImageTexture:
	# Wallpaper B: olive twin for the west rooms.
	return _wallpaper_with(rng, Color(0.60, 0.56, 0.34), Color(0.38, 0.34, 0.20))


static func _wallpaper_with(rng: RandomNumberGenerator, base: Color, rail: Color) -> ImageTexture:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y: int in SIZE:
		for x: int in SIZE:
			# Pinstripe every 16px + diamond damask on a 64px tile.
			var stripe: float = 0.94 + 0.06 * (0.5 + 0.5 * sin(float(x) / 16.0 * PI))
			var tx: float = float(x % 64) - 32.0
			var ty: float = float(y % 64) - 32.0
			var diamond: float = 1.0 - clampf((absf(tx) + absf(ty)) / 32.0, 0.0, 1.0)
			var motif: float = 0.20 * maxf(0.0, diamond - 0.55)
			# Hung drops: seam shadow every 128px + per-drop tone shift.
			var drop: float = floor(float(x) / 128.0)
			var seam: float = -0.10 if x % 128 < 2 else 0.0
			var drop_tone: float = 0.02 * sin(drop * 2.3 + 0.7)
			var n: float = rng.randf_range(-0.03, 0.03)
			var v: float = clampf(stripe + motif + seam + drop_tone + n, 0.0, 1.2)
			var c := Color(base.r * v, base.g * v, base.b * v, 1.0)
			# Dado band: darker bottom 48px with a chair rail line.
			if y >= SIZE - 48:
				c = c.darkened(0.3)
			if y >= SIZE - 52 and y < SIZE - 48:
				c = rail
			img.set_pixel(x, y, c)
	_finish(img)
	return ImageTexture.create_from_image(img)


static func make_carpet(rng: RandomNumberGenerator) -> ImageTexture:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var blotches: Array = []
	for i: int in 5:
		blotches.append([rng.randf_range(0.0, 256.0), rng.randf_range(0.0, 256.0), rng.randf_range(24.0, 60.0)])
	for y: int in SIZE:
		for x: int in SIZE:
			var n: float = rng.randf_range(-0.05, 0.05)
			# Faint diamond weave + 128px checker.
			var weave: float = 0.03 * sin(float(x + y) / 9.0 * PI) * sin(float(x - y) / 9.0 * PI)
			var checker: float = -0.04 if (x / 128 + y / 128) % 2 == 1 else 0.0
			var v: float = clampf(1.0 + n * 4.0 + weave + checker, 0.0, 1.4)
			var c := Color(0.42 * v, 0.35 * v, 0.18 * v, 1.0)
			# Blackened wear blotches.
			for b: Array in blotches:
				var dx: float = float(x) - float(b[0])
				var dy: float = float(y) - float(b[1])
				var d: float = sqrt(dx * dx + dy * dy)
				var r: float = float(b[2])
				if d < r:
					c = c.darkened(0.45 * (1.0 - d / r))
			img.set_pixel(x, y, c)
	_finish(img)
	return ImageTexture.create_from_image(img)


static func make_ceiling(rng: RandomNumberGenerator) -> ImageTexture:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var stained := {}
	for i: int in 8:
		stained[Vector2i(rng.randi_range(0, 7), rng.randi_range(0, 7))] = true
	for y: int in SIZE:
		for x: int in SIZE:
			var n: float = rng.randf_range(-0.025, 0.025)
			var v: float = clampf(0.82 + n, 0.0, 1.0)
			var c := Color(0.84 * v, 0.82 * v, 0.76 * v, 1.0)
			# Tile grid every 32px + speckle pinholes.
			if x % 32 < 2 or y % 32 < 2:
				c = c.darkened(0.3)
			elif x % 17 < 2 and y % 13 < 2 and rng.randf() < 0.6:
				c = c.darkened(0.45)
			# Brown water-stain ring in a few tiles.
			var tile := Vector2i(x / 32, y / 32)
			if stained.has(tile):
				var dx: float = float(x % 32) - 16.0
				var dy: float = float(y % 32) - 16.0
				var d: float = sqrt(dx * dx + dy * dy)
				if d > 7.0 and d < 11.0:
					c = Color(0.45, 0.32, 0.18)
				elif d <= 7.0:
					c = c.darkened(0.12)
			img.set_pixel(x, y, c)
	_finish(img)
	return ImageTexture.create_from_image(img)


static func make_wall_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.92
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func make_floor_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.98
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func make_ceiling_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.0, 1.0, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func make_grime_decal(rng: RandomNumberGenerator) -> ImageTexture:
	# Vertical streaks, transparent edges. Applied on wall Decals.
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var seeds: Array[float] = []
	var strengths: Array[float] = []
	for i: int in 9:
		seeds.append(rng.randf_range(0.0, float(SIZE)))
		strengths.append(rng.randf_range(0.4, 1.0))
	for y: int in SIZE:
		var wobble: float = sin(float(y) / 41.0) * 6.0
		for x: int in SIZE:
			var edge: float = sin(float(x) / float(SIZE) * PI) * sin(float(y) / float(SIZE) * PI)
			var streak: float = 0.0
			for i: int in seeds.size():
				var d: float = absf(float(x) - seeds[i] - wobble) / 14.0
				streak += exp(-d * d) * strengths[i]
			var a: float = clampf(streak * 0.28 * edge, 0.0, 0.55)
			img.set_pixel(x, y, Color(0.16, 0.13, 0.08, a))
	_finish(img)
	return ImageTexture.create_from_image(img)


static func make_wet_patch() -> ImageTexture:
	# Dark glossy blob with soft falloff for floor Decals.
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var c: float = float(SIZE) * 0.5
	for y: int in SIZE:
		for x: int in SIZE:
			var dx: float = (float(x) - c) / c
			var dy: float = (float(y) - c) / c
			var r: float = sqrt(dx * dx + dy * dy)
			var a: float = clampf(1.0 - r, 0.0, 1.0)
			a = a * a * 0.62
			img.set_pixel(x, y, Color(0.05, 0.045, 0.035, a))
	_finish(img)
	return ImageTexture.create_from_image(img)


static func make_vent_texture() -> ImageTexture:
	# Louvered grille: frame, angled slats with highlight lips, corner screws.
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y: int in SIZE:
		for x: int in SIZE:
			var slat: float = 0.5 + 0.5 * sin(float(y) / 10.0 * PI)
			var v: float = 0.05 + 0.10 * slat
			var c := Color(v, v, v * 1.05, 1.0)
			var ph: float = fmod(float(y) / 10.0, 2.0)
			if ph > 1.82:
				c = Color(0.32, 0.33, 0.34)
			if x < 10 or x >= SIZE - 10 or y < 10 or y >= SIZE - 10:
				c = Color(0.16, 0.16, 0.17)
			for corner: Vector2i in [Vector2i(20, 20), Vector2i(SIZE - 20, 20), Vector2i(20, SIZE - 20), Vector2i(SIZE - 20, SIZE - 20)]:
				var sdx: int = x - corner.x
				var sdy: int = y - corner.y
				if sdx * sdx + sdy * sdy < 36:
					c = Color(0.45, 0.46, 0.47)
			img.set_pixel(x, y, c)
	_finish(img)
	return ImageTexture.create_from_image(img)


static func make_screen(rng: RandomNumberGenerator) -> ImageTexture:
	# Dead-monitor snow with scanlines and a dim phosphor glow spot.
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y: int in SIZE:
		for x: int in SIZE:
			var snow: float = rng.randf()
			var scan: float = 0.75 + 0.25 * sin(float(y) / 3.0 * PI)
			var dx: float = (float(x) - SIZE / 2.0) / SIZE
			var dy: float = (float(y) - SIZE / 2.0) / SIZE
			var glow: float = clampf(1.0 - (dx * dx + dy * dy) * 3.0, 0.0, 1.0)
			var v: float = (0.12 + snow * 0.5) * scan + glow * 0.25
			img.set_pixel(x, y, Color(v * 0.75, v, v * 0.9, 1.0))
	_finish(img)
	return ImageTexture.create_from_image(img)


static func make_concrete(rng: RandomNumberGenerator) -> ImageTexture:
	# Service-district walls: gray poured concrete, form lines, damp streaks.
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y: int in SIZE:
		for x: int in SIZE:
			var n: float = rng.randf_range(-0.045, 0.045)
			var v: float = clampf(0.45 + n, 0.0, 1.0)
			if y % 64 < 2:
				v *= 0.82
			# Form-tie holes on a 128px grid.
			var hx: int = x % 128
			var hy: int = y % 128
			var hd: int = (hx - 64) * (hx - 64) + (hy - 64) * (hy - 64)
			if hd < 36:
				v *= 0.55
			var streak: float = 0.06 * sin(float(x) / 37.0 + sin(float(y) / 53.0))
			v = clampf(v + streak, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v * 1.01, v * 0.98, 1.0))
	_finish(img)
	return ImageTexture.create_from_image(img)


static func make_serverwall(rng: RandomNumberGenerator) -> ImageTexture:
	# Server-district walls: dark blue-gray equipment panels + rivets.
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y: int in SIZE:
		for x: int in SIZE:
			var n: float = rng.randf_range(-0.02, 0.02)
			var v: float = clampf(0.15 + n, 0.0, 1.0)
			if x % 64 < 2 or y % 64 < 2:
				v *= 0.7
			if (x % 64 < 4 and y % 64 < 4) and (x % 64 > 1 and y % 64 > 1):
				v = 0.35
			# Vent slits row.
			if y >= 200 and y < 216 and x % 16 < 8:
				v *= 0.5
			img.set_pixel(x, y, Color(v * 0.9, v, v * 1.15, 1.0))
	_finish(img)
	return ImageTexture.create_from_image(img)


static func make_floortile(rng: RandomNumberGenerator) -> ImageTexture:
	# Anti-static server tile: near-black + faint grid.
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y: int in SIZE:
		for x: int in SIZE:
			var n: float = rng.randf_range(-0.012, 0.012)
			var v: float = clampf(0.05 + n, 0.0, 1.0)
			if x % 64 < 2 or y % 64 < 2:
				v *= 0.6
			img.set_pixel(x, y, Color(v * 0.9, v, v * 1.1, 1.0))
	_finish(img)
	return ImageTexture.create_from_image(img)


static func make_hazard(rng: RandomNumberGenerator) -> ImageTexture:
	# 45-degree yellow/black warning bands for gateway frames.
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y: int in SIZE:
		for x: int in SIZE:
			var band: int = int((float(x + y) / 16.0)) % 2
			var n: float = rng.randf_range(-0.03, 0.03)
			var c := Color(0.85 + n, 0.65 + n, 0.10, 1.0) if band == 0 else Color(0.08 + n, 0.08 + n, 0.08 + n, 1.0)
			img.set_pixel(x, y, c)
	_finish(img)
	return ImageTexture.create_from_image(img)


static func make_metaldor(rng: RandomNumberGenerator) -> ImageTexture:
	# Brushed metal door + kick plate + sign plate. Hero prop skin.
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y: int in SIZE:
		for x: int in SIZE:
			var brush: float = 0.03 * sin(float(y) / 3.0) + 0.02 * sin(float(y) / 7.3 + float(x) / 41.0)
			var v: float = clampf(0.42 + brush + rng.randf_range(-0.02, 0.02), 0.0, 1.0)
			var c := Color(v, v * 1.01, v * 1.04, 1.0)
			if y >= 216:
				c = Color(v * 0.7, v * 0.7, v * 0.7, 1.0)
			if x >= 108 and x < 148 and y >= 40 and y < 64:
				c = Color(0.75, 0.75, 0.72, 1.0)
			img.set_pixel(x, y, c)
	_finish(img)
	return ImageTexture.create_from_image(img)


static func _finish(img: Image) -> void:
	if img.has_mipmaps() == false:
		img.generate_mipmaps()


static func load_materials(rng: RandomNumberGenerator, level: int = 0) -> Dictionary:
	"""CC0 files from assets/ when present, procedural fallback otherwise.
	Levels reskin the base trio: 1 = bare concrete, 2 = dark machine tile."""
	var wall_tex: Texture2D = _load_tex("res://assets/tex_wall")
	if wall_tex == null:
		wall_tex = make_wallpaper(rng)
	else:
		print("TextureFactory: using assets/tex_wall.jpg")
	var floor_tex: Texture2D = _load_tex("res://assets/tex_floor")
	if floor_tex == null:
		floor_tex = make_carpet(rng)
	else:
		print("TextureFactory: using assets/tex_floor.jpg")
	var ceil_tex: Texture2D = _load_tex("res://assets/tex_ceiling")
	if ceil_tex == null:
		ceil_tex = make_ceiling(rng)
	else:
		print("TextureFactory: using assets/tex_ceiling.jpg")
	var wall_mat := make_wall_material(wall_tex)
	var floor_mat := make_floor_material(floor_tex)
	var ceil_mat := make_ceiling_material(ceil_tex)
	var wall2_tex := make_concrete(rng)
	var wall3_tex := make_serverwall(rng)
	var wall2_mat := make_wall_material(wall2_tex)
	var wall3_mat := make_wall_material(wall3_tex)
	var wallb_tex := make_wallpaper_b(rng)
	var wallb_mat := make_wall_material(wallb_tex)
	var svc_mat := make_floor_material(wall2_tex)
	svc_mat.roughness = 0.35
	var srv_tex := make_floortile(rng)
	var srv_mat := make_floor_material(srv_tex)
	srv_mat.roughness = 0.6
	if level == 1:
		wall_tex = wall2_tex
		floor_tex = wall2_tex
		ceil_tex = wall2_tex
		wall_mat = make_wall_material(wall2_tex)
		floor_mat = make_floor_material(wall2_tex)
		floor_mat.roughness = 0.5
		ceil_mat = make_ceiling_material(wall2_tex)
	elif level == 2:
		wall_tex = wall3_tex
		floor_tex = srv_tex
		ceil_tex = wall2_tex
		wall_mat = make_wall_material(wall3_tex)
		wall_mat.albedo_color = Color(0.55, 0.58, 0.66)
		floor_mat = make_floor_material(srv_tex)
		floor_mat.albedo_color = Color(0.5, 0.52, 0.58)
		floor_mat.roughness = 0.6
		ceil_mat = make_ceiling_material(wall2_tex)
		ceil_mat.albedo_color = Color(0.35, 0.35, 0.38)
	var hazard_mat := make_wall_material(make_hazard(rng))
	var metaldor_mat := make_wall_material(make_metaldor(rng))
	var pbr_pairs: Array = [[wallb_mat, "wall_b"], [wall2_mat, "concrete"], [svc_mat, "concrete"], [wall3_mat, "server"], [srv_mat, "floor_server"]]
	if level == 0:
		pbr_pairs += [[wall_mat, "wall"], [floor_mat, "carpet"], [ceil_mat, "ceiling"]]
	var baked_mats := {}
	for pair: Array in pbr_pairs:
		if ResourceLoader.exists("res://assets/materials/%s_albedo.png" % pair[1]):
			baked_mats[pair[0]] = true
	for entry: Array in [[wall_mat, wall_tex, 0.5], [floor_mat, floor_tex, 0.7], [ceil_mat, ceil_tex, 0.4], [wall2_mat, wall2_tex, 0.6], [wall3_mat, wall3_tex, 0.5], [wallb_mat, wallb_tex, 0.5], [svc_mat, wall2_tex, 0.5], [srv_mat, srv_tex, 0.4]]:
		if baked_mats.has(entry[0]):
			continue  # baked PBR below replaces albedo+normal wholesale; Sobel is pure waste
		var nrm: Texture2D = normal_from_luminance(entry[1])
		if nrm != null:
			(entry[0] as StandardMaterial3D).normal_enabled = true
			(entry[0] as StandardMaterial3D).normal_texture = nrm
			(entry[0] as StandardMaterial3D).normal_scale = float(entry[2])
	for pair: Array in pbr_pairs:
		_apply_pbr(pair[0], pair[1])
	return {
		"wall": wall_mat,
		"wallB": wallb_mat,
		"wall2": wall2_mat,
		"wall3": wall3_mat,
		"floor": floor_mat,
		"floor_service": svc_mat,
		"floor_server": srv_mat,
		"hazard": hazard_mat,
		"metaldor": metaldor_mat,
		"ceiling": ceil_mat,
		"grime": make_grime_decal(rng),
		"wet": make_wet_patch(),
		"vent": make_vent_texture(),
		"screen": make_screen(rng),
	}


static func _apply_pbr(material: StandardMaterial3D, surface: String) -> void:
	var base: String = "res://assets/materials/%s_" % surface
	if not ResourceLoader.exists(base + "albedo.png"):
		return
	material.albedo_texture = load(base + "albedo.png") as Texture2D
	material.normal_texture = load(base + "normal.png") as Texture2D
	material.normal_enabled = true
	material.normal_scale = 0.8
	material.roughness_texture = load(base + "roughness.png") as Texture2D
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


static func normal_from_luminance(tex: Texture2D) -> ImageTexture:
	"""Cheap Sobel normal map from any albedo (procedural or CC0)."""
	var src: Image = tex.get_image()
	if src == null or src.is_empty():
		return null
	# Imported textures arrive compressed; decompress for pixel access.
	if src.is_compressed():
		var dc := src.duplicate() as Image
		if dc.decompress() != OK:
			return null
		src = dc
	var w: int = src.get_width()
	var h: int = src.get_height()
	if w <= 0 or h <= 0:
		return null
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	# Cap work: normals bake at 128px, GPU upscales. 4x faster, same look.
	var step: int = maxi(1, mini(w, h) / 128)
	for y: int in range(0, h, step):
		for x: int in range(0, w, step):
			var xm: int = (x - step + w) % w
			var xp: int = (x + step) % w
			var ym: int = (y - step + h) % h
			var yp: int = (y + step) % h
			var dx: float = src.get_pixel(xp, y).get_luminance() - src.get_pixel(xm, y).get_luminance()
			var dy: float = src.get_pixel(x, yp).get_luminance() - src.get_pixel(x, ym).get_luminance()
			var n := Vector3(-dx * 4.0, -dy * 4.0, 1.0).normalized()
			var c := Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0)
			for yy: int in range(y, mini(y + step, h)):
				for xx: int in range(x, mini(x + step, w)):
					out.set_pixel(xx, yy, c)
	_finish(out)
	return ImageTexture.create_from_image(out)


static func _load_tex(path_no_ext: String) -> Texture2D:
	for ext: String in [".jpg", ".png"]:
		var path: String = path_no_ext + ext
		if FileAccess.file_exists(path):
			var t: Texture2D = load(path) as Texture2D
			if t != null:
				return t
			push_warning("TextureFactory: present but unloadable: %s" % path)
	return null
