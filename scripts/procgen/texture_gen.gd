class_name TextureGen
extends RefCounted
## Procedural textures for walls and floors. Generated once per theme,
## cached by color key.

static var _cache := {}


## Stone tile floor texture: grid of tiles with per-tile brightness variation
## and dark grout lines.
static func floor_tex(base: Color) -> ImageTexture:
	var key := "floor_%s" % base.to_html()
	if _cache.has(key):
		return _cache[key]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var tiles := 8
	var tile_px := size / tiles
	# Per-tile brightness.
	var brightness := []
	for t in tiles * tiles:
		brightness.append(rng.randf_range(0.85, 1.15))
	for y in size:
		for x in size:
			var tx := x / tile_px
			var ty := y / tile_px
			var b: float = brightness[ty * tiles + tx]
			# Grout lines.
			var gx := x % tile_px
			var gy := y % tile_px
			var grout := gx < 2 or gy < 2
			var c := base * b
			if grout:
				c = base * 0.55
			# Subtle noise.
			var n := rng.randf_range(0.95, 1.05)
			c = Color(clampf(c.r * n, 0.0, 1.0), clampf(c.g * n, 0.0, 1.0), clampf(c.b * n, 0.0, 1.0))
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Brick wall texture: running bond pattern with mortar lines.
static func wall_tex(base: Color) -> ImageTexture:
	var key := "wall_%s" % base.to_html()
	if _cache.has(key):
		return _cache[key]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 67890
	var rows := 8
	var row_h := size / rows
	var brick_w := size / 4
	var brightness := []
	for r in rows:
		for b in 5:
			brightness.append(rng.randf_range(0.82, 1.12))
	for y in size:
		for x in size:
			var row := y / row_h
			# Offset every other row (running bond).
			var ox := (brick_w / 2) if (row % 2 == 1) else 0
			var bx := int((x + ox) / brick_w) % 5
			var b: float = brightness[row * 5 + bx]
			# Mortar lines.
			var my := y % row_h
			var mx := (x + ox) % brick_w
			var mortar := my < 2 or mx < 2
			var c := base * b
			if mortar:
				c = base * 0.5
			var n := rng.randf_range(0.94, 1.06)
			c = Color(clampf(c.r * n, 0.0, 1.0), clampf(c.g * n, 0.0, 1.0), clampf(c.b * n, 0.0, 1.0))
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Material with a texture, UV scaled for world-space tiling.
static func textured_mat(tex: Texture2D, uv_scale: float = 4.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.95
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	return mat
