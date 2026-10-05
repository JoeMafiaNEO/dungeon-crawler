class_name SoundSynth
extends RefCounted
## Procedural sound-effect synthesizer. Every SFX is generated in code as a
## 22050 Hz mono 16-bit WAV -- no audio files ship with the game, everything
## is CC0-by-construction. Callers should go through AudioManager, which
## caches the streams returned here.

const SR := 22050


# --- core helpers ---

static func _wav(samples: PackedFloat32Array, vol: float = 1.0) -> AudioStreamWAV:
	var peak := 0.001
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain: float = vol / peak
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = data
	return w


static func _tone(f0: float, f1: float, dur: float, wave: String, decay: float, vol: float = 1.0, delay: float = 0.0) -> PackedFloat32Array:
	var n := int(SR * (dur + delay))
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var start := int(SR * delay)
	for i in range(start, n):
		var t := float(i - start) / SR
		var k := t / dur
		var f := lerpf(f0, f1, k)
		phase += TAU * f / SR
		var v := 0.0
		match wave:
			"sine":
				v = sin(phase)
			"square":
				v = 1.0 if sin(phase) >= 0.0 else -1.0
				v *= 0.6
			"saw":
				v = (fmod(phase, TAU) / TAU) * 2.0 - 1.0
				v *= 0.7
			"tri":
				v = asin(sin(phase)) * 0.9
		var env := exp(-decay * t)
		out[i] += v * env * vol
	return out


static func _noise(dur: float, decay: float, vol: float = 1.0, delay: float = 0.0, lowpass: float = 0.0) -> PackedFloat32Array:
	var n := int(SR * (dur + delay))
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234567
	var last := 0.0
	var start := int(SR * delay)
	for i in range(start, n):
		var t := float(i - start) / SR
		var v := rng.randf_range(-1.0, 1.0)
		if lowpass > 0.0:
			# One-pole lowpass; higher lowpass value = darker.
			last = lerpf(v, last, clampf(lowpass, 0.0, 0.99))
			v = last
		out[i] += v * exp(-decay * t) * vol
	return out


static func _mix(parts: Array) -> PackedFloat32Array:
	var longest := 0
	for p in parts:
		longest = maxi(longest, (p as PackedFloat32Array).size())
	var out := PackedFloat32Array()
	out.resize(longest)
	for p in parts:
		var a := p as PackedFloat32Array
		for i in a.size():
			out[i] += a[i]
	return out


# --- combat ---

static func swing() -> AudioStreamWAV:
	# Whoosh: bandy noise burst sweeping down.
	return _wav(_noise(0.16, 22.0, 0.9, 0.0, 0.55))


static func bow_shot() -> AudioStreamWAV:
	# Bowstring twang: quick pitch drop + snap.
	return _wav(_mix([
		_tone(320.0, 90.0, 0.1, "triangle", 40.0, 0.8),
		_noise(0.04, 80.0, 0.4),
	]))


static func arrow_hit() -> AudioStreamWAV:
	# Arrow thud: short woody knock.
	return _wav(_mix([
		_tone(220.0, 110.0, 0.08, "sine", 35.0, 0.9),
		_noise(0.03, 50.0, 0.35),
	]))


static func dash() -> AudioStreamWAV:
	# Dash whoosh: airy noise sweep up.
	return _wav(_noise(0.18, 18.0, 0.7, 0.9, 0.35))


static func revive() -> AudioStreamWAV:
	# Revive chime: warm rising arpeggio.
	return _wav(_mix([
		_tone(440.0, 440.0, 0.12, "sine", 30.0, 0.7),
		_tone(554.0, 554.0, 0.12, "sine", 30.0, 0.7),
		_tone(659.0, 659.0, 0.2, "sine", 30.0, 0.8),
	]))


static func frost_cast() -> AudioStreamWAV:
	# Crystalline whoosh: high shimmer + air.
	return _wav(_mix([
		_tone(1200.0, 2400.0, 0.15, "sine", 25.0, 0.5),
		_noise(0.12, 30.0, 0.4, 0.0, 0.7),
	]))


static func frost_hit() -> AudioStreamWAV:
	# Ice shatter: bright crash.
	return _wav(_mix([
		_noise(0.1, 70.0, 0.6),
		_tone(1800.0, 900.0, 0.08, "triangle", 30.0, 0.5),
	]))


