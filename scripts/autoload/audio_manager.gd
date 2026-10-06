extends Node
## Central audio: music crossfading, pooled SFX (2D + positional 3D),
## volume persistence. All audio is synthesized in code (SoundSynth/MusicGen);
## drop a file at res://assets/audio/sfx/<name>.ogg (or .wav) or
## res://assets/audio/music/<theme>.ogg to override any generated sound.

const POOL_SIZE := 12
const CFG_PATH := "user://audio.cfg"

var _sfx_cache: Dictionary = {}
var _music_cache: Dictionary = {}
var _sfx_builders: Dictionary = {}
var _pool: Array = []
var _pool_i := 0
var _mus_a: AudioStreamPlayer
var _mus_b: AudioStreamPlayer
var _mus_active: AudioStreamPlayer
var _mus_theme := ""
var _gen_busy := false
var _queued_theme := ""

var master_vol := 1.0
var music_vol := 0.8
var sfx_vol := 1.0


func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	for b in ["swing", "hit", "mob_die", "player_hurt", "player_die", "fireball_cast",
			"explosion", "pickup", "coin", "levelup", "wave_horn", "wave_clear",
			"jump", "land", "footstep", "drink",
			"key", "unlock", "ability_unlock", "boss_roar", "boss_slam", "boss_die", "bow_shot", "arrow_hit", "dash", "revive",
			"frost_cast", "frost_hit", "lightning_cast", "lightning_zap", "meteor_cast", "meteor_incoming",
			"totem_place", "totem_expire",
			"eagle_eye", "smoke_veil", "mark", "mark_applied",
			"barrage_cast", "blizzard_cast", "blizzard_loop", "shadow_step", "fan", "milestone",
			"ui_click", "ui_hover", "ui_error", "ping",
			"wind_gust", "drip", "rumble", "bird", "torch_crackle",
			"train_whistle", "train_chug", "train_brake",
			"train_door_open", "train_door_close",
			"all_aboard", "board_chime", "door_lock", "countdown_tick",
			"vote_cast", "apex_announce", "apex_roar",
			"cash_register", "holy_light", "holy_light_cast",
			"thunderclap",
			"relic_pickup", "vault_open", "vault_close", "relic_equip",
			"bounty_accept", "bounty_complete", "bounty_toast",
			"finisher_orbital_strike", "finisher_stormcall",
			"finisher_shatter_cascade", "finisher_reciprocity_surge",
			"finisher_smoke_bombard", "codex_discover"]:
		_sfx_builders[b] = Callable(SoundSynth, b)
	for i in POOL_SIZE:
		var pl := AudioStreamPlayer.new()
		pl.bus = "SFX"
		add_child(pl)
		_pool.append(pl)
	_mus_a = AudioStreamPlayer.new()
	_mus_a.bus = "Music"
	_mus_b = AudioStreamPlayer.new()
	_mus_b.bus = "Music"
	add_child(_mus_a)
	add_child(_mus_b)
	_mus_active = _mus_a
	_load_volumes()
	_apply_volumes()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


# --- volumes ---

func set_master_vol(v: float) -> void:
	master_vol = clampf(v, 0.0, 1.0)
	_apply_volumes()
	_save_volumes()


func set_music_vol(v: float) -> void:
	music_vol = clampf(v, 0.0, 1.0)
	_apply_volumes()
	_save_volumes()


func set_sfx_vol(v: float) -> void:
	sfx_vol = clampf(v, 0.0, 1.0)
	_apply_volumes()
	_save_volumes()


func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(maxf(master_vol, 0.001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music_vol, 0.001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(sfx_vol, 0.001)))


func _save_volumes() -> void:
	var c := ConfigFile.new()
	c.set_value("vol", "master", master_vol)
	c.set_value("vol", "music", music_vol)
	c.set_value("vol", "sfx", sfx_vol)
	c.save(CFG_PATH)


func _load_volumes() -> void:
	var c := ConfigFile.new()
	if c.load(CFG_PATH) == OK:
		master_vol = float(c.get_value("vol", "master", 1.0))
		music_vol = float(c.get_value("vol", "music", 0.8))
		sfx_vol = float(c.get_value("vol", "sfx", 1.0))


# --- SFX ---

