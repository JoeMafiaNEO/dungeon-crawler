class_name FishingVisual
extends Node3D
## Client-side eye candy for one fishing cast (issue #102 Phase 2).
## No gameplay state — the server owns the session and drives this node
## through the spot's on_cast/on_bite/on_catch/on_miss/on_cancel RPCs.
## Bobber arcs out with a splash, bobs while waiting, shows a big "!"
## on bite, then resolves (caught = quick lift, miss = sinks).

const ARC_TIME := 0.75


## Issue #104 Phase 3: the held rod prop (player viewmodel + the
## third-person HeldProp peers see). Simple procedural pole + reel in
## the same spirit as the session visual; the Art Director's real rod
## model replaces it when it ships.
static func build_rod_prop() -> Node3D:
	var root3d := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.3, 0.16)
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.02
	cm.height = 1.5
	pole.mesh = cm
	pole.material_override = mat
	pole.position = Vector3(0, 0.55, 0)
	pole.rotation.z = -0.5
	root3d.add_child(pole)
	var reel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.09, 0.05)
	reel.mesh = bm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.6, 0.6, 0.65)
	reel.material_override = rmat
	reel.position = Vector3(-0.18, 0.05, 0.03)
	root3d.add_child(reel)
	return root3d

var _bobber: Bobber = null
var _line: MeshInstance3D = null
var _splash: MeshInstance3D = null
var _splash_t: float = -1.0
var _puff: MeshInstance3D = null ## Issue #139: dirt-flop dust puff.
var _puff_t: float = -1.0
var _bang: Label3D = null
var _phase: int = 0 ## 0 = arcing, 1 = bobbing, 2 = resolving
var _arc_t: float = 0.0
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _flop := false ## Issue #126 Phase 2: dirt landing — sink on arrival.
var _dip_t := -1.0 ## Issue #126 Phase 3: bite dip timer (plunge + recover).
var _bob_phase: float = 0.0
var _resolve_t: float = -1.0
var _resolve_mode: String = ""


## Issue #126 Phase 2: `to` carries the real surface height (water
## level or dirt) — the caller validates; flop = dirt landing.
func begin_cast(from: Vector3, to: Vector3, flop: bool = false) -> void:
	_from = from
	_to = to
	_flop = flop
	_bobber = Bobber.new()
	add_child(_bobber)
	_bobber.global_position = _from
	# Thin line from the cast origin to the bobber.
	_line = MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.03, 0.03, 1.0)
	_line.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.85, 0.85, 0.8)
	_line.material_override = lmat
	add_child(_line)
	# Reusable splash ring. Issue #139: the band is 0.28 m wide
	# (was 0.08) — at a fisher's grazing angle a flat ring's whole
	# screen height IS its band width, and the hairline vanished
	# at 15 m in the Docks' night lighting.
	_splash = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.30
	tm.outer_radius = 0.58
	_splash.mesh = tm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.75, 0.9, 1.0, 0.85)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Issue #139: cues are fog-exempt — at 15 m the Docks' fog
	# (density 0.035) washes ~40% off a cue's brightness, which is
	# the whole failure this issue exists to fix.
	smat.disable_fog = true
	_splash.material_override = smat
	_splash.visible = false
	add_child(_splash)
	# Bite "!" — hidden until bite(). Issue #139: scaled for range
	# (font 160 at pixel_size 0.02 = a 3.2 m em, ~2.5x the shipped
	# 128/0.01) — at 15 m the old mark rendered ~12 px tall at
	# 1080p: colored pixels, not a mark. It also pulses while up
	# (phase 1) and hovers higher (1.35 m) to clear pond props.
	_bang = Label3D.new()
	_bang.text = "!"
	_bang.font_size = 160
	_bang.pixel_size = 0.02
	_bang.modulate = Color(1.0, 0.85, 0.2)
	_bang.outline_size = 20
	_bang.outline_modulate = Color(0.1, 0.05, 0.0)
	_bang.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bang.visible = false
	add_child(_bang)


func bobber_position() -> Vector3:
	if _bobber != null and is_instance_valid(_bobber):
		return _bobber.global_position
	return global_position


func bite() -> void:
	if _bang != null:
		_bang.visible = true
	_splash_at(_to)
	# Issue #126 Phase 3 (bite-cue readability): the bobber PLUNGES
	# and recovers — readable at 15 m where a splash ring alone is
	# easy to miss.
	_dip_t = 0.0


func caught() -> void:
	_phase = 2
	_resolve_t = 0.0
	_resolve_mode = "caught"
	if _bang != null:
		_bang.visible = false


## Issue #126 Phase 2: the fish escaped — the bobber STAYS in the
## water (the session idles until the fisher reels in).
func escape() -> void:
	if _bang != null:
		_bang.visible = false


## Issue #126 Phase 2: reel-in — the bobber slides back to the caster.
func reel_in() -> void:
	_phase = 2
	_resolve_t = 0.0
	_resolve_mode = "reel"
	if _bang != null:
		_bang.visible = false


func missed() -> void:
	_phase = 2
	_resolve_t = 0.0
	_resolve_mode = "missed"
	if _bang != null:
		_bang.visible = false