static func lightning_cast() -> AudioStreamWAV:
	# Electric crack: sharp zap.
	return _wav(_mix([
		_noise(0.08, 90.0, 0.7),
		_tone(200.0, 80.0, 0.1, "sawtooth", 40.0, 0.6),
	]))


static func lightning_zap() -> AudioStreamWAV:
	return _wav(_noise(0.06, 80.0, 0.5))


static func meteor_cast() -> AudioStreamWAV:
	# Deep rumble rising.
	return _wav(_mix([
		_tone(60.0, 120.0, 0.4, "sine", 20.0, 0.8),
		_noise(0.3, 25.0, 0.4),
	]))


static func meteor_incoming() -> AudioStreamWAV:
	# Whistling descent.
	return _wav(_tone(900.0, 300.0, 0.8, "sine", 15.0, 0.4))


static func ability_unlock() -> AudioStreamWAV:
	# Bright unlock fanfare.
	return _wav(_mix([
		_tone(523.0, 523.0, 0.1, "triangle", 30.0, 0.7),
		_tone(784.0, 784.0, 0.18, "triangle", 30.0, 0.7),
	]))


static func holy_light_cast() -> AudioStreamWAV:
	# Rising shimmer.
	return _wav(_mix([
		_tone(440.0, 880.0, 0.4, "sine", 25.0, 0.6),
		_tone(660.0, 1320.0, 0.4, "triangle", 25.0, 0.4),
	]))


static func holy_light() -> AudioStreamWAV:
	# Warm radiant wash.
	return _wav(_mix([
		_tone(523.0, 523.0, 1.2, "sine", 20.0, 0.5),
		_tone(784.0, 784.0, 1.2, "sine", 20.0, 0.4),
		_tone(1046.0, 1046.0, 1.0, "triangle", 20.0, 0.3),
	]))


static func cash_register() -> AudioStreamWAV:
	# Cha-ching!
	return _wav(_mix([
		_tone(880.0, 880.0, 0.08, "square", 25.0, 0.5),
		_tone(1320.0, 1320.0, 0.15, "square", 25.0, 0.5),
	]))


static func totem_place() -> AudioStreamWAV:
	# Heavy wooden thud + earthy resonance.
	return _wav(_mix([
		_tone(90.0, 45.0, 0.25, "sine", 25.0, 0.9),
		_noise(0.08, 40.0, 0.4),
	]))


static func totem_expire() -> AudioStreamWAV:
	# Soft fade-out shimmer.
	return _wav(_tone(400.0, 150.0, 0.4, "sine", 20.0, 0.4))


static func eagle_eye() -> AudioStreamWAV:
	# Hawk cry: sharp descending screech.
	return _wav(_mix([
		_tone(1800.0, 900.0, 0.25, "sawtooth", 30.0, 0.5),
		_tone(2400.0, 1200.0, 0.2, "sine", 25.0, 0.4),
	]))


static func smoke_veil() -> AudioStreamWAV:
	# Poof of smoke: soft noise burst.
	return _wav(_noise(0.35, 20.0, 0.6, 0.0, 0.4))


static func mark() -> AudioStreamWAV:
	# Target lock: crisp double-beep.
	return _wav(_mix([
		_tone(880.0, 880.0, 0.08, "square", 30.0, 0.4),
		_tone(1174.0, 1174.0, 0.12, "square", 30.0, 0.4),
	]))


static func mark_applied() -> AudioStreamWAV:
	return _wav(_tone(660.0, 660.0, 0.1, "square", 30.0, 0.3))


static func barrage_cast() -> AudioStreamWAV:
	# Triple zap: rapid fire crackles.
	return _wav(_mix([
		_noise(0.06, 70.0, 0.5),
		_noise(0.13, 70.0, 0.5, 0.07),
		_noise(0.2, 70.0, 0.5, 0.14),
	]))


static func blizzard_cast() -> AudioStreamWAV:
	# Howling wind buildup.
	return _wav(_mix([
		_noise(0.5, 25.0, 0.5, 0.0, 0.6),
		_tone(300.0, 600.0, 0.4, "sine", 20.0, 0.3),
	]))