func _get_sfx(sfx_name: String) -> AudioStream:
	if _sfx_cache.has(sfx_name):
		return _sfx_cache[sfx_name]
	# File override first.
	for ext in ["ogg", "wav"]:
		var path := "res://assets/audio/sfx/%s.%s" % [sfx_name, ext]
		if ResourceLoader.exists(path):
			var w := load(path) as AudioStream
			if w != null:
				_sfx_cache[sfx_name] = w
				return w
	var w2: AudioStream = null
	if _sfx_builders.has(sfx_name):
		w2 = (_sfx_builders[sfx_name] as Callable).call()
	if w2 != null:
		_sfx_cache[sfx_name] = w2
	return w2


## Play a named SFX. Pass a Vector3 for positional 3D playback.
func sfx(sfx_name: String, pos: Variant = null, pitch: float = 1.0, vol: float = 1.0) -> void:
	var stream := _get_sfx(sfx_name)
	if stream == null:
		return
	var p := pitch * randf_range(0.95, 1.05)
	if pos is Vector3:
		var pl3d := AudioStreamPlayer3D.new()
		pl3d.bus = "SFX"
		pl3d.stream = stream
		pl3d.pitch_scale = p
		pl3d.volume_db = linear_to_db(maxf(vol, 0.001))
		pl3d.max_distance = 40.0
		pl3d.position = pos
		get_tree().current_scene.add_child(pl3d)
		pl3d.finished.connect(pl3d.queue_free)
		pl3d.play()
	else:
		var pl: AudioStreamPlayer = _pool[_pool_i]
		_pool_i = (_pool_i + 1) % POOL_SIZE
		pl.stream = stream
		pl.pitch_scale = p
		pl.volume_db = linear_to_db(maxf(vol, 0.001))
		pl.play()


# --- music ---

## Crossfade to a theme's music loop. Procedural themes: "menu", "village",
## "dungeon", "depths", "supermarket", "warlord", "apex". File-backed themes
## in res://assets/audio/music/<id>.ogg|wav|mp3 (e.g. "train", Jesse's
## inside-train recording) override the synth and loop automatically.
func play_music(theme_id: String) -> void:
	if theme_id == _mus_theme and _mus_active.playing:
		return
	if _music_cache.has(theme_id):
		_crossfade_to(theme_id)
		return
	_queued_theme = theme_id
	if _gen_busy:
		return
	_gen_busy = true
	var th := Thread.new()
	th.start(_gen_track.bind(theme_id, th))


func stop_music() -> void:
	_mus_theme = ""
	_queued_theme = ""
	for pl in [_mus_a, _mus_b]:
		var tw := create_tween()
		tw.tween_property(pl, "volume_db", -60.0, 1.0)
		tw.tween_callback(pl.stop)


func _gen_track(theme_id: String, th: Thread) -> void:
	var w: AudioStream = null
	for ext in ["ogg", "wav", "mp3"]:
		var path := "res://assets/audio/music/%s.%s" % [theme_id, ext]
		if ResourceLoader.exists(path):
			w = load(path) as AudioStream
			break
	if w == null:
		w = MusicGen.make_track(theme_id)
	else:
		_enable_track_loop(w)
	call_deferred("_on_track_ready", theme_id, w, th)


## File-backed music themes loop like the procedural ones (which set
## LOOP_FORWARD at render time). Jesse's train ambient rides the music bus.
func _enable_track_loop(w: AudioStream) -> void:
	if w is AudioStreamMP3:
		(w as AudioStreamMP3).loop = true
	elif w is AudioStreamOggVorbis:
		(w as AudioStreamOggVorbis).loop = true
	elif w is AudioStreamWAV:
		var wav := w as AudioStreamWAV
		var bytes_per_frame := (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1) \
			* (2 if wav.stereo else 1)
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.get_data().size() / bytes_per_frame


func _on_track_ready(theme_id: String, w: AudioStream, th: Thread) -> void:
	th.wait_to_finish()
	_music_cache[theme_id] = w
	_gen_busy = false
	if _queued_theme == theme_id:
		_crossfade_to(theme_id)
	elif _queued_theme != "":
		# A different theme was requested while this one generated; pick it up
		# now instead of leaving the game silent until the next theme change.
		play_music(_queued_theme)


func _crossfade_to(theme_id: String) -> void:
	_mus_theme = theme_id
	var next: AudioStreamPlayer = _mus_b if _mus_active == _mus_a else _mus_a
	var prev := _mus_active
	_mus_active = next
	next.stream = _music_cache[theme_id]
	next.volume_db = -60.0
	next.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(next, "volume_db", 0.0, 2.0)
	tw.tween_property(prev, "volume_db", -60.0, 2.0)
	tw.chain().tween_callback(prev.stop)