func _process(delta: float) -> void:
	if _bobber == null or not is_instance_valid(_bobber):
		return
	match _phase:
		0:
			_arc_t += delta
			var t := clampf(_arc_t / ARC_TIME, 0.0, 1.0)
			var pos := _from.lerp(_to, t)
			pos.y += sin(t * PI) * 2.2
			_bobber.global_position = pos
			if t >= 1.0:
				if _flop:
					# Issue #126 Phase 3: a dirt landing reads DIRT —
					# a dust-tan ring, not the water ring. Issue #139:
					# the tan is brightened and a billboard dust puff
					# carries the read at range (see _spawn_dust_puff).
					if _splash != null and _splash.material_override is StandardMaterial3D:
						(_splash.material_override as StandardMaterial3D).albedo_color = Color(0.88, 0.70, 0.44, 0.9)
					_splash_at(_to)
					_spawn_dust_puff()
					_phase = 2
					_resolve_t = 0.0
					_resolve_mode = "flop"
					AudioManager.sfx("dirt_flop", _to)
				else:
					_phase = 1
					_splash_at(_to)
					AudioManager.sfx("splashdown", _to)
		1:
			_bob_phase += delta * 2.2
			var dip := 0.0
			if _dip_t >= 0.0:
				_dip_t += delta
				var dk := clampf(_dip_t / 0.45, 0.0, 1.0)
				dip = -0.17 * sin(dk * PI)
				if dk >= 1.0:
					_dip_t = -1.0
			_bobber.global_position = Vector3(
				_to.x, _to.y + sin(_bob_phase) * 0.05 + dip, _to.z)
			if _bang != null and _bang.visible:
				_bang.global_position = _bobber.global_position + Vector3(0, 1.35, 0)
				# Issue #139: a gentle pulse while the bite window is
				# open — motion is what the eye catches at 15 m.
				_bang.scale = Vector3.ONE * (1.0 + 0.13 * sin(_bob_phase * 6.0))
		2:
			_resolve_t += delta
			if _resolve_mode == "caught":
				var bp := _bobber.global_position
				_bobber.global_position = bp + Vector3(0, 3.0 * delta, 0)
				if _resolve_t > 0.45:
					queue_free()
					return
			elif _resolve_mode == "reel":
				var rp := _bobber.global_position.lerp(_from, clampf(delta * 6.0, 0.0, 1.0))
				_bobber.global_position = rp
				if _resolve_t > 0.45:
					queue_free()
					return
			elif _resolve_mode == "flop":
				# Issue #139: the sink runs its original 0.4 s, but
				# the visual now lives until the widened ring and
				# the dust puff have played out (1.05 s) — at range
				# those cues ARE the flop's read.
				if _resolve_t < 0.4:
					var fp := _bobber.global_position
					_bobber.global_position = fp + Vector3(0, -0.8 * delta, 0)
				if _resolve_t > 1.05:
					queue_free()
					return
			else:
				var bp2 := _bobber.global_position
				_bobber.global_position = bp2 + Vector3(0, -1.2 * delta, 0)
				if _resolve_t > 0.8:
					queue_free()
					return
	_update_line()
	if _splash_t >= 0.0:
		_splash_t += delta
		# Issue #139: the ring lives 1.0 s (was 0.6) — at 15 m a
		# sub-second cue is a coin flip to even look at in time.
		var st := clampf(_splash_t / 1.0, 0.0, 1.0)
		_splash.scale = Vector3.ONE * lerpf(0.4, 2.2, st)
		var m := _splash.material_override as StandardMaterial3D
		if m != null:
			var c := m.albedo_color
			c.a = 0.9 * (1.0 - st)
			m.albedo_color = c
		if st >= 1.0:
			_splash_t = -1.0
			_splash.visible = false
	if _puff_t >= 0.0 and _puff != null and is_instance_valid(_puff):
		_puff_t += delta
		var pt := clampf(_puff_t / 1.0, 0.0, 1.0)
		_puff.global_position = _to + Vector3(0, 0.45 + 0.55 * pt, 0)
		_puff.scale = Vector3.ONE * lerpf(1.0, 1.5, pt)
		var pmat := _puff.material_override as StandardMaterial3D
		if pmat != null:
			var pc := pmat.albedo_color
			# Hold near-full strength past mid-life, then
			# dissipate — a linear fade spends its back half
			# below the visibility floor at range.
			pc.a = 0.9 * (1.0 - smoothstep(0.55, 1.0, pt))
			pmat.albedo_color = pc
		if pt >= 1.0:
			_puff_t = -1.0
			_puff.visible = false


## Issue #139: a dirt landing throws a billboarded dust puff. The
## flat ring alone collapses to a hairline at a fisher's grazing
## angle; the flop's at-range read rides on this vertical sprite —
## unshaded dust-tan, rising and swelling as it fades over ~1 s.
func _spawn_dust_puff() -> void:
	_puff = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.1, 2.1)
	_puff.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _dust_texture()
	mat.albedo_color = Color(0.88, 0.70, 0.44, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_fog = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_puff.material_override = mat
	add_child(_puff)
	_puff.global_position = _to + Vector3(0, 0.45, 0)
	_puff_t = 0.0


static var _dust_tex: Texture2D = null


## Soft radial disc, generated once (no asset file): full alpha at
## the center easing to zero at the rim.
static func _dust_texture() -> Texture2D:
	if _dust_tex != null:
		return _dust_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var center := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(center) / (n * 0.5)
			# Fat core: alpha holds high past halfway out — a dust
			# burst, not a halo — then eases to the rim.
			var a := clampf(1.18 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_dust_tex = ImageTexture.create_from_image(img)
	return _dust_tex


func _splash_at(pos: Vector3) -> void:
	if _splash == null:
		return
	_splash.global_position = Vector3(pos.x, pos.y - 0.06, pos.z)
	_splash.visible = true
	_splash_t = 0.0


func _update_line() -> void:
	if _line == null or _bobber == null or not is_instance_valid(_bobber):
		return
	var a := _from
	var b := _bobber.global_position
	var mid := (a + b) * 0.5
	_line.global_position = mid
	var d := b - a
	var dist := d.length()
	if dist > 0.001:
		_line.global_transform = Transform3D(
			Basis.looking_at(d.normalized(), Vector3.UP), mid)
		_line.scale = Vector3(1, 1, dist)