static func blizzard_loop() -> AudioStreamWAV:
	return _wav(_noise(0.8, 22.0, 0.35, 0.0, 0.5))


static func shadow_step() -> AudioStreamWAV:
	# Dark blink: low whoosh + shimmer.
	return _wav(_mix([
		_noise(0.15, 25.0, 0.6, 0.9, 0.3),
		_tone(800.0, 1600.0, 0.12, "sine", 25.0, 0.4),
	]))


static func fan() -> AudioStreamWAV:
	# Whirling blades: metallic swishes.
	return _wav(_mix([
		_noise(0.2, 45.0, 0.55, 0.3, 0.6),
		_tone(1500.0, 900.0, 0.15, "triangle", 30.0, 0.4),
	]))


static func milestone() -> AudioStreamWAV:
	# Epic milestone fanfare.
	return _wav(_mix([
		_tone(392.0, 392.0, 0.15, "triangle", 32.0, 0.7),
		_tone(523.0, 523.0, 0.15, "triangle", 32.0, 0.7, 0.12),
		_tone(659.0, 659.0, 0.15, "triangle", 32.0, 0.7, 0.24),
		_tone(784.0, 784.0, 0.35, "triangle", 30.0, 0.8, 0.36),
	]))


static func hit() -> AudioStreamWAV:
	# Meaty thwack: pitch-dropping sine + click.
	return _wav(_mix([
		_tone(170.0, 55.0, 0.12, "sine", 30.0, 1.0),
		_noise(0.05, 60.0, 0.5),
	]))


static func mob_die() -> AudioStreamWAV:
	# Descending blip + soft poof.
	return _wav(_mix([
		_tone(420.0, 70.0, 0.28, "square", 9.0, 0.55),
		_noise(0.22, 10.0, 0.5, 0.02, 0.7),
	]))


static func player_hurt() -> AudioStreamWAV:
	# Harsh grunt-ish hit.
	return _wav(_mix([
		_tone(220.0, 90.0, 0.2, "saw", 16.0, 0.8),
		_noise(0.12, 25.0, 0.6),
	]))


static func player_die() -> AudioStreamWAV:
	return _wav(_mix([
		_tone(300.0, 50.0, 0.7, "saw", 5.0, 0.8),
		_tone(150.0, 40.0, 0.7, "sine", 5.0, 1.0, 0.05),
	]))


static func fireball_cast() -> AudioStreamWAV:
	# Rising whoosh with heat.
	return _wav(_mix([
		_noise(0.35, 6.0, 0.8, 0.0, 0.35),
		_tone(120.0, 480.0, 0.3, "saw", 7.0, 0.35),
	]))


static func explosion() -> AudioStreamWAV:
	# Boom: sub drop + noise burst.
	return _wav(_mix([
		_tone(70.0, 28.0, 0.6, "sine", 6.0, 1.2),
		_noise(0.5, 7.0, 0.9, 0.0, 0.5),
		_noise(0.12, 30.0, 0.7),
	]))


# --- loot / progression ---

static func pickup() -> AudioStreamWAV:
	# Bright two-note pickup blip.
	return _wav(_mix([
		_tone(660.0, 660.0, 0.09, "sine", 28.0, 0.8),
		_tone(990.0, 990.0, 0.12, "sine", 24.0, 0.8, 0.07),
	]))


static func coin() -> AudioStreamWAV:
	return _wav(_mix([
		_tone(1320.0, 1320.0, 0.07, "square", 30.0, 0.4),
		_tone(1760.0, 1760.0, 0.1, "square", 26.0, 0.4, 0.06),
	]))


static func drink() -> AudioStreamWAV:
	# Glug-glug: three descending gulps.
	return _wav(_mix([
		_tone(400.0, 250.0, 0.12, "sine", 20.0, 0.7),
		_tone(350.0, 220.0, 0.12, "sine", 20.0, 0.7, 0.13),
		_tone(300.0, 180.0, 0.16, "sine", 18.0, 0.7, 0.26),
	]))


static func key() -> AudioStreamWAV:
	# Bright metallic jingle: high chime + shimmer.
	return _wav(_mix([
		_tone(1568.0, 1568.0, 0.12, "triangle", 30.0, 0.6),
		_tone(2093.0, 2093.0, 0.16, "triangle", 26.0, 0.5, 0.08),
		_tone(2637.0, 2500.0, 0.2, "sine", 22.0, 0.4, 0.16),
	]))


