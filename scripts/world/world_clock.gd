class_name WorldClock
extends RefCounted
## Issue #204 (P4): the Act 2 world clock (Jesse's refinement,
## SE option (b)). `world_time` is accumulated Act 2 play time
## in seconds, carried in the run save, advanced by the server
## only while the run is played, lightly synced, and pulled on
## join/continue with the run record (#135-style).
##
## ALL presentation is a pure function of world_time, derived
## locally on every peer through the P2 parameter mechanism: a
## keyframed day cycle (dawn / day / dusk / night) over the
## same sky / sun / fog parameters the level themes carry.
## Entry's first look is the bright-clear day state
## (ENTRY_TIME). v1 nights are MOONLIT: the sun (read as the
## moon) and ambient energies floor at the MOON_* constants —
## never full dark. The day length is a TUNING PLACEHOLDER.
## Weather is NOT here (its own phase, P7).

const DAY_LENGTH := 600.0 ## TUNING PLACEHOLDER: seconds per cycle
const ENTRY_TIME := 150.0 ## tod 0.25: bright morning, first look
const MOON_SUN_ENERGY := 0.22
const MOON_AMBIENT_ENERGY := 0.20

# Keyframes: [tod, sky_top, sky_horizon, ground, sun_color,
# sun_energy, ambient_color, ambient_energy, fog_color,
# fog_density, fog_sky_affect, sky_energy, sun_dir].
const KEYS: Array = [
	[0.00, Color(0.36, 0.44, 0.66), Color(0.98, 0.62, 0.38),
		Color(0.32, 0.27, 0.22), Color(1.0, 0.72, 0.50), 0.55,
		Color(0.55, 0.50, 0.48), 0.34, Color(0.85, 0.62, 0.48),
		0.004, 0.50, 0.90, Vector3(0.85, 0.12, 0.30)],
	[0.07, Color(0.24, 0.48, 0.92), Color(0.74, 0.83, 0.95),
		Color(0.35, 0.33, 0.28), Color(1.0, 0.95, 0.88), 1.05,
		Color(0.62, 0.66, 0.72), 0.45, Color(0.74, 0.82, 0.94),
		0.0025, 0.60, 1.00, Vector3(0.62, 0.55, 0.25)],
	[0.30, Color(0.22, 0.47, 0.95), Color(0.76, 0.85, 0.97),
		Color(0.36, 0.34, 0.29), Color(1.0, 0.97, 0.92), 1.20,
		Color(0.64, 0.68, 0.74), 0.50, Color(0.76, 0.84, 0.96),
		0.002, 0.60, 1.05, Vector3(0.15, 0.95, 0.20)],
	[0.52, Color(0.26, 0.46, 0.88), Color(0.78, 0.80, 0.92),
		Color(0.35, 0.32, 0.27), Color(1.0, 0.93, 0.84), 1.00,
		Color(0.62, 0.64, 0.70), 0.43, Color(0.76, 0.80, 0.92),
		0.0028, 0.58, 1.00, Vector3(-0.55, 0.50, 0.25)],
	[0.60, Color(0.30, 0.32, 0.58), Color(0.99, 0.50, 0.26),
		Color(0.30, 0.25, 0.21), Color(1.0, 0.60, 0.38), 0.50,
		Color(0.54, 0.48, 0.46), 0.30, Color(0.80, 0.55, 0.42),
		0.004, 0.52, 0.88, Vector3(-0.88, 0.10, 0.30)],
	[0.68, Color(0.03, 0.05, 0.13), Color(0.10, 0.13, 0.24),
		Color(0.05, 0.05, 0.07), Color(0.75, 0.82, 1.0),
		MOON_SUN_ENERGY, Color(0.40, 0.46, 0.62),
		MOON_AMBIENT_ENERGY, Color(0.09, 0.11, 0.19),
		0.0035, 0.50, 0.55, Vector3(-0.30, 0.75, -0.45)],
	[0.97, Color(0.03, 0.05, 0.13), Color(0.10, 0.13, 0.24),
		Color(0.05, 0.05, 0.07), Color(0.75, 0.82, 1.0),
		MOON_SUN_ENERGY, Color(0.40, 0.46, 0.62),
		MOON_AMBIENT_ENERGY, Color(0.09, 0.11, 0.19),
		0.0035, 0.50, 0.55, Vector3(-0.30, 0.75, -0.45)],
]


## Time of day, 0..1 (0 = dawn's first keyframe).
static func tod_of(world_time: float) -> float:
	return fposmod(world_time, DAY_LENGTH) / DAY_LENGTH


static func phase_of(world_time: float) -> String:
	var tod := tod_of(world_time)
	if tod < 0.07:
		return "dawn"
	if tod < 0.55:
		return "day"
	if tod < 0.68:
		return "dusk"
	return "night"


## The full environment parameter set at a world_time. Pure:
## the same world_time yields the identical presentation on
## every peer, which is what makes the light sync safe.
static func params_at(world_time: float) -> Dictionary:
	var tod := tod_of(world_time)
	var a: Array = KEYS[KEYS.size() - 1]
	var b: Array = KEYS[0]
	var t := 0.0
	for i in KEYS.size():
		var k0: Array = KEYS[i]
		var k1: Array = KEYS[(i + 1) % KEYS.size()]
		var t0 := float(k0[0])
		var t1 := float(k1[0]) + (1.0 if i == KEYS.size() - 1
			else 0.0)
		var tt := tod + (1.0 if tod < t0 and i == KEYS.size() - 1
			else 0.0)
		if tt >= t0 and tt <= t1:
			a = k0
			b = k1
			t = (tt - t0) / maxf(t1 - t0, 0.0001)
			break
	var dir := (a[12] as Vector3).lerp(b[12], t).normalized()
	return {
		"tod": tod,
		"phase": phase_of(world_time),
		"sky_top_color": (a[1] as Color).lerp(b[1], t),
		"sky_horizon_color": (a[2] as Color).lerp(b[2], t),
		"ground_color": (a[3] as Color).lerp(b[3], t),
		"sun_color": (a[4] as Color).lerp(b[4], t),
		"sun_energy": lerpf(float(a[5]), float(b[5]), t),
		"ambient_color": (a[6] as Color).lerp(b[6], t),
		"ambient_energy": lerpf(float(a[7]), float(b[7]), t),
		"fog_color": (a[8] as Color).lerp(b[8], t),
		"fog_density": lerpf(float(a[9]), float(b[9]), t),
		"fog_sky_affect": lerpf(float(a[10]), float(b[10]), t),
		"sky_energy_multiplier": lerpf(float(a[11]),
			float(b[11]), t),
		"sun_direction": dir,
	}
