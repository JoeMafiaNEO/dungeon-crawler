class_name MusicGen
extends RefCounted
## Generative ambient music. Each theme gets a deterministic chord-pad loop
## with bass and a sparse bell/pluck melody, rendered once and looped.
## Everything is synthesized -- no music files ship with the game.

const SR := 22050

static var _note_cache: Dictionary = {}


static func _nf(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## Render a single note into a buffer. Cached by (freq, dur, timbre).
static func _note(freq: float, dur: float, timbre: String, vol: float) -> PackedFloat32Array:
	var key := "%d_%.1f_%s" % [int(freq * 10.0), dur, timbre]
	if _note_cache.has(key):
		return _note_cache[key]
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	match timbre:
		"pad":
			# Slow-attack detuned stack: fundamental + harmonics with chorus.
			for i in n:
				var t := float(i) / SR
				var k := t / dur
				var attack := minf(1.0, t / 1.2)
				var release := minf(1.0, (dur - t) / 1.5)
				var env: float = attack * attack * release * vol
				var v := sin(TAU * freq * t) * 0.5
				v += sin(TAU * freq * 1.003 * t) * 0.3
				v += sin(TAU * freq * 0.997 * t) * 0.3
				v += sin(TAU * freq * 2.0 * t) * 0.18
				v += sin(TAU * freq * 3.0 * t) * 0.08
				out[i] = v * env
		"bass":
			for i in n:
				var t := float(i) / SR
				var k := t / dur
				var attack := minf(1.0, t / 0.15)
				var release := minf(1.0, (dur - t) / 0.8)
				var env: float = attack * release * vol
				var v := sin(TAU * freq * t) * 0.7 + sin(TAU * freq * 2.0 * t) * 0.2
				out[i] = v * env
		"bell":
			# Long-decay metallic-ish bell.
			for i in n:
				var t := float(i) / SR
				var env: float = exp(-2.2 * t) * vol
				var v := sin(TAU * freq * t) * 0.6
				v += sin(TAU * freq * 2.76 * t) * 0.25 * exp(-3.0 * t)
				v += sin(TAU * freq * 5.4 * t) * 0.12 * exp(-5.0 * t)
				out[i] = v * env
		"pluck":
			for i in n:
				var t := float(i) / SR
				var env: float = exp(-6.0 * t) * vol
				var v := asin(sin(TAU * freq * t)) * 0.8
				v += sin(TAU * freq * 2.0 * t) * 0.15
				out[i] = v * env
	_note_cache[key] = out
	return out


static func _place(track: PackedFloat32Array, note: PackedFloat32Array, at_sec: float) -> void:
	var start := int(SR * at_sec)
	for i in note.size():
		var j := start + i
		if j < track.size():
			track[j] += note[i]


static func _add_echo(track: PackedFloat32Array) -> void:
	# Cheap space: two low-mix delays.
	var d1 := int(SR * 0.31)
	var d2 := int(SR * 0.47)
	var src := track.duplicate()
	for i in range(d1, track.size()):
		track[i] += src[i - d1] * 0.22
	for i in range(d2, track.size()):
		track[i] += src[i - d2] * 0.13


static func _wind_bed(dur: float, vol: float, seed: int) -> PackedFloat32Array:
	var n := int(SR * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var last := 0.0
	for i in n:
		var v := rng.randf_range(-1.0, 1.0)
		last = lerpf(v, last, 0.97)
		out[i] = last * vol
	return out


## chords: Array of {root: midi, tones: [midi...]}, melody: pentatonic midi list
static func _render(chords: Array, bass_roots: Array, melody: Array, chord_len: float,
		melody_timbre: String, wind_vol: float, seed: int) -> AudioStreamWAV:
	var total := chord_len * chords.size()
	var n := int(SR * total)
	var track := PackedFloat32Array()
	track.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for ci in chords.size():
		var at := float(ci) * chord_len
		var chord: Array = chords[ci]
		for m in chord:
			_place(track, _note(_nf(float(m)), chord_len + 1.0, "pad", 0.16), at)
		_place(track, _note(_nf(float(bass_roots[ci])), chord_len, "bass", 0.5), at)
		# Sparse melody: one note per chord, sometimes two.
		var slots := 2
		for s in slots:
			if rng.randf() < 0.75:
				var note_midi: float = melody[rng.randi_range(0, melody.size() - 1)]
				_place(track, _note(_nf(note_midi), 3.0, melody_timbre, 0.28),
					at + float(s) * chord_len * 0.5 + rng.randf_range(0.0, 0.4))
	if wind_vol > 0.0:
		var bed := _wind_bed(total, wind_vol, seed + 99)
		for i in n:
			track[i] += bed[i]
	_add_echo(track)
	# Normalize.
	var peak := 0.001
	for s in track:
		peak = maxf(peak, absf(s))
	var gain := 0.85 / peak
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(track[i] * gain, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


static func make_track(theme_id: String) -> AudioStreamWAV:
	match theme_id:
		"village":
			# Warm and gentle: C - G - Am - F, plucked melody.
			return _render(
				[[48, 52, 55, 60], [43, 47, 50, 55], [45, 48, 52, 57], [41, 45, 48, 53]],
				[36, 31, 33, 29],
				[72, 74, 76, 79, 81, 84], 4.0, "pluck", 0.0, 101)
		"dungeon":
			# Dark and pulsing: Dm - Bb - Gm - A, bell melody, wind bed.
			return _render(
				[[50, 53, 57, 62], [46, 50, 53, 58], [43, 46, 50, 55], [45, 49, 52, 57]],
				[26, 22, 19, 21],
				[69, 72, 74, 76, 79, 81], 4.0, "bell", 0.05, 202)
		"depths":
			# Deep and slow: Cm - Ab - Bb - G, sparse bells, heavy wind.
			return _render(
				[[48, 51, 55, 60], [44, 48, 51, 56], [46, 50, 53, 58], [43, 47, 50, 55]],
				[24, 20, 22, 19],
				[60, 63, 65, 67, 70, 72], 6.0, "bell", 0.09, 303)
		_:
			# Menu: calm mystery, Am - F - C - G.
			return _render(
				[[45, 48, 52, 57], [41, 45, 48, 53], [48, 52, 55, 60], [43, 47, 50, 55]],
				[33, 29, 36, 31],
				[69, 72, 74, 76, 79, 81, 84], 4.0, "bell", 0.02, 404)