static func unlock() -> AudioStreamWAV:
	# Triumphant unlock fanfare: rising major arpeggio + low thud.
	return _wav(_mix([
		_tone(392.0, 392.0, 0.14, "triangle", 32.0, 0.7),
		_tone(523.0, 523.0, 0.14, "triangle", 32.0, 0.7, 0.12),
		_tone(659.0, 659.0, 0.14, "triangle", 32.0, 0.7, 0.24),
		_tone(784.0, 784.0, 0.3, "triangle", 30.0, 0.7, 0.36),
		_tone(120.0, 60.0, 0.25, "sine", 24.0, 0.8),
	]))


static func boss_roar() -> AudioStreamWAV:
	# Deep guttural roar: low sawtooth growl with pitch wobble.
	return _wav(_mix([
		_tone(90.0, 55.0, 0.7, "saw", 40.0, 0.9),
		_tone(135.0, 82.0, 0.7, "saw", 34.0, 0.7, 0.05),
		_tone(60.0, 40.0, 0.8, "sine", 44.0, 0.9, 0.1),
	]))


static func boss_slam() -> AudioStreamWAV:
	# Ground-shaking slam: sub thump + noise crash.
	return _wav(_mix([
		_tone(70.0, 30.0, 0.4, "sine", 48.0, 1.0),
		_tone(150.0, 60.0, 0.25, "square", 30.0, 0.5),
		_noise(0.3, 20.0, 0.5, 0.05),
	]))


static func boss_die() -> AudioStreamWAV:
	# Epic death: descending roar + final boom.
	return _wav(_mix([
		_tone(200.0, 50.0, 0.9, "saw", 36.0, 0.8),
		_tone(100.0, 30.0, 1.1, "sine", 40.0, 0.9, 0.2),
		_noise(0.5, 16.0, 0.6, 0.4),
	]))


static func levelup() -> AudioStreamWAV:
	# Ascending major arpeggio, warm.
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var parts: Array = []
	for i in notes.size():
		parts.append(_tone(notes[i], notes[i], 0.35, "tri", 7.0, 0.7, 0.09 * i))
	return _wav(_mix(parts))


static func wave_horn() -> AudioStreamWAV:
	# Low war-horn swell: root + fifth, slow attack via low decay.
	return _wav(_mix([
		_tone(98.0, 92.0, 0.9, "saw", 3.2, 0.7),
		_tone(147.0, 138.0, 0.9, "saw", 3.2, 0.5, 0.03),
		_tone(49.0, 46.0, 0.9, "sine", 3.0, 0.9),
	]))


static func wave_clear() -> AudioStreamWAV:
	var notes := [392.0, 523.25, 659.25]
	var parts: Array = []
	for i in notes.size():
		parts.append(_tone(notes[i], notes[i], 0.4, "sine", 6.0, 0.7, 0.1 * i))
	return _wav(_mix(parts))


# --- movement ---

static func jump() -> AudioStreamWAV:
	return _wav(_noise(0.12, 18.0, 0.35, 0.0, 0.3))


static func land() -> AudioStreamWAV:
	return _wav(_mix([
		_tone(130.0, 45.0, 0.12, "sine", 26.0, 0.9),
		_noise(0.07, 30.0, 0.3, 0.0, 0.6),
	]))


static func footstep() -> AudioStreamWAV:
	# Soft shuffling step: gentle lowpassed noise, quiet.
	return _wav(_noise(0.09, 28.0, 0.16, 0.0, 0.9))


# --- train (station Phase 5) ---

static func train_whistle() -> AudioStreamWAV:
	# Classic two-tone steam whistle: 660Hz then 550Hz, slight chorus detune
	# for vibrato-ish shimmer.
	return _wav(_mix([
		_tone(660.0, 655.0, 0.55, "sine", 1.6, 0.75),
		_tone(667.0, 662.0, 0.55, "sine", 1.6, 0.45),
		_tone(550.0, 545.0, 0.65, "sine", 1.6, 0.75, 0.55),
		_tone(556.0, 551.0, 0.65, "sine", 1.6, 0.45, 0.55),
	]))


static func train_chug() -> AudioStreamWAV:
	# Steam engine pulling out: accelerating low filtered-noise chugs.
	var parts: Array = []
	var t := 0.0
	var gap := 0.30
	while t < 2.0:
		parts.append(_noise(0.12, 16.0, 0.85, t, 0.88))
		parts.append(_tone(70.0, 55.0, 0.10, "sine", 18.0, 0.5, t))
		t += gap
		gap = maxf(0.14, gap * 0.88)
	return _wav(_mix(parts))


static func train_brake() -> AudioStreamWAV:
	# Metallic arrival screech: descending high tone + gritty noise.
	return _wav(_mix([
		_tone(2800.0, 1400.0, 1.5, "saw", 2.0, 0.35),
		_tone(2850.0, 1450.0, 1.5, "saw", 2.0, 0.25, 0.03),
		_noise(1.5, 2.2, 0.20, 0.0, 0.15),
	]))


# --- train interior (issue #3 Phase 1) ---

static func train_door_open() -> AudioStreamWAV:
	# Pneumatic sliding door: air hiss, then the metallic clunk of the latch.
	return _wav(_mix([
		_noise(0.45, 14.0, 0.55, 0.0, 0.65),
		_tone(190.0, 120.0, 0.14, "square", 22.0, 0.35, 0.42),
	]))

static func train_door_close() -> AudioStreamWAV:
	# Latch clunk first, then the hiss release as the seal sets.
	return _wav(_mix([
		_tone(210.0, 130.0, 0.14, "square", 22.0, 0.35, 0.0),
		_noise(0.40, 14.0, 0.50, 0.12, 0.55),
	]))


# --- UI ---

static func ui_click() -> AudioStreamWAV:
	return _wav(_tone(1250.0, 900.0, 0.06, "sine", 40.0, 0.6))


static func ui_hover() -> AudioStreamWAV:
	return _wav(_tone(1600.0, 1600.0, 0.04, "sine", 50.0, 0.25))


static func ui_error() -> AudioStreamWAV:
	return _wav(_tone(220.0, 180.0, 0.15, "square", 18.0, 0.4))


static func ping() -> AudioStreamWAV:
	# Attention ping: bright rising double-blip for co-op communication.
	return _wav(_mix([
		_tone(990.0, 990.0, 0.09, "sine", 26.0, 0.7),
		_tone(1320.0, 1320.0, 0.16, "sine", 22.0, 0.7, 0.11),
	]))


# --- ambient one-shots (scheduled by the dungeon per theme) ---

static func wind_gust() -> AudioStreamWAV:
	# Slow swell of dark noise, ~2.5s.
	var n := int(SR * 2.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var last := 0.0
	for i in n:
		var t := float(i) / SR
		var swell := sin(PI * t / 2.5) # up then down
		swell *= swell
		var v := rng.randf_range(-1.0, 1.0)
		last = lerpf(v, last, 0.92)
		out[i] = last * swell * 0.5
	return _wav(out, 0.8)


static func drip() -> AudioStreamWAV:
	# Water drip: bright ping dropping fast.
	return _wav(_mix([
		_tone(900.0, 350.0, 0.09, "sine", 45.0, 0.7),
		_tone(1800.0, 700.0, 0.05, "sine", 60.0, 0.3),
	]))


static func rumble() -> AudioStreamWAV:
	# Deep earth groan, ~2s.
	return _wav(_mix([
		_tone(55.0, 38.0, 2.0, "sine", 2.2, 1.0),
		_noise(2.0, 2.5, 0.35, 0.0, 0.95),
	]), 0.7)


static func bird() -> AudioStreamWAV:
	# Cheerful FM-ish chirp: two quick descending sweeps.
	return _wav(_mix([
		_tone(3200.0, 2400.0, 0.09, "sine", 30.0, 0.5),
		_tone(3400.0, 2600.0, 0.09, "sine", 30.0, 0.5, 0.12),
		_tone(3000.0, 3600.0, 0.07, "sine", 32.0, 0.4, 0.24),
	]), 0.8)


static func torch_crackle() -> AudioStreamWAV:
	# Short fire crackle for torch ambience.
	return _wav(_noise(0.3, 12.0, 0.4, 0.0, 0.25))
