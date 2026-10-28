class_name Player
extends CharacterBody3D
## First-person hack-and-slash character, client-authoritative.
## The owning peer simulates movement, mouse-look and attacks; snapshots are
## broadcast unreliably so remote peers can interpolate the billboard sprite.
## Loot goes into an inventory (E to pick up, I to manage); equipped items
## grant flat bonuses plus stacking multipliers.

signal health_changed(hp: float, max_hp: float)
signal xp_changed(xp: int, xp_next: int, level: int)
signal died
signal leveled_up(level: int)
## Issue #95 Phase 2: emitted when the player's click-action state changes
## (rogue dagger charge, Holy Light arm/charge). The mouse legend subscribes.
signal click_state_changed

const GRAVITY := 20.0
const JUMP_VELOCITY := 7.0
const SNAPSHOT_INTERVAL := 0.1
## Back-sprite integration (Jesse's depth rule): the front and back
## presentation planes are separated along the facing axis by this
## many sprite pixels (~the sprite's black outline width), so the
## pair never sits co-planar. Tunable; world offset = PX * pixel_size.
const BACK_SPRITE_DEPTH_PX := 3.0
const MOUSE_SENS := 0.0025
## Issue #144 Phase 1 (Q2): right-stick look rate at full tilt, rad/s.
const LOOK_STICK_RATE := 2.4
const EYE_HEIGHT := 1.6
const INVENTORY_MAX := 12
## Issue #113 Phase 1: weapon upgrade kits. PLACEHOLDER tuning (Jesse
## owns balance): flat damage granted per upgrade level on the equipped
## weapon stack, and the max upgrade level a weapon stack can reach.
const UPGRADE_DAMAGE_PER_LEVEL := 2.0
const UPGRADE_LEVEL_CAP := 5
const PICKUP_RANGE := 4.5
const FIREBALL_SPEED := 22.0

@export var class_id: String = "warrior"
## Steam ID of the owning player (0 = unknown / LAN). Used for the
## overhead name bar via Steam.getFriendPersonaName.
@export var steam_id: int = 0

## RTS faction in the Warlord's Domain (-1 = not in RTS mode).
var rts_faction := -1

var class_data: ClassData
var level := 1
var xp := 0
var xp_next := 25
var max_hp := 100.0
var hp := 100.0
## Jesse 2026-10-11: floating health bar above the player (visible to all).
var _phb_fill: Sprite3D = null
var _phb_full_w: float = 1.0
var _phb_bar_h: float = 0.22
var _phb_image: Image = null
var _phb_tex: ImageTexture = null
var _phb_img_w: int = 200
var _phb_img_h: int = 22
var damage := 10.0
var attack_cooldown := 0.5
var move_speed := 5.0
var attack_range := 2.8
var xp_mult := 1.0
# Every carried item applies its bonuses and multipliers. Death wipes them all.
# Inventory is an Array of stacks: { "item": ItemData, "count": int }.
# Same-type items combine into one stack; every copy contributes fully.
var inventory: Array = []
# Permanent stat points earned from leveling (kept through death).
var stat_points := 0
var bonus_damage := 0.0
var bonus_health := 0.0
var bonus_speed := 0.0
var bonus_aura := 0.0 # mage only: staff glow brightness per point
## Issue #184: ATK SPD investment — the fraction itself
## (+0.01 per stat point since #192's retune, NO cap, no
## class gate). Read
## through atk_spd_mult(); replicated via push_snapshot into
## net_bonus_atk_spd so server-side gates divide truly.
var bonus_atk_spd := 0.0
var supermarket_cash := 0 # cash from selling supermarket loot
## Relic Vault (issue #6): exactly one special equipped per run ("" = none).
## Run-scoped, saved with the run, cleared on a new run.
var equipped_special := ""
## Iron Resolve earn tracking: consecutive deathless level clears this run.
var no_death_streak := 0
## Greed Charm: loot-sale cash multiplier (1.0 = none).
var cash_mult := 1.0
## Iron Resolve: armed 1-HP survival save (once per run).
var second_wind_armed := false
var second_wind_used := false
## Apex specials (issue #5): effect multipliers from the equipped relic,
## set by _apply_equipped_special() from SpecialData effect_params.
var special_hp_mult := 1.0
var special_pickup_mult := 1.0
var special_cooldown_mult := 1.0


## Ability cooldown multiplier from the equipped special (apex_warden_sigil).
func cooldown_mult() -> float:
	return special_cooldown_mult


## Issue #184: attack-speed multiplier, computed on read
## (1.0 + the invested fraction). The authority copy reads its
## live investment; a replica reads the snapshot mirror — the
## sync_aura pattern, enforcement-grade: a server gate on a
## guest's copy divides by the guest's true investment.
func atk_spd_mult() -> float:
	if is_multiplayer_authority():
		# Issue #210 section 1.2 (settled): the owner's own
		# cadence folds the tree — the same combined value
		# that already rides the snapshot.
		return 1.0 + bonus_atk_spd + _tree_stat("atk_spd") \
			+ (_tree_tempo_pct / 100.0 \
				if Time.get_ticks_msec() < _tree_tempo_until \
				else 0.0) \
			+ (_tree_adrenaline_pct / 100.0 \
				if Time.get_ticks_msec() \
					< _tree_adrenaline_until \
				else 0.0)
	return 1.0 + net_bonus_atk_spd
## Bounty Board (issue #7): server-authoritative per-player progress,
## {bounty_id: count} (-1 = failed). Synced via player snapshots.
var bounty_progress := {}
var alive := true
var hud: CanvasLayer
## Downed (co-op only): not dead yet — a teammate can revive. Bleed out
## after REVIVE_WINDOW seconds, then it's a real death.
var downed := false
var _bleedout := 0.0
var _revive_channel := 0.0
## Issue #155 (ii): a deferred plant press at a tilled farm plot
## (tap = the tap tier, hold PLANT_HOLD_SECONDS = quality). The
## press arms only while the bag holds a quality packet — with
## none held, E dispatches instantly as it always has.
var _plant_hold_plot: Node = null
var _plant_hold_t := 0.0
var _plant_hold_fired := false
## Issue #163 Part 4: the peer the channel bank belongs to
## (0 = none); switching targets zeroes the bank.
var _revive_target_peer := 0
## Issue #163 Part 3: the server's revive-channel record for THIS
## node's player (target peer + elapsed), validated like repair's.
## Issue #172: the record's elapsed no longer gates anything —
## each valid tick credits its delta into the TARGET's pool.
var _srv_revive_target := 0
var _srv_revive_t := 0.0
## Issue #172: the revive POOL, living on the TARGET's node and
## owned by the server: seconds credited toward REVIVE_CHANNEL
## by every validated channel record aimed at this player.
## Contributions persist while the target stays downed (a
## reviver dropping out loses nothing); the pool zeroes
## exactly when the target leaves the downed state.
var _srv_revive_pool := 0.0
## Issue #172: the pool fraction as replicated presentation
## state — set by the server (sync_revive_pool) and carried
## onward by the snapshot stream, so the channeling clients
## and the downed player all render ONE pooled bar.
var _revive_pool_frac := 0.0
## Issue #172: pool-fraction sync bookkeeping (server copy).
var _srv_pool_frac_sent := -1.0
var _srv_pool_sync_t := 0.0
## World-space downed marker (Label3D "!"), visible to teammates.
var _downed_marker: Label3D = null
const REVIVE_WINDOW := 30.0
const REVIVE_CHANNEL := 3.0
const REVIVE_RANGE := 3.5

## Issue #113 Phase 3: the Architect's starting tools. Both are granted
## at run start (wrench equipped, hammer bagged) and re-granted into the
## bag whenever a restore finds one missing — disposal is allowed but
## never permanent. Neither grants a basic attack.
const ARCHITECT_TOOL_IDS: Array[String] = ["field_wrench", "forge_hammer"]
const WRENCH_ITEM_ID := "field_wrench"
const HAMMER_ITEM_ID := "forge_hammer"
## Issue #113 Phase 4: Hammer Smash — the forge_hammer's AOE ability
## (placeholders — Jesse's tuning). No melee swing: the hammer's only
## offense is this ability, cast through the ordinary ability system.
const SMASH_RADIUS := 3.5
const SMASH_DAMAGE_MULT := 1.5
const SMASH_STUN_TIME := 1.0
const SMASH_COOLDOWN := 10.0
## Server-side Smash cooldown on this node (the client's ability_cds
## entry is a HUD mirror; this is the validated truth).
var _srv_smash_cd := 0.0
## Issue #170: server-side Chain Lightning cooldown (mage base
## attack CD 0.85 x ~0.7 — an honest War Drums-buffed cadence of
## ~0.77 s must never false-reject; this gates spam, not play).
const LIGHTNING_COOLDOWN := 0.6
var _srv_lightning_cd := 0.0
## Wrench repair channel (placeholders — Jesse's tuning): free, limited
## only by the channel itself. Server ticks on its own timer; clients
## send start/stop intents only.
const REPAIR_REACH := 3.5
const REPAIR_TICK_HP := 25.0
const REPAIR_TICK_TIME := 0.6
## Server-side range slack over REPAIR_REACH: snapshot positions lag a
## frame or two, and a legit channel must not false-refuse.
const REPAIR_SERVER_SLACK := 1.0
## Client channel state (the authority peer's own view).
var _repair_target: Node3D = null
var _repair_sending := false
var _prompt_repair := false
var _near_repairable := false
## Server channel state (the server's copy of this player node).
var _srv_repair_target: Node3D = null
var _srv_repair_t := 0.0
var _srv_repair_anchor := Vector3.ZERO

# --- Run statistics (shown on the death screen) ---
var run_start_msec := 0
var run_kills := 0
var run_damage_dealt := 0.0
var run_death_cause := ""

# --- Class abilities ---
# Unlocked by character level. Mage cycles spells (1-4/Q, cast with click).
# Warrior cycles totems (Q) and places with T. Rogue cycles (Q), uses with F.
var unlocked_abilities: Array = []
var selected_ability := 0
var totem_charges := 0
var ability_cds := {}  # ability id -> cooldown remaining
var eagle_eye_used_wave := -1
## Affinity Families: specialization in one skill, family collections.
var specialization := ""  # skill_id, or "" for none
var affinity := {}  # skill_id -> float (0-100)
var family_collection := {}  # family_id -> {"traits": [trait_ids], "signature": bool}
## Signatures earned IN THIS RUN (family_id -> true), set only when the
## 100-affinity milestone trips during play. Jesse 2026-10-27: the profile
## collection book (family_collection, permanent account meta per issue #4
## Phase 2) must NOT put a specialized skill on the hotbar at a new level —
## the book stays the lifetime record (family panel, Deep Tree branch
## gates), but the usable signature unlock is run-scoped: earn 100 family
## affinity in the current run and it appears; start a new level/run
## without having earned it there and it does not.
var run_signatures := {}
## Issue #206 (Deep Tree): the character's tree seed (stored
## per save; initialized from DeepTree.TREE_SEED, stored
## value wins on apply), owned packed node ids, and the
## NEVER-clamped lifetime affinity counters the insight
## wallets derive from. Aggregates are derived state —
## recomputed by DeepTree.compute_aggregates, never saved.
var tree_seed := DeepTree.TREE_SEED
var tree_owned: Array = []
var tree_lifetime := {}  # skill_id -> float (lifetime, unclamped)
var tree_aggregates := {}
## Server-side monotone record: branch -> last claimed
## lifetime total a validated purchase presented. Rollback
## claims (below the record) reject (spec section 4).
var tree_last_claimed := {}
## Fuel for the Flame (issue #206 behavior): msec deadline
## of the post-Inferno fire-damage window. Timed buff in
## the _buff_mult pattern — a var + a clock check at the
## read sites.
var _tree_fuel_until := 0
## Issue #210 (slice B2): Veilwalker's post-veil damage
## window (msec), From the Dark's veil/step recency
## stamp (msec), and Twin Step's free-recast window.
var _tree_veil_until := 0
var _tree_dark_stamp := 0
var _tree_twin_until := 0
var _tree_twin_armed := false
## Issue #210 (slice B3): Warlord's Tempo — the totem
## placement buff window (msec) and its percent.
var _tree_tempo_until := 0
var _tree_adrenaline_until := 0
var _tree_adrenaline_pct := 0.0
var _tree_tempo_pct := 0.0
var _tree_tempered_until := 0
var _reinforce_strength := 0.5
## Issue #210: Stormcharged's window (10 s after Tempest).
var _tree_storm_until := 0
## Anti-cheese: per-enemy cooldowns for affinity gain.
var _affinity_enemy_cd := {}  # "%s:%d" % [skill_id, enemy_id] -> msec
## Per-cast caps: cast_id -> points granted so far.
var _affinity_cast_total := {}
const FOCUS_MULT := 2.0
const AFFINITY_ENEMY_CD := 5000
## Global tuning: scales all affinity gains. 0.25 = 4x slower than Appendix A
## starting values. Target ~15-20 min focused play to reach 100.
const AFFINITY_RATE := 0.25
## Specialization unlocks at this character level.
const SPECIALIZATION_UNLOCK_LEVEL := 20
## Smoke Veil stealth: mobs can't target you while stealthed.
var stealthed := false
var _stealth_t := 0.0
## Gilded Cage (Warden): rooted inside the dome while > 0.
var _caged_t := 0.0
## Issue #126 Phase 1: rod-out mode. Toggled by the rod key (V) and
## only enterable with the rod EQUIPPED in the TOOL slot (Choice B).
## While out: the FP viewmodel is the rod alone, peers' HeldProp drops
## the weapon, and LMB belongs to the cast (Phase 2). Replicated via
## push_snapshot so peers render it.
var rod_out := false
## Issue #126 Phase 2: client mirrors of the server-owned fishing
## session (set by FishingDirector's fx broadcasts on this peer only).
## _bobber_out: a cast is in the water (waiting / biting / idle after
## an escape). _bite_ready: the hook window is open.
var _bobber_out := false
var _bite_ready := false
## Cast charge state: -1 = not charging; 0..1 while LMB is held.
var _cast_charge := -1.0
## Issue #126 Phase 3: the last probed rod-out legend state (the aim
## probe re-emits click_state_changed only when it flips), and the
## viewmodel rod handle the charge bend drives.
var _rod_legend_cache := ""
var _vm_rod_prop: Node3D = null
## Unseen trait: next attack after veil/blink crits (2x). Set on veil expiry / blink land.
var unseen_crit_ready := false
## Co-op ping: MMB / G drops a "!" marker visible to the whole party.
var _ping_cd := 0.0
const PING_COOLDOWN := 1.5
const PING_RANGE := 30.0
const PING_LIFETIME := 5.0
const PING_MAX := 6
var _pings: Array = []

var _cooldown := 0.0
var _jump_queued := false
var _was_on_floor := true
var _step_timer := 0.0
## Issue #69 Phase 1: Thrown dagger charge. Hold RMB 0→1 over 0.8s.
## LMB while charging throws; releasing RMB cancels silently.
var _dagger_charge := 0.0
## Issue #95 Phase 2: setter emits click_state_changed so the mouse legend
## re-renders live. Only emits on actual change (no per-frame spam).
var _charging := false:
	set(v):
		if _charging == v:
			return
		_charging = v
		click_state_changed.emit()
const DAGGER_CHARGE_TIME := 0.8
const DAGGER_RANGE_MIN := 6.0
const DAGGER_RANGE_MAX := 16.0
const DAGGER_DMG_MIN := 0.6
const DAGGER_DMG_MAX := 1.4
## Issue #69 Phase 2: Dagger-out state. While the dagger is flying (out or
## returning), melee is disabled and Fan of Knives requires dagger in hand.
## 1.2s cooldown after catch before the next throw.
var _dagger_out := false
var _dagger_catch_cd := 0.0
const DAGGER_CATCH_COOLDOWN := 1.2
## Dash: Shift for a quick burst. _dash_t > 0 while dashing (i-frames),
## _dash_cd is the cooldown before the next dash.
var _dash_t := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
const DASH_TIME := 0.18
const DASH_COOLDOWN := 2.0
const DASH_SPEED := 16.0
## Temporary potion buffs: stat -> {"mult": float, "until": float (unix sec)}.
var _buffs := {
	"speed": {"mult": 1.0, "until": 0.0},
	"damage": {"mult": 1.0, "until": 0.0},
	"defense": {"mult": 1.0, "until": 0.0},
}
## Issue #102 Phase 4: wave-counted buffs: stat -> {"mult": float, "waves": int}.
## Granted by items with buff_waves > 0; decremented by on_wave_cleared,
## which the dungeon broadcasts per cleared wave. Mult < 1.0 on "defense"
## reduces damage taken.
var _wave_buffs := {
	"speed": {"mult": 1.0, "waves": 0},
	"damage": {"mult": 1.0, "waves": 0},
	"defense": {"mult": 1.0, "waves": 0},
}
var _buff_announced := {"speed": false, "damage": false}
var _snapshot := 0.0
var _remote_pos := Vector3.ZERO
var _has_remote := false
## Issue #72 Phase 1: remote yaw for snapshot interpolation.
var _remote_yaw := 0.0
var _sprite: AnimatedSprite3D
## Back-sprite integration: front/back frame sets + presentation state.
var _frames_front: SpriteFrames = null
var _frames_back: SpriteFrames = null
var _showing_back := false
var _sprite_base_pos := Vector3.ZERO
var _sprite_base_captured := false
var _yaw := 0.0
var _pitch := 0.0
## Issue #144 Phase 1: latched the first time any joypad event arrives
## this session; the pad leg of gameplay_focused() keys off it.
var _pad_seen := false
var _camera: Camera3D
var _cam_base := Vector3(0, EYE_HEIGHT, 0)
var _shake := 0.0
var _viewmodel: Node3D
## Issue #104 Phase 3: slot name -> equipped item id, derived from the
## inventory markers by _sync_equipped_ids() and REPLICATED to peers via
## push_snapshot (inventory itself never replicates — see issue #105).
## Drives held props (own viewmodel + the third-person prop peers see)
## and the server-side rod validation (FishingDirector cast gate).
var equipped_ids: Dictionary = {}
var _held_prop: Node3D = null
var _vm_base := Vector3(0.32, -0.34, -0.55)
var _vm_base_rot := Vector3(0.15, -0.25, 0.1)
var _cast_seq := 0
var _staff_glow: OmniLight3D
var _staff_crystal_mat: StandardMaterial3D
# Team-visible aura: world-space glow every peer renders. Synced via RPC.
var _aura_light: OmniLight3D
var net_aura_level := 1
var net_bonus_aura := 0.0
## Issue #184 (section 2): the snapshot mirror of the owner's
## ATK SPD investment — replicas (incl. the server's copies of
## guests) read their multiplier from here.
var net_bonus_atk_spd := 0.0
var _bob_t := 0.0
var _prompt_pickup: ItemPickup = null
var _prompt_interact := false
## Jesse 2026-10-11: RTS command mode (warlord domain). When active, the
## player can E-interact with friendly buildings and click/order RTS units
## via camera raycast. Toggled by the Command special ability.
var _command_mode := false
var _command_selected: Array = []
var _command_faction := -1
## Issue #165 (F2): the FPS command aim — the ground point under
## the camera-center aim, refreshed per frame in command mode,
## with its ground marker. Targeting resolves from the aim at
## click time, never from a free cursor (the mouse stays captured).
var _command_aim := Vector3.INF
var _aim_marker: MeshInstance3D = null
## Jesse 2026-10-11: FPS building placement state (B in command mode).
var _placing_type := ""
var _placing_ghost: MeshInstance3D = null
var _placing_valid := false
## Departure-board reading mode (station only, local per client). While set,
## input is modal: cursor raycast votes on the 3D board's rows.
var _reading_board: DepartureBoard = null
var _reading_hover := ""
const READ_HINT := "Aim at a destination and click to vote — E to step away"


func _ready() -> void:
	add_to_group("players")
	run_start_msec = Time.get_ticks_msec()
	class_data = load("res://data/classes/%s.tres" % class_id) as ClassData
	if class_data == null:
		push_error("[Player] Unknown class: %s" % class_id)
		return
	_recalc_stats()
	hp = max_hp
	_sprite = $AnimatedSprite3D
	_build_sprite()
	$Label3D.text = _display_name()
	_remote_pos = global_position
	_give_starter_kit()
	_build_aura_visual()
	_apply_equipped_special()
	_build_health_bar()
	# Push initial aura so the team sees the glow from the start.
	if is_multiplayer_authority() and class_id == "mage":
		_push_aura.call_deferred()
	if class_id == "warrior":
		totem_charges = 1  # start with one totem charge
	if is_multiplayer_authority():
		_sprite.visible = false
		$Label3D.visible = false
		_camera = Camera3D.new()
		_camera.position = _cam_base
		_camera.far = 120.0
		add_child(_camera)
		_camera.current = true
		_build_viewmodel()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_bob_t = randf() * 10.0


func _display_name() -> String:
	if SteamManager.initialized and steam_id != 0:
		return Steam.getFriendPersonaName(steam_id)
	var pid := get_multiplayer_authority()
	if NetworkManager.transport == NetworkManager.Transport.LAN:
		return str(NetworkManager.lan_names.get(pid, "Player %d" % pid))
	return "Player %d" % pid


func _build_sprite() -> void:
	var frames := SpriteFrames.new()
	for tex in class_data.frames:
		frames.add_frame("default", tex)
	frames.set_animation_speed("default", 4.0)
	frames.set_animation_loop("default", true)
	_frames_front = frames
	# Back-sprite integration: a parallel frame set from the class's
	# back-view art (empty for a front-only class -> no swapping).
	_frames_back = null
	if class_data.frames_back.size() > 0:
		var back := SpriteFrames.new()
		for tex in class_data.frames_back:
			back.add_frame("default", tex)
		back.set_animation_speed("default", 4.0)
		back.set_animation_loop("default", true)
		_frames_back = back
	if not _sprite_base_captured:
		_sprite_base_pos = _sprite.position
		_sprite_base_captured = true
	_sprite.frames = _frames_front
	_showing_back = false
	_sprite.position.x = _sprite_base_pos.x
	_sprite.position.z = _sprite_base_pos.z
	_sprite.modulate = class_data.tint
	# Issue #72 Phase 2: billboard disabled in tscn; sprite yaws to facing.
	# NOTE: Do NOT set material_override here — StandardMaterial3D breaks
	# AnimatedSprite3D texture rendering (white quads, issue #78).
	_sprite.play("default")


## Facing direction on the ground plane for the current yaw (the same
## convention the movement code uses: forward = -Z rotated by _yaw).
func _facing_dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


## True when the character's replicated facing points away from a
## viewer at cam_pos, i.e. the viewer sees the character's back. Pure
## math on the synced _yaw — every peer computes the same side for the
## same viewpoint (back-sprite integration, MP consistency rule).
func _is_facing_away(cam_pos: Vector3) -> bool:
	var to_cam := cam_pos - global_position
	to_cam.y = 0.0
	if to_cam.length() < 0.01:
		return _showing_back
	return _facing_dir().dot(to_cam) < 0.0


## Present the front or back frame set. The back plane sits
## BACK_SPRITE_DEPTH_PX sprite-pixels behind the front plane along
## the facing axis (Jesse's depth rule — the pair never co-planar).
func _apply_sprite_side(away: bool) -> void:
	if _sprite == null or _frames_back == null:
		return
	_showing_back = away
	_sprite.frames = _frames_back if away else _frames_front
	_sprite.play("default")
	var shift := Vector3.ZERO
	if away:
		shift = -_facing_dir() * (BACK_SPRITE_DEPTH_PX * _sprite.pixel_size)
	_sprite.position.x = _sprite_base_pos.x + shift.x
	_sprite.position.z = _sprite_base_pos.z + shift.z


## Per-frame presentation update for remote instances: derive the
## visible side from the replicated yaw and the local camera.
func _update_sprite_presentation() -> void:
	if _sprite == null or _frames_back == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var away := _is_facing_away(cam.global_position)
	if away != _showing_back:
		_apply_sprite_side(away)


func _give_starter_kit() -> void:
	if not class_data.starting_weapon.is_empty():
		var item := ItemDB.get_item(class_data.starting_weapon)
		if item != null:
			# Issue #104 Phase 1 (Co-founder amendment): a brand-new
			# character's starting weapon starts EQUIPPED — under
			# equip-only recalc, an unequipped starter would leave every
			# new player powerless until they opened the panel.
			var marker := ItemData.slot_name(item.slot) if ItemData.is_gear(item) else ""
			inventory.append({"item": item, "count": 1, "equipped_slot": marker})
			_recalc_stats()
			hp = max_hp
	# Issue #113 Phase 3: a brand-new architect also starts with BOTH
	# tools — the wrench equipped (builder identity first), the hammer
	# in the bag, swappable through the ordinary equip action.
	if class_id == "architect":
		ensure_architect_tools(true)
		hp = max_hp


## Issue #113 Phase 3: guarantee both architect tools are in the
## inventory. Missing tools are appended to the bag (unequipped);
## existing stacks are never duplicated or re-marked. With
## equip_wrench, the wrench takes the WEAPON slot (any other weapon's
## marker is cleared — the ordinary one-per-slot swap). Called at run
## start for new architects and from apply_state for restores, which is
## what re-grants disposed tools and migrates legacy architect saves.
func ensure_architect_tools(equip_wrench: bool = false) -> void:
	if class_id != "architect":
		return
	var wrench_entry: Dictionary = {}
	for entry in inventory:
		var it := entry.get("item") as ItemData
		if it != null and it.id == WRENCH_ITEM_ID:
			wrench_entry = entry
	for tool_id in ARCHITECT_TOOL_IDS:
		var found := false
		for entry in inventory:
			var it := entry.get("item") as ItemData
			if it != null and it.id == tool_id:
				found = true
				break
		if not found:
			var item := ItemDB.get_item(tool_id)
			if item != null:
				var e := {"item": item, "count": 1, "equipped_slot": ""}
				inventory.append(e)
				if tool_id == WRENCH_ITEM_ID:
					wrench_entry = e
	if equip_wrench and not wrench_entry.is_empty():
		for entry in inventory:
			if entry != wrench_entry and _entry_equipped_slot(entry) == "WEAPON":
				entry["equipped_slot"] = ""
		wrench_entry["equipped_slot"] = "WEAPON"
	_recalc_stats()


## True when the Field Wrench is the equipped WEAPON. Reads the
## replicated equipped_ids, so the server can validate repair channels
## for remote peers (inventory itself never replicates — issue #105).
func has_wrench_equipped() -> bool:
	return str(equipped_ids.get("WEAPON", "")) == WRENCH_ITEM_ID


## True when the Forge Hammer is the equipped WEAPON (same replicated
## source as has_wrench_equipped — the Smash gate reads this).
func has_hammer_equipped() -> bool:
	return str(equipped_ids.get("WEAPON", "")) == HAMMER_ITEM_ID


func _recalc_stats() -> void:
	if class_data == null:
		return
	var dmg_m := 1.0
	var hp_m := 1.0
	var spd_m := 1.0
	xp_mult = 1.0
	max_hp = class_data.base_health + float(level - 1) * 15.0 + bonus_health + _tree_stat("health")
	damage = class_data.base_damage + float(level - 1) * 2.0 + bonus_damage + _tree_stat("damage")
	move_speed = class_data.base_move_speed + bonus_speed + _tree_stat("speed")
	attack_cooldown = class_data.base_attack_cooldown
	attack_range = class_data.base_attack_range
	for entry in inventory:
		# Issue #104 Phase 1: ONLY equipped stacks grant stats. Bag stacks
		# are inert (Jesse's equip-only decision); per-copy math below is
		# unchanged for the stacks that do count.
		if _entry_equipped_slot(entry) == "":
			continue
		var item := entry["item"] as ItemData
		var count := int(entry["count"])
		max_hp += item.health_bonus * count
		damage += item.damage_bonus * count
		# Issue #113 Phase 1: the equipped WEAPON stack's upgrade level
		# adds flat damage — per stack, once (a stack of five +3 swords
		# is one +3 weapon read, not five).
		if _entry_equipped_slot(entry) == "WEAPON":
			damage += UPGRADE_DAMAGE_PER_LEVEL * float(int(entry.get("upgrade_level", 0)))
		move_speed += item.speed_bonus * count
		dmg_m *= pow(item.damage_mult, count)
		hp_m *= pow(item.health_mult, count)
		spd_m *= pow(item.speed_mult, count)
		xp_mult *= pow(item.xp_mult, count)
	max_hp *= hp_m
	# Apex relic (issue #5): equipped Boar Hide scales max HP.
	max_hp *= special_hp_mult
	damage *= dmg_m
	move_speed *= spd_m
	# Issue #210 slice B5 (spec section 3): the tree xp
	# layer — base x item x tree; the section 1.5 envelope
	# does not clamp xp (not a combat channel).
	xp_mult *= 1.0 + _tree_skill_mod("xp", "xp_pct", 0.0)
	# Milestone passives: 25/50/75/100.
	var ms := milestone_mult()
	damage *= ms
	max_hp *= ms
	hp = minf(hp, max_hp)
	_sync_equipped_ids()


# --- Equipment (issue #104 Phase 1) -------------------------------------
## Items never leave the inventory: each stack dict carries an
## "equipped_slot" marker ("" = in the bag, inert). Invariants: at most
## one stack per slot; a stack equips only into its own ItemData.slot;
## picking up more copies of an equipped item grows the equipped stack;
## new pickups NEVER auto-equip (old-save migration and the new-character
## starting weapon are the only exceptions).

## Slot name a stack is equipped into ("" = not equipped). Entries built
## before this system may lack the key — missing means unequipped.
func _entry_equipped_slot(entry: Dictionary) -> String:
	return str(entry.get("equipped_slot", ""))


## The inventory entry currently equipped in the given slot, or {}.
func equipped_entry(slot_name_str: String) -> Dictionary:
	if slot_name_str == "":
		return {}
	for entry in inventory:
		if _entry_equipped_slot(entry) == slot_name_str:
			return entry
	return {}


## Item equipped in the given slot, or null.
func equipped_item(slot_name_str: String) -> ItemData:
	var e := equipped_entry(slot_name_str)
	if e.is_empty():
		return null
	return e.get("item") as ItemData


## Rebuild equipped_ids from the inventory markers; on change, refresh
## the held props. Called from _recalc_stats, so every equip/unequip /
## restore path stays in sync without its own bookkeeping.
func _sync_equipped_ids() -> void:
	var ids: Dictionary = {}
	for entry in inventory:
		var s := _entry_equipped_slot(entry)
		if s != "":
			var it := entry.get("item") as ItemData
			if it != null:
				ids[s] = str(it.id)
	if ids != equipped_ids:
		equipped_ids = ids
		# Issue #126 Phase 1: rod-out cannot outlive the equipped rod —
		# any equip change that takes the rod out of TOOL ends the mode
		# before the held props refresh into it. Phase 2: a bobber in
		# the water is reeled in with it (the fisher's own peer only —
		# replicas have no session to end).
		if rod_out and str(ids.get("TOOL", "")) != "fishing_rod":
			rod_out = false
			if is_multiplayer_authority() and _bobber_out:
				_director_request("request_reel_in")
		_refresh_held_props()


## Item id equipped in the TOOL slot ("" = none).
func equipped_tool_id() -> String:
	return str(equipped_ids.get("TOOL", ""))


## Issue #104 Phase 3: the fishing gate key. Issue #126 Phase 1: the
## spots no longer gate on it — it is now the rod-out mode key.
func has_rod_equipped() -> bool:
	return equipped_tool_id() == "fishing_rod"


## Issue #126 Phase 1: owns a fishing rod anywhere in the inventory
## (equipped or bagged). Drives the rod-key toast choice.
func _owns_fishing_rod() -> bool:
	for entry in inventory:
		var it := entry.get("item") as ItemData
		if it != null and it.id == "fishing_rod":
			return true
	return false


## Issue #126 Phase 1: the rod key. With the rod equipped, toggles
## rod-out mode. Without it, the ONLY rod messaging in the game: a
## toast on the player's own key press (never a world refusal) —
## equip hint when owned, merchant hint when not.
## Phase 2: leaving rod-out with a bobber in the water reels it in
## (the session ends free on the server).
func _toggle_rod_out() -> void:
	if has_rod_equipped():
		rod_out = not rod_out
		if not rod_out:
			_cancel_cast_charge()
			if _bobber_out:
				_director_request("request_reel_in")
		_refresh_held_props()
	elif _owns_fishing_rod():
		if hud != null:
			hud.toast("Equip your Fishing Rod (Tool slot) to cast")
	else:
		if hud != null:
			hud.toast("The dock merchant sells a Fishing Rod")


## Issue #126 Phase 2: the dungeon's FishingDirector (session owner).
func _fishing_director() -> Node:
	var ds := get_tree().get_nodes_in_group("fishing_director")
	if ds.is_empty():
		return null
	return ds[0]


## Route a fishing request to the server's director (direct call when
## hosting — the spot flow's pattern).
func _director_request(method: String, arg: Variant = null) -> void:
	var d := _fishing_director()
	if d == null:
		return
	if multiplayer.is_server():
		if arg == null:
			d.call(method)
		else:
			d.call(method, arg)
	else:
		if arg == null:
			d.rpc_id(NetworkManager.server_peer_id, method)
		else:
			d.rpc_id(NetworkManager.server_peer_id, method, arg)


## Director fx mirror setters (called locally on the fisher's peer).
func set_bobber_out(v: bool) -> void:
	if _bobber_out == v:
		return
	_bobber_out = v
	if not v:
		_bite_ready = false
	# Issue #126 Phase 3: the rod-out legend contexts follow the
	# session mirrors — flip the legend the moment they change.
	click_state_changed.emit()


func set_bite_ready(v: bool) -> void:
	if _bite_ready == v:
		return
	_bite_ready = v
	click_state_changed.emit()


## The cast landing point: flat camera aim at the charged distance
## (the FishingController prototype's model, productionized).
func _cast_landing(charge: float) -> Vector3:
	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var dist := lerpf(4.0, 15.0, charge)
	return global_position + fwd * dist


func _begin_cast_charge() -> void:
	_cast_charge = 0.0
	if hud != null and hud.has_method("set_charge_meter"):
		hud.set_charge_meter(0.0, true)


func _release_cast() -> void:
	var charge := _cast_charge
	_cast_charge = -1.0
	_apply_rod_bend()
	if hud != null and hud.has_method("set_charge_meter"):
		hud.set_charge_meter(0.0, false)
	var landing := _cast_landing(charge)
	# Client splash prediction with the shared validation; the
	# director's fx_cast broadcast reconciles it.
	var d := _fishing_director()
	if d != null and d.has_method("predict_cast"):
		var from := global_position + Vector3(0, 1.4, 0) \
			+ (-global_transform.basis.z) * 0.4
		d.predict_cast(int(multiplayer.get_unique_id()), from, landing)
	_director_request("request_cast", landing)


func _cancel_cast_charge() -> void:
	_cast_charge = -1.0
	_apply_rod_bend()
	if hud != null and hud.has_method("set_charge_meter"):
		hud.set_charge_meter(0.0, false)


## Issue #126 Phase 3: the rod-bend charge tell — the viewmodel rod
## flexes as the charge builds (the pole leans further from its rest
## angle and the whole prop pitches), and springs straight when the
## charge ends. Charge 0 = the P1 rest framing, exactly.
func _apply_rod_bend() -> void:
	if _vm_rod_prop == null or not is_instance_valid(_vm_rod_prop):
		return
	var c := clampf(_cast_charge, 0.0, 1.0)
	_vm_rod_prop.rotation.x = 0.45 + 0.25 * c
	if _vm_rod_prop.get_child_count() > 0:
		var pole := _vm_rod_prop.get_child(0) as Node3D
		if pole != null:
			pole.rotation.z = -0.5 - 0.45 * c


## True when the item may be equipped by this player's class. The class
## restriction is equip-time only: anyone may carry anything.
func _class_may_equip(item: ItemData) -> bool:
	return item.allowed_classes.is_empty() or item.allowed_classes.has(class_id)


## Equip the stack at index into its own slot, moving the marker off any
## stack currently holding that slot (swap). Refuses non-gear and
## class-restricted stacks regardless of caller. Returns true on success.
func equip_stack(index: int) -> bool:
	if not is_multiplayer_authority():
		return false
	if index < 0 or index >= inventory.size():
		return false
	var entry: Dictionary = inventory[index]
	var item := entry.get("item") as ItemData
	if item == null or not ItemData.is_gear(item):
		if hud != null:
			hud.toast("That item can't be equipped.")
		return false
	if not _class_may_equip(item):
		if hud != null:
			hud.toast("Your class can't equip that.")
		return false
	var target := ItemData.slot_name(item.slot)
	if _entry_equipped_slot(entry) == target:
		return true
	for i in inventory.size():
		if i != index and _entry_equipped_slot(inventory[i]) == target:
			inventory[i]["equipped_slot"] = ""
	entry["equipped_slot"] = target
	_recalc_stats()
	health_changed.emit(hp, max_hp)
	if hud != null:
		hud.refresh_inventory(self)
		hud.refresh_loadout(self)
	# Issue #177: teach the rod's V toggle at the moment of
	# equipping — the rod readies on V, not on equip.
	if item.id == "fishing_rod" and target == "TOOL" and not rod_out:
		if hud != null:
			hud.toast("Press {toggle_rod} to ready your rod")
	return true


## Remove the equip marker from the stack at index. Returns true when a
## marker was actually cleared.
func unequip_stack(index: int) -> bool:
	if not is_multiplayer_authority():
		return false
	if index < 0 or index >= inventory.size():
		return false
	var entry: Dictionary = inventory[index]
	if _entry_equipped_slot(entry) == "":
		return false
	entry["equipped_slot"] = ""
	_recalc_stats()
	health_changed.emit(hp, max_hp)
	if hud != null:
		hud.refresh_inventory(self)
		hud.refresh_loadout(self)
	return true


## Old-save migration (issue #104 Phase 1): saves with no equip markers
## auto-equip the highest-power stack per slot so a resumed player is
## not powerless under equip-only recalc. Score = ItemData.stack_power_score
## (what the whole stack grants: flat bonuses x count + compounded mult
## deviation from 1.0); ties keep inventory order. Zero-score stacks are
## skipped: equipping them would grant nothing.
func _migrate_auto_equip() -> void:
	for slot_idx in [ItemData.Slot.WEAPON, ItemData.Slot.ARMOR, ItemData.Slot.TRINKET, ItemData.Slot.TOOL]:
		var slot_str := ItemData.slot_name(slot_idx)
		var best: Dictionary = {}
		var best_score := 0.0
		for entry in inventory:
			var item := entry.get("item") as ItemData
			if item == null or not ItemData.is_gear(item):
				continue
			if ItemData.slot_name(item.slot) != slot_str:
				continue
			if not _class_may_equip(item):
				continue
			var score := ItemData.stack_power_score(item, int(entry.get("count", 1)))
			if score > best_score:
				best_score = score
				best = entry
		if not best.is_empty():
			best["equipped_slot"] = slot_str


## Class switch (issue #104 Phase 1): stacks the new class may not equip
## come off; carrying them stays legal. Returns the removed item names.
func _unequip_class_restricted() -> Array:
	var removed: Array = []
	for entry in inventory:
		if _entry_equipped_slot(entry) == "":
			continue
		var item := entry.get("item") as ItemData
		if item != null and not _class_may_equip(item):
			entry["equipped_slot"] = ""
			removed.append(item.display_name)
	return removed


## Milestone bonuses: +10% at 25, +10% at 50, +15% at 75, +25% at 100.
func milestone_mult() -> float:
	var m := 1.0
	if level >= 25:
		m *= 1.10
	if level >= 50:
		m *= 1.10
	if level >= 75:
		m *= 1.15
	if level >= 100:
		m *= 1.25
	return m


func milestone_tier() -> int:
	if level >= 100:
		return 4
	if level >= 75:
		return 3
	if level >= 50:
		return 2
	if level >= 25:
		return 1
	return 0


# --- First-person viewmodels ---

func _build_viewmodel() -> void:
	_viewmodel = Node3D.new()
	_viewmodel.position = _vm_base
	_viewmodel.rotation = _vm_base_rot
	_camera.add_child(_viewmodel)
	_refresh_viewmodel()


## Issue #104 Phase 3: the viewmodel shows the EQUIPPED weapon's
## world_model when it has one, else the class default. Issue #177:
## the fishing rod appears ONLY in rod-out mode (the early branch
## below owns that case) — rod prop iff rod_out, weapon prop iff
## not (at fishing spots the #102 session visual takes over the
## cast itself).
func _refresh_viewmodel() -> void:
	if _viewmodel == null:
		return
	for c in _viewmodel.get_children():
		_viewmodel.remove_child(c)
		c.free()
	# Issue #126 Phase 1: in rod-out mode the rod alone fills the
	# viewmodel, reusing the #104 Phase 3 side framing (the weapon
	# stays sheathed).
	if rod_out and equipped_tool_id() == "fishing_rod":
		var rod_out_prop := FishingVisual.build_rod_prop()
		rod_out_prop.name = "RodProp"
		rod_out_prop.position = Vector3(-0.3, -0.24, -0.1)
		rod_out_prop.rotation = Vector3(0.45, 0.0, 0.3)
		_viewmodel.add_child(rod_out_prop)
		_vm_rod_prop = rod_out_prop # Issue #126 P3: charge-bend handle
		_apply_rod_bend()
		return
	_vm_rod_prop = null
	var wid := str(equipped_ids.get("WEAPON", ""))
	var witem: ItemData = ItemDB.get_item(wid) if wid != "" else null
	if witem != null and witem.world_model != "" and ResourceLoader.exists(witem.world_model):
		if wid == "storm_caller":
			# Staff-formed (GLB measured 2.35m tall, bottom at y=-0.99):
			# the staff frame keeps the crystal in view; the generic
			# sword frame crops it out of the top of the screen.
			_vm_model(witem.world_model, 0.45, 0.99, Vector3(0, -0.38, 0))
		else:
			_vm_model(witem.world_model, 0.55, 0.37, Vector3(0, -0.12, 0))
	elif witem != null and WeaponVisual.has_fallback(wid):
		# Issue #113 Phase 2: procedural fallback until the real asset
		# lands. Framing mirrors the matching KayKit class weapon: the
		# storm caller is staff-formed (long — the _build_staff frame
		# keeps its orb in view); the void blade uses the sword frame.
		var holder := Node3D.new()
		var prop := WeaponVisual.build_fallback(wid)
		if wid == "storm_caller":
			holder.position = Vector3(0, -0.25, 0)
			prop.scale = Vector3.ONE * 0.45
			prop.position.y = 0.1
		else:
			holder.position = Vector3(0, -0.12, 0)
			prop.scale = Vector3.ONE * 0.55
			prop.position.y = 0.2
		holder.add_child(prop)
		_viewmodel.add_child(holder)
	else:
		match class_id:
			"mage":
				_build_staff()
			"rogue":
				_build_dagger()
			_:
				_build_sword()
	# Issue #177: no rod tail here — this point is reachable only
	# when NOT rod_out (the early branch returned), and the
	# invariant is no rod prop exists then.


## Own viewmodel + the third-person held prop peers see. The TP prop is
## hidden for the authority player (their viewmodel covers first
## person); replicas show the equipped weapon's world_model and the
## rod, driven entirely by the synced equipped_ids.
func _refresh_held_props() -> void:
	_refresh_viewmodel()
	if _held_prop == null:
		_held_prop = Node3D.new()
		_held_prop.name = "HeldProp"
		_held_prop.position = Vector3(0.38, 1.32, 0.1)
		add_child(_held_prop)
	for c in _held_prop.get_children():
		_held_prop.remove_child(c)
		c.free()
	_held_prop.visible = not is_multiplayer_authority()
	var wid := str(equipped_ids.get("WEAPON", ""))
	var witem: ItemData = ItemDB.get_item(wid) if wid != "" else null
	# Issue #126 Phase 1: in rod-out mode peers see the rod alone —
	# the weapon prop is suppressed until the mode ends.
	if not rod_out and witem != null and witem.world_model != "" and ResourceLoader.exists(witem.world_model):
		var packed := load(witem.world_model) as PackedScene
		if packed != null:
			var inst := packed.instantiate() as Node3D
			inst.name = "WeaponProp"
			# World models are pickup-scale (~1.8m for a sword): shrink
			# and hang the prop at the carrier's side, handle at hand
			# height, instead of towering at native size.
			inst.scale = Vector3.ONE * 0.6
			inst.position = Vector3(0.05, -0.55, 0.05)
			inst.rotation_degrees = Vector3(0, 0, -14)
			_held_prop.add_child(inst)
	elif not rod_out and witem != null and WeaponVisual.has_fallback(wid):
		# Issue #113 Phase 2: procedural fallback (see _refresh_viewmodel).
		var prop := WeaponVisual.build_fallback(wid)
		prop.name = "WeaponProp"
		prop.scale = Vector3.ONE * 0.6
		prop.position = Vector3(0.05, -0.55, 0.05)
		prop.rotation_degrees = Vector3(0, 0, -14)
		_held_prop.add_child(prop)
	# Issue #177: the rod is this builder's only rod source and it
	# is gated on rod_out like the weapon branches above — rod
	# alone when out, weapon alone when in.
	if rod_out and equipped_tool_id() == "fishing_rod":
		var rod := FishingVisual.build_rod_prop()
		rod.name = "RodProp"
		rod.position = Vector3(0.0, -0.15, 0.3)
		rod.rotation = Vector3(0.9, 0.0, 0.15)
		_held_prop.add_child(rod)


func _vm_model(path: String, model_scale: float, y_off: float, holder_pos: Vector3) -> Node3D:
	var packed := load(path) as PackedScene
	var holder := Node3D.new()
	holder.position = holder_pos
	if packed != null:
		var inst := packed.instantiate() as Node3D
		inst.scale = Vector3.ONE * model_scale
		inst.position.y = y_off * model_scale
		holder.add_child(inst)
	_viewmodel.add_child(holder)
	return holder


func _build_sword() -> void:
	# KayKit sword_1handed: 1.78m tall, handle bottom at y=-0.37 in model space.
	_vm_model("res://assets/models/kaykit/weapons/sword_1handed.gltf", 0.55, 0.37, Vector3(0, -0.12, 0))


func _build_dagger() -> void:
	# KayKit dagger: 1.2m tall, handle bottom at y=-0.225 in model space.
	_vm_model("res://assets/models/kaykit/weapons/dagger.gltf", 0.5, 0.225, Vector3(0, -0.08, 0))


func _build_staff() -> void:
	# KayKit staff: 2.15m tall, bottom at y=-0.9 in model space.
	var holder := _vm_model("res://assets/models/kaykit/weapons/staff.gltf", 0.5, 0.9, Vector3(0, -0.25, 0))
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.55, 0.2)
	glow.light_energy = 0.5
	glow.omni_range = 3.5
	glow.position = Vector3(0, 0.8, 0)
	holder.add_child(glow)
	# Arcane crystal: grows brighter with mage level.
	var crystal := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.09
	cm.height = 0.18
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(1.0, 0.6, 0.2)
	cmat.emission_enabled = true
	cmat.emission = Color(1.0, 0.5, 0.15)
	cmat.emission_energy_multiplier = 2.0
	cm.material = cmat
	crystal.mesh = cm
	crystal.position = Vector3(0, 0.82, 0)
	holder.add_child(crystal)
	_staff_glow = glow
	_staff_crystal_mat = cmat
	_update_staff_glow()


## Mage staff brightens with level and aura investment: light energy and
## crystal emission scale. Each aura point is +50% brightness.
func _update_staff_glow() -> void:
	if _staff_glow == null:
		return
	var f := _aura_factor()
	_staff_glow.light_energy = 0.5 * f
	_staff_glow.omni_range = 3.5 + float(level) * 0.15 + (bonus_aura + _tree_stat("aura")) * 0.5
	if _staff_crystal_mat != null:
		_staff_crystal_mat.emission_energy_multiplier = 2.0 * f


## Shared aura brightness factor (level + invested aura points).
func _aura_factor() -> float:
	return 1.0 + float(maxi(0, level - 1)) * 0.25 + (bonus_aura + _tree_stat("aura")) * 0.5


## Team-visible aura: a world-space light every peer renders, so the
## whole party can see how much aura a mage has invested.
func _build_aura_visual() -> void:
	_clear_aura_visual()
	if class_id != "mage":
		return
	_aura_light = OmniLight3D.new()
	_aura_light.position = Vector3(0, 1.2, 0)
	_aura_light.light_color = Color(0.5, 0.8, 1.0)
	_aura_light.shadow_enabled = false
	add_child(_aura_light)
	_update_aura_visual()


func _clear_aura_visual() -> void:
	if _aura_light != null and is_instance_valid(_aura_light):
		_aura_light.queue_free()
	_aura_light = null


## Refresh the world-space aura from the synced (level, aura) values.
func _update_aura_visual() -> void:
	if _aura_light == null:
		return
	var f := 1.0 + float(maxi(0, net_aura_level - 1)) * 0.25 + net_bonus_aura * 0.5
	_aura_light.light_energy = 0.6 * f
	_aura_light.omni_range = 4.0 + net_bonus_aura * 1.0


## Broadcast aura changes so every peer sees the team glow.
@rpc("any_peer", "call_local")
func sync_aura(p_level: int, p_aura: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	net_aura_level = p_level
	net_bonus_aura = p_aura
	_update_aura_visual()


func _push_aura() -> void:
	if not is_multiplayer_authority():
		return
	net_aura_level = level
	# Issue #206: the combined aura (base + tree) rides the
	# sync channel, like the snapshot's combined atk_spd.
	net_bonus_aura = bonus_aura + _tree_stat("aura")
	_update_aura_visual()
	rpc("sync_aura", level, bonus_aura + _tree_stat("aura"))


# --- Deep Tree (issue #206) ---

## One aggregate value, read-safe before the first
## recompute (empty aggregates read as zero everywhere).
func _tree_stat(key: String) -> float:
	if tree_aggregates.is_empty():
		return 0.0
	return float((tree_aggregates.get("stat_adds", {})
		as Dictionary).get(key, 0.0))


func _tree_skill_mod(skill_id: String, key: String,
		default_value: float) -> float:
	if tree_aggregates.is_empty():
		return default_value
	var mods: Dictionary = tree_aggregates.get("skill_mods",
		{})
	if not mods.has(skill_id):
		return default_value
	return float((mods[skill_id] as Dictionary).get(key,
		default_value))


func _recompute_tree_aggregates() -> void:
	tree_aggregates = DeepTree.compute_aggregates(tree_seed,
		class_id, tree_owned)


## Public read for effect scripts (spec section 5): the
## caster's radius_add for a skill, fetched by the effects
## through get_player_node(owner_peer) at the effect site.
func tree_radius_add(skill_id: String) -> float:
	return _tree_skill_mod(skill_id, "radius_add", 0.0)


## The fire-damage multiplier the three fire cast sites
## fold in beside trait_damage_mult (spec section 5): the
## skill's aggregate dmg_mult, with the two authored
## behaviors multiplying under their conditions.
func _tree_fire_mult(skill_id: String) -> float:
	var m := _tree_skill_mod(skill_id, "dmg_mult", 1.0)
	if tree_aggregates.is_empty():
		return m
	var beh: Dictionary = tree_aggregates.get("behaviors", {})
	if beh.has("emberheart") and hp < max_hp * 0.35:
		m *= 1.0 + float(beh["emberheart"]) / 100.0
	if beh.has("fuel_for_the_flame") \
			and Time.get_ticks_msec() < _tree_fuel_until:
		m *= 1.0 + float(beh["fuel_for_the_flame"]) / 100.0
	return m


func _tree_variant(skill_id: String) -> String:
	if tree_aggregates.is_empty():
		return ""
	return str((tree_aggregates.get("variants", {})
		as Dictionary).get(skill_id, ""))


## Issue #210: the plain aggregate damage multiplier for a
## skill (echoes + the skill's own dmg_pct nodes) — the
## frost/storm cast expressions fold this beside
## trait_damage_mult, closing the prototype's unwired-echo
## disclosure for frost/blizzard/lightning/barrage.
func _tree_mult(skill_id: String) -> float:
	return _tree_skill_mod(skill_id, "dmg_mult", 1.0)


func _tree_behavior_pct(behavior_id: String) -> float:
	if tree_aggregates.is_empty():
		return 0.0
	return float((tree_aggregates.get("behaviors", {})
		as Dictionary).get(behavior_id, 0.0))


## Frost's cast multiplier: the aggregate dmg_mult with
## Permafrost Heart multiplying while the caster is above
## 75% health (Emberheart's high-HP mirror). Shatterglass
## is target-conditioned and reads at the hit sites.
func _tree_frost_mult(skill_id: String) -> float:
	var m := _tree_mult(skill_id)
	var pct := _tree_behavior_pct("permafrost_heart")
	if pct > 0.0 and hp > max_hp * 0.75:
		m *= 1.0 + pct / 100.0
	return m


## Issue #210 Amendment 1: the caster's Arcing Brand amp
## for a skill. Public: the Fireball explode loop reads
## the barrage amp via the caster.
## Issue #210 (Veilwalker): the damage multiplier of the
## post-veil window — 1.0 outside it or unowned.
func _tree_veil_mult() -> float:
	if Time.get_ticks_msec() < _tree_veil_until:
		var p := _tree_behavior_pct("veilwalker")
		if p > 0.0:
			return 1.0 + p / 100.0
	return 1.0


## Issue #210 (slice B3): the Totem's reads of its
## caster's tree — the public wrappers in the
## tree_brand_amp pattern.
func tree_totem_mod(skill_id: String, key: String,
		default: float) -> float:
	return _tree_skill_mod(skill_id, key, default)


func tree_totem_behavior(behavior_id: String) -> float:
	return _tree_behavior_pct(behavior_id)


func tree_totem_variant(skill_id: String) -> String:
	return _tree_variant(skill_id)


## Issue #210 (slice B4): public structure reads for
## Structure/Dungeon, same wrapper pattern.
func tree_structure_mod(skill_id: String, key: String,
		default: float) -> float:
	return _tree_skill_mod(skill_id, key, default)


func tree_structure_behavior(behavior_id: String) -> float:
	return _tree_behavior_pct(behavior_id)


func tree_structure_variant(skill_id: String) -> String:
	return _tree_variant(skill_id)


## Issue #210 (slice B4, Aegis Shell): true while this
## player's Reinforce shell holds and the variant is
## owned — read at the forge damage sites.
func tree_aegis_active() -> bool:
	return _reinforce_t > 0.0 and _tree_variant("reinforce") \
		== "aegis_shell"


## Issue #210 (slice B4, Salvage): a structure of this
## player's was destroyed server-side — refund the
## behavior's percent of its placement cooldown.
func apply_tree_salvage(structure_id: String) -> void:
	var pct := _tree_behavior_pct("salvage")
	if pct <= 0.0:
		return
	var base := {"sentry_turret": 12.0, "bulwark_wall": 8.0,
		"spike_trap": 10.0, "keystone": 30.0}
	if not base.has(structure_id):
		return
	var cur := float(ability_cds.get(structure_id, 0.0))
	if cur > 0.0:
		ability_cds[structure_id] = maxf(0.0,
			cur - float(base[structure_id]) * pct / 100.0)


## Issue #210 slice B5 (Amendment 1 section C.1): the
## caster's burn fraction for a skill (fireball / meteor).
func tree_burn_pct(skill_id: String) -> float:
	return _tree_skill_mod(skill_id, "burn_pct", 0.0)


## Issue #210 slice B5 (spec section 3): Wayfarer's Edge
## governance for the basic-attack variant slot.
## Public variant check for cross-object readers.
func tree_variant_is(skill_id: String, vid: String) -> bool:
	return _tree_variant(skill_id) == vid


func tree_wayfarers_edge() -> bool:
	return _tree_variant("basic_attack") == "wayfarers_edge"


func tree_brand_amp(skill_id: String) -> float:
	return _tree_skill_mod(skill_id, "brand_amp", 0.0)


## Shatterglass (issue #210): frost damage against a
## slowed or frozen target (the #173 status system's own
## state — mob.is_slowed covers the frozen 0.0-mult case).
## Public: the FrostShard hit site reads it via the caster.
func tree_shatterglass_mult(mob: Variant) -> float:
	var pct := _tree_behavior_pct("shatterglass")
	if pct <= 0.0 or mob == null:
		return 1.0
	if bool(mob.call("is_slowed")):
		return 1.0 + pct / 100.0
	return 1.0


## Owner-side purchase entry (spec sections 4/8): local
## validation first, then the single server-validated claim
## path. Returns true when the claim was SENT (or applied
## host-locally); acceptance itself arrives via
## tree_sync_player.
func try_purchase(node_id: int) -> bool:
	var branch := DeepTree.id_branch(node_id)
	var node := DeepTree.node_for(tree_seed, class_id, branch,
		DeepTree.id_ring(node_id), DeepTree.id_index(node_id))
	if node.is_empty() or bool(node.get("inert", false)):
		return false
	if not DeepTree.branch_unlocked(family_collection,
			class_id, branch, tree_lifetime, level):
		return false
	if tree_owned.has(node_id):
		return false
	if not DeepTree.prereq_met(tree_seed, class_id, node_id,
			tree_owned):
		return false
	if DeepTree.wallet_of(tree_seed, class_id, tree_lifetime,
			tree_owned, branch) < int(node["cost"]):
		return false
	var claimed := int(DeepTree.lifetime_total(tree_lifetime,
		class_id, branch))
	if _tree_is_server():
		# Host: direct call (the standard host-routing
		# pattern); the accept broadcasts the sync, whose
		# call_local leg applies on this copy the same way
		# as every replica (the validator already recorded
		# it; the sync re-application is idempotent).
		var reason := _tree_validate_claim(node_id, claimed,
			get_multiplayer_authority())
		if reason != "":
			return false
		if multiplayer.has_multiplayer_peer():
			rpc("tree_sync_player",
				get_multiplayer_authority(), tree_owned,
				tree_aggregates)
		return true
	# Guest: claim to the server's copy of this node.
	rpc_id(NetworkManager.server_peer_id,
		"tree_claim_purchase", node_id, claimed)
	return true


func _tree_is_server() -> bool:
	return not multiplayer.has_multiplayer_peer() \
		or multiplayer.is_server()


## The regeneration validator (spec section 4.2) — pure
## enough to drive process-locally in tests: it consults
## only this copy's state (which, on the server, is the
## ledger). Returns "" on accept, else the reject reason.
## On accept it RECORDS the purchase on this copy; the
## caller broadcasts the sync.
func _tree_validate_claim(node_id: int,
		claimed_lifetime: int, claimant_peer: int) -> String:
	if claimant_peer != get_multiplayer_authority():
		return "not_owner"
	var branch := DeepTree.id_branch(node_id)
	var node := DeepTree.node_for(tree_seed, class_id, branch,
		DeepTree.id_ring(node_id), DeepTree.id_index(node_id))
	if node.is_empty() or bool(node.get("inert", false)):
		return "inert"
	if not DeepTree.branch_unlocked(family_collection,
			class_id, branch, tree_lifetime, level):
		return "locked"
	if tree_owned.has(node_id):
		return "duplicate"
	if not DeepTree.prereq_met(tree_seed, class_id, node_id,
			tree_owned):
		return "prereq"
	if claimed_lifetime < int(tree_last_claimed.get(branch,
			0)):
		return "rollback"
	var spent := DeepTree.spent_total(tree_seed, class_id,
		tree_owned, branch)
	if claimed_lifetime - spent < int(node["cost"]):
		return "insufficient"
	tree_owned.append(node_id)
	tree_last_claimed[branch] = claimed_lifetime
	_recompute_tree_aggregates()
	return ""


@rpc("any_peer", "call_remote", "reliable")
func tree_claim_purchase(node_id: int,
		claimed_lifetime: int) -> void:
	if not _tree_is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var reason := _tree_validate_claim(node_id,
		claimed_lifetime, sender)
	if reason == "":
		rpc("tree_sync_player", get_multiplayer_authority(),
			tree_owned, tree_aggregates)
	else:
		rpc_id(sender, "tree_purchase_denied", node_id, reason)


@rpc("any_peer", "call_local", "reliable")
func tree_sync_player(peer_id: int, owned: Array,
		aggregates: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_peer_id:
		return # only the server originates syncs
	if peer_id != get_multiplayer_authority():
		return
	tree_owned = []
	for id in owned:
		tree_owned.append(int(id))
	tree_aggregates = aggregates.duplicate(true)
	_recalc_stats()
	_push_aura()


@rpc("any_peer", "call_remote", "reliable")
func tree_purchase_denied(node_id: int, reason: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_peer_id:
		return
	# Nothing changes anywhere on a reject (spec section 4);
	# the denial is surfaced for the inspector/HUD only.
	print("[DeepTree] purchase denied node=%d reason=%s"
		% [node_id, reason])
	# Issue #215 (node-UI spec 5.3): forward the denial
	# to the HUD, whose canvas surface shows the reason
	# verbatim. Guarded; nothing else about this handler
	# changes.
	if hud != null and hud.has_method(
			"tree_denial_received"):
		hud.tree_denial_received(node_id, reason)


# --- Co-op ping ---

## Place a party-wide ping at whatever the crosshair is pointing at (MMB / G).
func _try_ping() -> void:
	if _ping_cd > 0.0 or _camera == null or not alive or downed:
		return
	_ping_cd = PING_COOLDOWN
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * PING_RANGE)
	params.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	var target: Vector3 = hit["position"] if not hit.is_empty() else from + dir * PING_RANGE
	var pname := NetworkManager.member_name(int(multiplayer.get_unique_id()))
	rpc("spawn_ping", target, pname)


## Host: R starts the next wave (the HUD button can't be clicked while the
## mouse is captured for FPS look).
func _try_start_wave() -> void:
	var dungeons := get_tree().get_nodes_in_group("dungeon")
	if dungeons.is_empty():
		return
	dungeons[0].rpc("request_next_wave")


## Show a bouncing "!" marker + player name at a pinged position for everyone.
@rpc("any_peer", "call_local")
func spawn_ping(pos: Vector3, from_player: String) -> void:
	var root := Node3D.new()
	root.name = "Ping"
	get_parent().add_child(root)
	root.global_position = pos + Vector3(0, 1.5, 0)
	var mark := Label3D.new()
	mark.text = "!"
	mark.font_size = 96
	mark.pixel_size = 0.01
	mark.modulate = Color(1.0, 0.85, 0.1)
	mark.outline_size = 12
	mark.outline_modulate = Color(0.1, 0.08, 0.0)
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	root.add_child(mark)
	var who := Label3D.new()
	who.text = from_player
	who.font_size = 32
	who.pixel_size = 0.008
	who.modulate = Color(1.0, 0.9, 0.4)
	who.outline_size = 8
	who.outline_modulate = Color(0.1, 0.08, 0.0)
	who.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	who.no_depth_test = true
	who.position = Vector3(0, 1.0, 0)
	root.add_child(who)
	AudioManager.sfx("ping", pos)
	# Bounce up and down.
	var base_y := root.position.y
	var tw := root.create_tween().set_loops()
	tw.tween_property(root, "position:y", base_y + 0.5, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(root, "position:y", base_y, 0.4).set_trans(Tween.TRANS_SINE)
	# Cap active pings: drop the oldest.
	_pings.append(root)
	while _pings.size() > PING_MAX:
		var old: Node3D = _pings.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	# Fade out and clean up after the lifetime.
	var fade := root.create_tween()
	fade.tween_interval(PING_LIFETIME)
	fade.tween_property(mark, "modulate:a", 0.0, 0.5)
	fade.parallel().tween_property(who, "modulate:a", 0.0, 0.5)
	fade.tween_callback(root.queue_free)


func _attack_anim() -> void:
	if _viewmodel == null:
		return
	if class_id == "mage":
		var tw := create_tween()
		tw.tween_property(_viewmodel, "position:z", _vm_base.z - 0.3, 0.1)
		tw.tween_property(_viewmodel, "position:z", _vm_base.z, 0.22)
	else:
		var tw2 := create_tween()
		tw2.tween_property(_viewmodel, "rotation:z", -0.9, 0.08)
		tw2.tween_property(_viewmodel, "rotation:z", _vm_base_rot.z, 0.18)
		var tw3 := create_tween()
		tw3.tween_property(_viewmodel, "position:z", _vm_base.z - 0.28, 0.08)
		tw3.tween_property(_viewmodel, "position:z", _vm_base.z, 0.18)


# --- Input ---

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_pad_seen = true
	if not is_multiplayer_authority() or not alive:
		return
	if _reading_board != null:
		_reading_input(event)
		return
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var mm := event as InputEventMouseMotion
			var sens := look_sens_setting()
			var inv := -1.0 if look_invert_y_setting() else 1.0
			_yaw -= mm.relative.x * MOUSE_SENS * sens
			_pitch = clampf(_pitch - mm.relative.y * MOUSE_SENS * sens * inv, -1.2, 1.2)
			rotation.y = _yaw
			if _camera != null:
				_camera.rotation.x = _pitch
		return
	# Issue #144 Phase 1: the verb dispatch below serves mouse buttons,
	# keys and joypad through the Phase 0 action vocabulary. `focused`
	# is the gate: keyboard/mouse events keep the historic capture test
	# verbatim; joypad events use the device-independent predicate.
	var focused := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		focused = gameplay_focused()
	var is_mouse := event is InputEventMouseButton
	var pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
	# Jesse 2026-10-11: command mode click handling (warlord domain).
	# Stays mouse-shaped in this phase — pad commanding is Phase 4.
	if is_mouse and _command_mode and (hud == null or not hud.is_paused):
		var mb := event as InputEventMouseButton
		# Placement mode: left confirms, right cancels.
		if _placing_type != "":
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_command_confirm_placement()
				return
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				command_cancel_placement()
				return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_command_select()
			return
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_command_order()
			return
	# In command mode the pad's combat verbs stay inert — commanding
	# is mouse-shaped until Phase 4; interact/build_menu/pause answer.
	if event.is_action_pressed("attack") and not (_command_mode and pad):
		# Issue #126 Phase 2: rod-out owns the attack verb — hook when
		# the bite window is open, begin the cast charge otherwise (a
		# bobber already out swallows the press). Attacks stay disabled.
		if rod_out and focused:
			if _bite_ready:
				_director_request("request_hook")
			elif not _bobber_out and _cast_charge < 0.0:
				_begin_cast_charge()
			get_viewport().set_input_as_handled()
			return
		if is_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			# Issue #65: don't steal the mouse back while the destination
			# popup is open — clicks on popup rows must stay in UI mode.
			if hud == null or (not hud.is_paused and not hud.inventory_open and not hud.cipher_popup_open and not hud.dest_popup_open and _reading_board == null):
				# Don't steal the mouse back while in RTS command view.
				var rts_cam := get_tree().get_first_node_in_group("rts_camera")
				if rts_cam == null or not bool(rts_cam.get("active")):
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		elif _cooldown <= 0.0 and focused:
			# Issue #91 Phase 1: attack while Holy Light is armed starts the charge.
			if _hl_state == HLState.ARMED:
				_hl_start_charge()
				return
			# Issue #69 Phase 1: attack while charging throws the dagger.
			if _charging and class_id == "rogue":
				_throw_dagger()
			else:
				_do_attack()
		return
	if event.is_action_released("attack") and not (_command_mode and pad):
		# Issue #126 Phase 2: releasing the attack verb fires the charged cast.
		if rod_out and _cast_charge >= 0.0:
			_release_cast()
			get_viewport().set_input_as_handled()
		return
	if (event.is_action_pressed("alt_attack") or event.is_action_released("alt_attack")) and not (_command_mode and pad):
		var alt_pressed := event.is_action_pressed("alt_attack")
		# Issue #126 Phase 2: rod-out owns the alt verb — reel the
		# bobber in (never during the bite window; attack/interact hook).
		if rod_out and focused:
			if alt_pressed and _bobber_out and not _bite_ready:
				_director_request("request_reel_in")
			get_viewport().set_input_as_handled()
			return
		# Issue #91 Phase 1: alt disarms Holy Light / cancels charge (free).
		if alt_pressed and (_hl_state == HLState.ARMED or _hl_state == HLState.CHARGING):
			_hl_disarm()
			return
		# Issue #69 Phase 1: alt hold charges the thrown dagger (rogue only).
		if class_id == "rogue" and alive and focused:
			if alt_pressed:
				_charging = true
				_dagger_charge = 0.0
			else:
				# Release without attacking: cancel silently, no penalty.
				_charging = false
				_dagger_charge = 0.0
				if hud != null and hud.has_method("set_charge_meter"):
					hud.set_charge_meter(0.0, false)
		return
	if event.is_action_pressed("ping") and not (_command_mode and pad):
		if alive and focused and (hud == null or not hud.is_paused):
			_try_ping()
		return
	if event.is_action_pressed("pause"):
		# Issue #91 Phase 1: pause disarms Holy Light / cancels charge (free).
		if _hl_state == HLState.ARMED or _hl_state == HLState.CHARGING:
			_hl_disarm()
			get_viewport().set_input_as_handled()
			return
		# Inventory open: pause swaps to the pause UI (no stacking).
		if hud != null and hud.inventory_open:
			hud.swap_inventory_to_pause()
			get_viewport().set_input_as_handled()
			return
		if focused:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if hud != null:
				hud.show_pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("jump"):
		if alive and focused and (hud == null or not hud.is_paused):
			_jump_queued = true
	if event.is_action_pressed("interact"):
		if hud != null and (hud.cipher_popup_open or _reading_board != null or hud.get("dest_popup_open") == true):
			return
		# Issue #126 Phase 2: interact hooks while the bite window is
		# open (rod-out) — ahead of the world interact dispatch.
		if rod_out and _bite_ready and alive \
				and focused \
				and (hud == null or not hud.is_paused):
			_director_request("request_hook")
			get_viewport().set_input_as_handled()
			return
		# Jesse 2026-10-11: interact in command mode interacts with RTS buildings.
		if _command_mode and (hud == null or not hud.is_paused):
			_command_interact_building()
			return
		if focused and (hud == null or not hud.is_paused):
			# Issue #155 (ii): at a tilled plot (mine or unclaimed)
			# with a quality packet in the bag, E becomes a
			# tap/hold plant press, resolved by _tick_plant_hold
			# (tap on release, quality at the hold threshold).
			# Every other interact dispatches on press as before.
			var target := _nearest_interact_node()
			if target != null and target is FarmPlot \
					and str(target.get("plot_state")) == "tilled" \
					and (int(target.get("occupied_by")) == 0 \
						or int(target.get("occupied_by")) == int(multiplayer.get_unique_id())) \
					and _bag_count(FarmPlot.SEED_ITEM_FINE) > 0:
				_plant_hold_plot = target
				_plant_hold_t = 0.0
				_plant_hold_fired = false
				get_viewport().set_input_as_handled()
				return
			_try_pickup()
	if event.is_action_pressed("build_menu"):
		# Jesse 2026-10-11: build verb in command mode opens the RTS build menu.
		if _command_mode and (hud == null or not hud.is_paused):
			var dungeon := get_tree().get_first_node_in_group("dungeon")
			var rhud := dungeon.get_node_or_null("RTSHUD") if dungeon else null
			if rhud != null and rhud.has_method("toggle_build_menu"):
				rhud.call("toggle_build_menu")
				get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("dash"):
		if alive and focused and (hud == null or not hud.is_paused):
			_try_dash()
	if event.is_action_pressed("cycle_ability"):
		if alive and focused and (hud == null or not hud.is_paused):
			_cycle_ability()
	if event.is_action_pressed("ability"):
		if alive and focused and (hud == null or not hud.is_paused):
			_use_class_ability()
	if event.is_action_pressed("toggle_rod"):
		# Issue #126 Phase 1: the rod verb. (The spec proposed F,
		# but F already fires the class ability — V is the free
		# dedicated key; an implementation fix, per the spec.)
		if alive and focused and (hud == null or not hud.is_paused):
			_toggle_rod_out()
	if event.is_action_pressed("potion"):
		# Potion quick-slot: drink the equipped potion (Jesse's feature).
		# Not focus-gated, exactly as the H key was.
		if alive and (hud == null or not hud.is_paused):
			if hud != null and hud.has_method("drink_potion"):
				hud.drink_potion()
	if event.is_action_pressed("start_wave"):
		if alive and focused and (hud == null or not hud.is_paused):
			_try_start_wave()
	if class_id in ["mage", "architect"] and alive and focused and (hud == null or not hud.is_paused):
		for n in 7:
			if event.is_action_pressed("ability_%d" % (n + 1)):
				# Issue #89: map by ability "key" label, not raw index.
				# Holy Light ("7") joins unlocked_abilities at whatever index
				# it lands on, not index 6.
				_select_ability_by_key(str(n + 1))
	if event.is_action_pressed("signature_ability"):
		if class_id == "mage" and alive and focused and (hud == null or not hud.is_paused):
			_activate_mage_signature()
	if event.is_action_pressed("inventory"):
		if hud != null:
			# Closing is always allowed: the mouse is free while the
			# panel is open, so requiring capture here would trap
			# it open. Opening keeps requiring focus, so the panel
			# can never stack over the pause menu or a popup (both
			# hold the mouse visible).
			if hud.inventory_open:
				hud.toggle_inventory()
			elif focused:
				# In Warlord's Domain, Tab toggles the RTS command view.
				if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_TAB and get_tree().get_first_node_in_group("rts_camera") != null:
					return
				hud.toggle_inventory()

## Downed bleed-out (runs on the downed player's authority).
func _tick_downed(delta: float) -> void:
	_bleedout -= delta
	if hud != null:
		hud.update_downed(_bleedout)
		# Issue #172: the downed player sees the same ONE pooled
		# bar the channeling teammates see (the replicated pool
		# fraction on this node), never a local guess.
		if _revive_pool_frac > 0.0:
			hud.show_revive_progress(_revive_pool_frac)
		else:
			hud.hide_revive_progress()
	if _bleedout <= 0.0:
		_do_death()


## This player's bag count of an item (the bag mirrors the
## server ledgers; client-side reads use it directly).
func _bag_count(item_id: String) -> int:
	var total := 0
	for entry in inventory:
		var item := (entry as Dictionary).get("item") as ItemData
		if item != null and item.id == item_id:
			total += int((entry as Dictionary).get("count", 0))
	return total


## Issue #155 (ii): resolve a deferred plant press (armed in
## _input at a tilled plot while a quality packet is held).
## Target binding mirrors the revive channel: if the plot stops
## being the nearest tilled plot, the press evaporates. Held to
## the threshold -> plant QUALITY (once); released short of it
## -> the tap tier: regular when held, quality when it is the
## only tier in the bag (Jesse's ruling).
func _tick_plant_hold(delta: float) -> void:
	if _plant_hold_plot == null:
		return
	var plot = _plant_hold_plot
	var valid: bool = is_instance_valid(plot) and alive and gameplay_focused() \
		and _nearest_interact_node() == plot \
		and str(plot.get("plot_state")) == "tilled"
	if not valid:
		_plant_hold_plot = null
		return
	if Input.is_action_pressed("interact"):
		_plant_hold_t += delta
		if not _plant_hold_fired and _plant_hold_t >= FarmPlot.PLANT_HOLD_SECONDS:
			_plant_hold_fired = true
			(plot as FarmPlot).interact(self, FarmPlot.TIER_FINE)
	elif not _plant_hold_fired:
		var tier := FarmPlot.TIER_REGULAR if _bag_count(FarmPlot.SEED_ITEM) > 0 else FarmPlot.TIER_FINE
		(plot as FarmPlot).interact(self, tier)
		_plant_hold_plot = null
	else:
		_plant_hold_plot = null


## Teammate revive: hold E near a downed ally to channel a revive.
## Issue #163: the channel is server-witnessed (the start goes
## through the server's validated record, mirroring the repair
## channel) and its progress binds to one target (Part 4).
## Issue #172: completion is the server's own determination
## from the target's pool — the client sends no completion.
func _tick_revive_channel(delta: float) -> void:
	var mate := _nearest_downed_teammate()
	var mate_peer := int(mate.get_multiplayer_authority()) if mate != null else 0
	if mate_peer != _revive_target_peer:
		if _revive_target_peer != 0:
			_send_revive_stop()
		_revive_channel = 0.0
		_revive_target_peer = mate_peer
		if mate_peer != 0:
			_send_revive_start(mate_peer)
	if mate != null and Input.is_action_pressed("interact") and (hud == null or not hud.is_paused):
		# Issue #172: the local accumulation is bookkeeping only
		# (target binding, Part 4) — it no longer completes
		# anything and no longer drives the bar. Completion is
		# the server's, decided by the target's POOL; the bar
		# renders the pool fraction replicated on the target.
		_revive_channel = minf(_revive_channel + delta, REVIVE_CHANNEL)
		if hud != null:
			hud.show_revive_progress(float(mate.get("_revive_pool_frac")))
	else:
		if _revive_channel > 0.0 and hud != null:
			hud.hide_revive_progress()
		_revive_channel = 0.0
		if _revive_target_peer != 0:
			_send_revive_stop()
			_revive_target_peer = 0


func _send_revive_start(target_peer: int) -> void:
	if multiplayer.is_server():
		revive_start(target_peer)
	else:
		rpc_id(NetworkManager.server_peer_id, "revive_start", target_peer)


func _send_revive_stop() -> void:
	if multiplayer.is_server():
		revive_stop()
	else:
		rpc_id(NetworkManager.server_peer_id, "revive_stop")


func _player_node_for_peer(peer: int) -> Node3D:
	for n in get_tree().get_nodes_in_group("players"):
		if int(n.get_multiplayer_authority()) == peer:
			return n as Node3D
	return null


## Server intent endpoint (issue #163 Part 3): a channel-start is
## recorded only if everything re-validates here — the reviver
## alive and standing, the target downed, in range.
@rpc("any_peer", "call_local")
func revive_start(target_peer: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	if not alive or downed:
		return
	var target := _player_node_for_peer(target_peer)
	if target == null or not bool(target.get("downed")):
		return
	if target.global_position.distance_to(global_position) > REVIVE_RANGE + 1.0:
		return
	_srv_revive_target = target_peer
	_srv_revive_t = 0.0


@rpc("any_peer", "call_local")
func revive_stop() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	_srv_revive_target = 0
	_srv_revive_t = 0.0


## Issue #172: there is NO client completion endpoint anymore.
## The #163 revive_complete RPC is REMOVED outright — a forged
## completion now calls a method that does not exist, and the
## 0.8x-plausibility check died with it (R3 closed in its
## strongest form). Completion is server-determined: the pool
## on the target's node fills from validated channel ticks
## (_srv_credit_revive) and the server alone fires it.


## Server notice: the record ended server-side (target left the
## downed state, out of range, reviver down). The client clears
## its channel state so the loser ends cleanly and promptly.
@rpc("any_peer", "call_local")
func revive_channel_ended() -> void:
	if int(get_multiplayer_authority()) != multiplayer.get_unique_id():
		return
	_revive_channel = 0.0
	_revive_target_peer = 0
	if hud != null:
		hud.hide_revive_progress()


## Server tick for revive records: re-validates continuously and
## ends the record the moment the world leaves the channel's
## premises (issue #163: the loser's channel ends when the target
## leaves the downed state for ANY reason).
## Issue #172 tick order, specced so the race cannot reopen:
## validity is re-checked BEFORE crediting; completion is
## evaluated AFTER crediting (inside the target's pool); if
## the target left the downed state this tick, the credit
## fails, the pool zeroes, and there is no completion —
## state exits beat completion.
func _server_revive_tick(delta: float) -> void:
	if _srv_revive_target == 0:
		return
	_srv_revive_t += delta
	var target := _player_node_for_peer(_srv_revive_target)
	var valid := alive and not downed and target != null \
		and bool(target.get("downed")) \
		and target.global_position.distance_to(global_position) <= REVIVE_RANGE + 1.0
	if not valid:
		_srv_revive_target = 0
		_srv_revive_t = 0.0
		if int(get_multiplayer_authority()) != multiplayer.get_unique_id():
			rpc_id(int(get_multiplayer_authority()), "revive_channel_ended")
		else:
			revive_channel_ended()
		return
	# Valid: credit this tick's delta into the target's pool.
	# Every valid record credits at the standard rate — two
	# revivers fill the pool twice as fast; there are no
	# diminishing or bonus constants.
	target.call("_srv_credit_revive", delta)


## Issue #172 (server only, on the TARGET's node): credit one
## validated channel tick into this target's pool and fire
## completion when the pool reaches REVIVE_CHANNEL. The
## downed re-check here is the second half of the tick-order
## rule: a target that left the downed state takes no credit.
func _srv_credit_revive(delta: float) -> void:
	if not multiplayer.is_server() or not downed:
		return
	_srv_revive_pool += delta
	if _srv_revive_pool >= REVIVE_CHANNEL:
		_srv_revive_pool = 0.0
		_srv_sync_pool_frac(true)
		# Completion lands on the target's authority (revive()),
		# from the server only — the same landing #163 used,
		# now fired by the server's own determination.
		var my_peer := int(get_multiplayer_authority())
		if my_peer == int(multiplayer.get_unique_id()):
			call("revive")
		else:
			rpc_id(my_peer, "revive")


## Issue #172: zero this target's pool (server copy) and push
## the cleared fraction out.
func _srv_zero_revive_pool() -> void:
	if _srv_revive_pool != 0.0:
		_srv_revive_pool = 0.0
		_srv_sync_pool_frac(true)


## Issue #172: the pool fraction leaves the server on the
## target's own sync — every copy of the target converges to
## the same fraction, and the owner's snapshot stream then
## carries it onward (push_snapshot's trailing field).
@rpc("any_peer", "call_local", "unreliable")
func sync_revive_pool(frac: float) -> void:
	_revive_pool_frac = frac


## Issue #172 (server copy of the target): keep the replicated
## fraction fresh while a pool is live — throttled to the
## snapshot cadence, immediate when forced (completion, zero).
func _srv_sync_pool_frac(force := false) -> void:
	var frac := clampf(_srv_revive_pool / REVIVE_CHANNEL, 0.0, 1.0)
	if not force and absf(frac - _srv_pool_frac_sent) < 0.02:
		return
	_srv_pool_frac_sent = frac
	rpc("sync_revive_pool", frac)


func _nearest_downed_teammate() -> Node3D:
	var best: Node3D = null
	var best_d := REVIVE_RANGE
	for n in get_tree().get_nodes_in_group("players"):
		if n == self:
			continue
		var p := n as Node3D
		if p == null:
			continue
		if p.get("downed") != true:
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


## --- Wrench repair channel (issue #113 Phase 3) ----------------------
## Hold E with the Field Wrench equipped near a damaged friendly
## repairable. The client sends start/stop INTENTS only; the server
## validates (sender is this node's authority, architect, wrench in the
## WEAPON slot via the replicated equipped_ids, target friendly +
## damaged + in range) and applies the ticks on its own timer. Repair
## is free — the channel is the only limiter. Damage taken does NOT
## interrupt in v1; releasing E, moving, unequipping the wrench, or the
## target filling / being destroyed / leaving reach ends the channel.

## Is this node a repairable this player may repair? Friendly means:
## a dungeon Structure placed by a player (owner_peer > 0 — neutral
## owner 0 is refused), or an RTS building of the player's own faction
## that is not destroyed.
func _is_friendly_repairable(n: Node) -> bool:
	if n is Structure:
		var s := n as Structure
		return s.owner_peer > 0 and s.hp > 0.0 and s.hp < s.max_hp
	if n is RTSBuilding:
		var b := n as RTSBuilding
		return not b.destroyed and not b.under_construction \
			and b.faction == rts_faction \
			and b.hp > 0.0 and b.hp < b.max_hp
	return false


## Nearest damaged friendly repairable within reach of pos, described
## as {node, kind, key, name, hp, max_hp}. kind/key are the network
## identity the server resolves independently: structures by uid,
## RTS buildings by building_id.
func repair_target_at(pos: Vector3, reach: float = REPAIR_REACH) -> Dictionary:
	var best: Node3D = null
	var best_d := reach
	for group in ["structures", "rts_buildings"]:
		for n in get_tree().get_nodes_in_group(group):
			var node := n as Node3D
			if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			if not _is_friendly_repairable(node):
				continue
			var d := node.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = node
	if best == null:
		return {}
	if best is Structure:
		var s := best as Structure
		return {"node": best, "kind": "structure", "key": s.uid,
			"name": s.display_name(), "hp": s.hp, "max_hp": s.max_hp}
	var b := best as RTSBuilding
	return {"node": best, "kind": "building", "key": str(b.building_id),
		"name": b.display_name(), "hp": b.hp, "max_hp": b.max_hp}


## Resolve a network target key on the server.
func _resolve_repair_target(kind: String, key: String) -> Node3D:
	if kind == "structure":
		for n in get_tree().get_nodes_in_group("structures"):
			var s := n as Structure
			if s != null and s.uid == key and not s.is_queued_for_deletion():
				return s
	elif kind == "building":
		for n in get_tree().get_nodes_in_group("rts_buildings"):
			var b := n as RTSBuilding
			if b != null and str(b.building_id) == key and not b.is_queued_for_deletion():
				return b
	return null


func _repair_move_input() -> bool:
	return _move_vector() != Vector2.ZERO


## Client channel driver (authority peer only), mirroring the revive
## channel's shape. Runs every physics frame.
func _tick_repair_channel(_delta: float) -> void:
	var want: bool = alive and has_wrench_equipped() \
		and Input.is_action_pressed("interact") \
		and not _repair_move_input() \
		and _nearest_downed_teammate() == null \
		and (hud == null or not hud.is_paused)
	var target: Node3D = null
	if want:
		var t := repair_target_at(global_position)
		if not t.is_empty():
			target = t["node"] as Node3D
	if target == null:
		if _repair_sending:
			_stop_repair_channel()
		_repair_target = null
	else:
		if not _repair_sending or _repair_target != target:
			_start_repair_channel(target)
		_repair_target = target
	# Wrench raised while channeling (viewmodel nudge, local only).
	if _viewmodel != null:
		var lift := Vector3(0, 0.07, -0.03) if _repair_sending else Vector3.ZERO
		_viewmodel.position = _vm_base + lift


func _start_repair_channel(target: Node3D) -> void:
	var t := repair_target_at(global_position)
	if t.is_empty() or (t["node"] as Node3D) != target:
		return
	_repair_sending = true
	if multiplayer.is_server():
		repair_start(str(t["kind"]), str(t["key"]))
	else:
		rpc_id(NetworkManager.server_peer_id, "repair_start",
			str(t["kind"]), str(t["key"]))


func _stop_repair_channel() -> void:
	_repair_sending = false
	if multiplayer.is_server():
		repair_stop()
	else:
		rpc_id(NetworkManager.server_peer_id, "repair_stop")


## Server intent endpoint: a client asks to start channeling on a
## target. Everything is re-validated here — the client's word is
## never enough.
@rpc("any_peer", "call_local")
func repair_start(kind: String, key: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	if class_id != "architect" or not has_wrench_equipped():
		return
	var target := _resolve_repair_target(kind, key)
	if target == null or not _is_friendly_repairable(target):
		return
	if target.global_position.distance_to(global_position) > REPAIR_REACH + REPAIR_SERVER_SLACK:
		return
	_srv_repair_target = target
	_srv_repair_t = 0.0
	_srv_repair_anchor = global_position


@rpc("any_peer", "call_local")
func repair_stop() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	_srv_repair_target = null
	_srv_repair_t = 0.0


## Server notice: the channel ended server-side (target filled,
## destroyed, out of range, wrench unequipped). The client clears its
## sending state so prompt/FX stop.
@rpc("any_peer", "call_local")
func repair_channel_ended() -> void:
	if int(get_multiplayer_authority()) != multiplayer.get_unique_id():
		return
	_repair_sending = false
	_repair_target = null


## Server tick driver: runs on the server's copy of every player node.
func _server_repair_tick(delta: float) -> void:
	if _srv_repair_target == null:
		return
	var target := _srv_repair_target
	var valid := alive and not downed \
		and is_instance_valid(target) and not target.is_queued_for_deletion() \
		and class_id == "architect" and has_wrench_equipped() \
		and _is_friendly_repairable(target) \
		and target.global_position.distance_to(global_position) <= REPAIR_REACH + REPAIR_SERVER_SLACK \
		and global_position.distance_to(_srv_repair_anchor) <= 1.5
	if not valid:
		_srv_repair_target = null
		_srv_repair_t = 0.0
		if int(get_multiplayer_authority()) != multiplayer.get_unique_id():
			rpc_id(int(get_multiplayer_authority()), "repair_channel_ended")
		else:
			repair_channel_ended()
		return
	_srv_repair_t += delta
	if _srv_repair_t >= REPAIR_TICK_TIME:
		_srv_repair_t = 0.0
		if target.has_method("repair"):
			target.call("repair", REPAIR_TICK_HP)


static func class_abilities(cid: String) -> Array:
	match cid:
		"mage":
			return [
				{"id": "fireball", "name": "Fireball", "unlock": 1, "key": "1", "desc": "Fiery bolt, small blast"},
				{"id": "frost", "name": "Frost Shard", "unlock": 3, "key": "2", "desc": "Fast shard, slows enemies"},
				{"id": "lightning", "name": "Chain Lightning", "unlock": 5, "key": "3", "desc": "Zaps 3 chained targets"},
				{"id": "meteor", "name": "Meteor", "unlock": 8, "key": "4", "desc": "Delayed fiery impact"},
				{"id": "barrage", "name": "Arcane Barrage", "unlock": 15, "key": "5", "desc": "Triple bolt spread"},
				{"id": "blizzard", "name": "Blizzard", "unlock": 30, "key": "6", "desc": "Freezing storm, DoT + slow"},
				{"id": "holy_light", "name": "Holy Light", "unlock": 999, "key": "7", "desc": "Radiant light 10s, heals nearby allies 15% (20s cd)", "aura_req": 20},
			]
		"warrior":
			return [
				{"id": "reciprocity", "name": "Reciprocity", "unlock": 1, "key": "T", "desc": "Healing totem aura"},
				{"id": "bulwark", "name": "Bulwark", "unlock": 4, "key": "T", "desc": "Totem that slows enemies"},
				{"id": "warhorn", "name": "War Horn", "unlock": 7, "key": "T", "desc": "Totem boosting ally damage"},
				{"id": "stoneskin", "name": "Stoneskin", "unlock": 15, "key": "T", "desc": "Totem reducing damage taken"},
				{"id": "rally", "name": "Rally", "unlock": 30, "key": "T", "desc": "Totem boosting move speed"},
			]
		"rogue":
			return [
				{"id": "eagle_eye", "name": "Eagle Eye", "unlock": 1, "key": "F", "desc": "Reveal all enemies 4s; refreshes when a marked foe dies"},
				{"id": "smoke_veil", "name": "Smoke Veil", "unlock": 4, "key": "F", "desc": "Untargetable 6s"},
				{"id": "mark", "name": "Mark Target", "unlock": 7, "key": "F", "desc": "Marked foe takes +50% dmg until it dies"},
				{"id": "shadow_step", "name": "Shadow Step", "unlock": 15, "key": "F", "desc": "Blink 8m forward"},
				{"id": "fan", "name": "Fan of Knives", "unlock": 30, "key": "F", "desc": "Blades hit all nearby foes"},
			]
		"architect":
			return [
				{"id": "sentry_turret", "name": "Sentry Turret", "unlock": 1, "key": "1", "desc": "Turret shoots nearby foes"},
				{"id": "bulwark_wall", "name": "Bulwark Wall", "unlock": 4, "key": "2", "desc": "Stone wall blocks enemies"},
				{"id": "spike_trap", "name": "Spike Trap", "unlock": 8, "key": "3", "desc": "Hidden trap, AoE + slow"},
				{"id": "keystone", "name": "Keystone", "unlock": 15, "key": "4", "desc": "Buffs nearby structures"},
				{"id": "reinforce", "name": "Reinforce", "unlock": 20, "key": "5", "desc": "Ally takes -50% damage 6s"},
				{"id": "demolish", "name": "Demolish", "unlock": 30, "key": "6", "desc": "Detonate all your structures"},
				{"id": "hammer_smash", "name": "Hammer Smash", "unlock": 1, "key": "7", "desc": "Forge Hammer only: slam the ground — AoE damage + stun (10s cd)"},
			]
	return []


## Affinity families: theme groups of skills. Specializing in a skill unlocks
## its family's collection track: traits at 25/50/75, signature skill at 100.
## Holy Light is excluded (special track).
static func families() -> Dictionary:
	return {
		"fire": {
			"name": "Fire", "class": "mage",
			"skills": ["fireball", "meteor"],
			"traits": {
				25: {"id": "kindled", "name": "Kindled", "desc": "+10% damage on fire skills"},
				50: {"id": "wildfire", "name": "Wildfire", "desc": "Fire hits apply burn (3s DoT)"},
				75: {"id": "conflagration", "name": "Conflagration", "desc": "+25% blast radius on fire skills"},
			},
			"signature": {"id": "inferno", "name": "Inferno", "key": "8",
				"desc": "Firestorm descends on a target location: huge AoE burn zone for 5s"},
		},
		"frost": {
			"name": "Frost", "class": "mage",
			"skills": ["frost", "blizzard"],
			"traits": {
				25: {"id": "deep_chill", "name": "Deep Chill", "desc": "+10% damage on frost skills"},
				50: {"id": "brittle", "name": "Brittle", "desc": "Slowed enemies take +15% damage (team)"},
				75: {"id": "permafrost", "name": "Permafrost", "desc": "Slows last +2s"},
			},
			"signature": {"id": "glacial_prison", "name": "Glacial Prison", "key": "8",
				"desc": "Freeze all enemies within 8m solid for 3s"},
		},
		"storm": {
			"name": "Storm", "class": "mage",
			"skills": ["lightning", "barrage"],
			"traits": {
				25: {"id": "charged", "name": "Charged", "desc": "+10% damage on storm skills"},
				50: {"id": "arc_conduit", "name": "Arc Conduit", "desc": "Lightning chains +1 target"},
				75: {"id": "overcharge", "name": "Overcharge", "desc": "Storm hits 15% chance to double-strike"},
			},
			"signature": {"id": "tempest", "name": "Tempest", "key": "8",
				"desc": "6s channeled storm: lightning strikes random nearby enemies"},
		},
		"warden": {
			"name": "Warden", "class": "warrior",
			"skills": ["reciprocity", "stoneskin"],
			"traits": {
				25: {"id": "wardens_oath", "name": "Warden's Oath", "desc": "+15% aura strength on Warden totems"},
				50: {"id": "shared_vitality", "name": "Shared Vitality", "desc": "Stoneskin also grants +10% move speed"},
				75: {"id": "wide_ward", "name": "Wide Ward", "desc": "+25% aura radius on Warden totems"},
			},
			"signature": {"id": "sanctuary_totem", "name": "Sanctuary Totem", "key": "T",
				"desc": "Totem: allies in radius immune to damage for 3s (long cooldown)"},
		},
		"conqueror": {
			"name": "Conqueror", "class": "warrior",
			"skills": ["bulwark", "warhorn", "rally"],
			"traits": {
				25: {"id": "commanding_presence", "name": "Commanding Presence", "desc": "+15% aura strength on Conqueror totems"},
				50: {"id": "relentless", "name": "Relentless", "desc": "Bulwark-slowed enemies deal -10% damage"},
				75: {"id": "war_drums", "name": "War Drums", "desc": "Rally also grants +10% attack speed"},
			},
			"signature": {"id": "doom_totem", "name": "Doom Totem", "key": "T",
				"desc": "Totem: enemies in radius take +30% damage from all sources"},
		},
		"shadow": {
			"name": "Shadow", "class": "rogue",
			"skills": ["smoke_veil", "shadow_step"],
			"traits": {
				25: {"id": "longer_shadows", "name": "Longer Shadows", "desc": "Shadow Step +2m range, Smoke Veil +1s"},
				50: {"id": "unseen", "name": "Unseen", "desc": "First attack after veil/blink crits"},
				75: {"id": "double_take", "name": "Double Take", "desc": "Shadow Step leaves a decoy for 3s"},
			},
			"signature": {"id": "assassinate", "name": "Assassinate", "key": "F",
				"desc": "Blink to a target enemy and strike for 300% damage"},
		},
		"precision": {
			"name": "Precision", "class": "rogue",
			"skills": ["eagle_eye", "mark", "fan"],
			"traits": {
				25: {"id": "true_aim", "name": "True Aim", "desc": "+10% damage to marked/revealed enemies"},
				50: {"id": "hamstring_mark", "name": "Hamstring Mark", "desc": "Marked targets also slowed 20%"},
				75: {"id": "ricochet", "name": "Ricochet", "desc": "Fan of Knives hits +2 targets"},
			},
			"signature": {"id": "execution", "name": "Execution", "key": "F",
				"desc": "Instantly kill a non-boss below 15% HP (bosses take heavy damage)"},
		},
	}


## The family a skill belongs to, or "" if none (e.g. holy_light).
static func family_of(skill_id: String) -> String:
	for fid in families():
		if skill_id in families()[fid]["skills"]:
			return fid
	return ""


## Ability rank 1-5 based on character level. Each rank is +25% effectiveness.
func ability_rank() -> int:
	if level >= 80:
		return 5
	if level >= 60:
		return 4
	if level >= 40:
		return 3
	if level >= 20:
		return 2
	return 1


func rank_mult() -> float:
	return 1.0 + float(ability_rank() - 1) * 0.25


func rank_roman() -> String:
	return ["", "I", "II", "III", "IV", "V"][ability_rank()]


## Refresh the unlocked ability list for the current level. Returns the
## newly unlocked ability dict, if any.
func refresh_abilities() -> Dictionary:
	var result := {}
	var fresh: Array = []
	for a in Player.class_abilities(class_id):
		var unlocked := level >= int(a["unlock"])
		# Holy Light is a Relic Vault special (issue #6): granted only while
		# equipped for the run, never by aura alone. Aura 20 EARNS it.
		if a.has("aura_req"):
			unlocked = equipped_special == "holy_light"
		if unlocked:
			fresh.append(a)
			if not unlocked_abilities.any(func(x): return x["id"] == a["id"]):
				result = a
	# Signature skills join the cycle when their family hits 100 (warrior/rogue).
	# Mage signatures are on key 8, not in the cycle.
	if class_id != "mage":
		var fams := Player.families()
		for fid in fams:
			var sig: Dictionary = family_signature(fid)
			if not sig.is_empty():
				# Only include signatures for this class's families.
				var class_fams := {"warrior": ["warden", "conqueror"], "rogue": ["shadow", "precision"]}
				if class_fams.has(class_id) and fid in class_fams[class_id]:
					if not fresh.any(func(x): return x["id"] == sig["id"]):
						fresh.append(sig)
	# Jesse 2026-10-11: warlord domain grants the Command ability — enables
	# RTS unit/building interaction from first-person view.
	var _dungeon := get_tree().get_first_node_in_group("dungeon")
	if _dungeon != null and _dungeon.get("is_warlord") == true:
		if not fresh.any(func(x): return x["id"] == "command"):
			fresh.append({"id": "command", "name": "Command", "unlock": 1, "key": "T/F",
				"desc": "Issue RTS orders: E on buildings, click to select/order units."})
	unlocked_abilities = fresh
	if selected_ability >= unlocked_abilities.size():
		selected_ability = 0
	# Warrior gains a totem charge on every level-up (max 3).
	if class_id == "warrior":
		totem_charges = mini(3, totem_charges + 1)
	if hud != null:
		hud.refresh_abilities(self)
	return result


# (duplicate _can_act removed; canonical version is near _use_class_ability)


# --- Class ability selection ---

func _cycle_ability() -> void:
	if unlocked_abilities.size() < 2:
		return
	selected_ability = (selected_ability + 1) % unlocked_abilities.size()
	AudioManager.sfx("ui_click")
	if hud != null:
		hud.refresh_abilities(self)


func _select_ability(idx: int) -> void:
	if idx < unlocked_abilities.size() and idx != selected_ability:
		selected_ability = idx
		AudioManager.sfx("ui_click")
		if hud != null:
			hud.refresh_abilities(self)


## Issue #89: select ability by its "key" label (e.g. "7" for Holy Light).
## Raw index mapping breaks for specials: Holy Light joins unlocked_abilities
## at whatever index it lands on (often 2 at 20 Aura), not index 6.
func _select_ability_by_key(key_label: String) -> void:
	for i in range(unlocked_abilities.size()):
		var a: Dictionary = unlocked_abilities[i]
		if str(a.get("key", "")) == key_label:
			_select_ability(i)
			return


func _selected_ability_id() -> String:
	if selected_ability < unlocked_abilities.size():
		return String(unlocked_abilities[selected_ability]["id"])
	return ""


## T/F: use the selected class ability (warrior totem / rogue trick).
## Mage casts via left-click instead.
func _use_class_ability() -> void:
	# Echo recording (issue #9 Phase 2): log the cast. No-op when not recording.
	_notify_echo_ability(_selected_ability_id())
	# Jesse 2026-10-11: Command ability toggles RTS command mode in warlord domain.
	if _selected_ability_id() == "command":
		_toggle_command_mode()
		return
	if class_id == "warrior":
		_place_totem()
	elif class_id == "rogue":
		_activate_rogue_ability()


## Warrior totem placement (implemented in the totem task).
func _place_totem() -> void:
	var totem_id := _selected_ability_id()
	if totem_id == "":
		totem_id = "reciprocity"
	# Signature totems have their own activation.
	if totem_id in ["sanctuary_totem", "doom_totem"]:
		_activate_signature_totem(totem_id)
		return
	if totem_charges <= 0:
		if hud != null:
			hud.toast("No totem charges! Level up to earn more.")
			AudioManager.sfx("ui_error")
		return
	totem_charges -= 1
	var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
	if dungeon != null:
		dungeon.rpc("place_totem", totem_id, global_position, int(multiplayer.get_unique_id()), ability_rank())
	_tree_note_totem_placed()
	if hud != null:
		hud.refresh_abilities(self)


## Issue #210 (Warlord's Tempo): placing a totem grants
## the placer +X% attack speed for 5 s (read in the
## atk_spd chain). Both placement paths call this.
func _tree_note_totem_placed() -> void:
	var tempo_pct := _tree_behavior_pct("warlords_tempo")
	if tempo_pct > 0.0:
		_tree_tempo_pct = tempo_pct
		_tree_tempo_until = Time.get_ticks_msec() + 5000


## Rogue ability activation (implemented in the rogue task).
func _activate_rogue_ability() -> void:
	match _selected_ability_id():
		"eagle_eye":
			_activate_eagle_eye()
		"smoke_veil":
			_activate_smoke_veil()
		"mark":
			_activate_mark()
		"shadow_step":
			_activate_shadow_step()
		"fan":
			_activate_fan()
		"assassinate":
			_activate_assassinate()
		"execution":
			_activate_execution()


## Eagle Eye: reveal all enemies through walls for 4s. Once per wave — refreshed when a marked target dies (issue #189).
func _activate_eagle_eye() -> void:
	var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
	var wave := 0
	if dungeon != null and "wave" in dungeon:
		wave = int(dungeon.get("wave"))
	if eagle_eye_used_wave == wave:
		if hud != null:
			hud.toast("Eagle Eye already used this wave.")
			AudioManager.sfx("ui_error")
		return
	eagle_eye_used_wave = wave
	AudioManager.sfx("eagle_eye")
	if hud != null:
		hud.toast("Eagle Eye! Enemies revealed.")
		hud.refresh_abilities(self)
	# X-ray all mobs on every peer.
	var cast_id := "eagle_%d" % _cast_seq
	var revealed := 0
	# Issue #210 (Surveyor): the reveal also marks the
	# nearest elite or boss, through the mark's own path.
	var surveyor := _tree_behavior_pct("surveyor") > 0.0
	var survey_target: Mob = null
	var survey_d := INF
	for n in get_tree().get_nodes_in_group("mobs"):
		var m := n as Mob
		if m != null and m.alive:
			m.rpc("set_xray", true)
			# Affinity: +1 normal, +5 elite/boss, max +10/activation.
			var pts := 5.0 if (m.is_elite or m.data.is_boss) else 1.0
			gain_affinity_capped("eagle_eye", pts, -1, cast_id, 10.0)
			revealed += 1
			if surveyor and (m.is_elite or m.data.is_boss):
				var d := m.global_position.distance_to(global_position)
				if d < survey_d:
					survey_d = d
					survey_target = m
	if survey_target != null:
		var svuln := _tree_skill_mod("mark", "vuln_add", 0.0)
		if _tree_variant("mark") == "death_sentence":
			svuln += 0.25
		if multiplayer.is_server():
			survey_target.apply_mark(Mob.MARK_PERMANENT, 1.0, svuln)
		else:
			survey_target.rpc_id(NetworkManager.server_peer_id, "apply_mark", Mob.MARK_PERMANENT, 1.0, svuln)
	await get_tree().create_timer(4.0 + _tree_skill_mod(
		"eagle_eye", "duration_add", 0.0)).timeout
	for n in get_tree().get_nodes_in_group("mobs"):
		var m := n as Mob
		if m != null and is_instance_valid(m):
			m.rpc("set_xray", false)


## Smoke Veil: mobs can't target you for 6s. 30s cooldown.
func _activate_smoke_veil() -> void:
	if float(ability_cds.get("smoke_veil", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Smoke Veil on cooldown.")
			AudioManager.sfx("ui_error")
		return
	ability_cds["smoke_veil"] = (30.0) * cooldown_mult() \
		* _tree_skill_mod("smoke_veil", "cd_mult", 1.0)
	stealthed = true
	_stealth_t = (7.0 if has_trait("longer_shadows") else 6.0) \
		+ _tree_skill_mod("smoke_veil", "duration_add", 0.0)
	# Issue #210 (From the Dark): the veil sets the recency
	# the combo condition reads.
	_tree_dark_stamp = Time.get_ticks_msec()
	rpc("set_stealthed", true)
	AudioManager.sfx("smoke_veil")
	Effects.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.5, 0.5, 0.55), 20, 4.0)
	# Affinity: +5 if ≥1 enemy within 10m.
	# Issue #210 (Choking Veil): the same scan slows its
	# enemies 20% for 3 s (server-routed like the mark).
	var choking := _tree_variant("smoke_veil") == "choking_veil"
	var near := false
	for n in get_tree().get_nodes_in_group("mobs"):
		var m := n as Mob
		if m != null and m.alive and m.global_position.distance_to(global_position) < 10.0:
			near = true
			if choking:
				if multiplayer.is_server():
					m.apply_slow(3.0, 0.8)
				else:
					m.rpc_id(NetworkManager.server_peer_id, "rpc_apply_slow", 3.0, 0.8)
			if not choking:
				break
	if near:
		gain_affinity("smoke_veil", 5.0)
	if hud != null:
		hud.toast("Smoke Veil! You vanish.")
		hud.refresh_abilities(self)


## Mark Target: the enemy under your crosshair takes +50% damage until it dies (issue #189: the mark is permanent). 25s cooldown.
func _activate_mark() -> void:
	if float(ability_cds.get("mark", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Mark on cooldown.")
			AudioManager.sfx("ui_error")
		return
	if _camera == null:
		return
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var target := _nearest_mob_aimed(from, dir, 25.0)
	if target == null:
		if hud != null:
			hud.toast("No target in sight.")
			AudioManager.sfx("ui_error")
		return
	ability_cds["mark"] = (25.0) * cooldown_mult() / atk_spd_mult() \
		* _tree_skill_mod("mark", "cd_mult", 1.0)
	# Hamstring Mark trait: marked targets are also slowed 20%.
	var hamstring := 0.8 if has_trait("hamstring_mark") else 1.0
	# Issue #210 (section 2.6): the caster's tree vuln add
	# rides the application and is stored on the mark;
	# Death Sentence deepens it by an authored +0.25 (the
	# base game's amplification is already all-source, so
	# the variant takes the deepen form).
	var vuln := _tree_skill_mod("mark", "vuln_add", 0.0)
	if _tree_variant("mark") == "death_sentence":
		vuln += 0.25
	# SteamMultiplayerPeer can't rpc_id its own peer ID: when this instance is
	# the server, call directly (same outcome — the handler is call_local).
	if multiplayer.is_server():
		target.apply_mark(Mob.MARK_PERMANENT, hamstring, vuln)
	else:
		target.rpc_id(NetworkManager.server_peer_id, "apply_mark", Mob.MARK_PERMANENT, hamstring, vuln)
	AudioManager.sfx("mark")
	if hud != null:
		hud.toast("Target marked! +50% damage.")
		hud.refresh_abilities(self)


func _nearest_mob_aimed(from: Vector3, dir: Vector3, max_dist: float) -> Mob:
	var best: Mob = null
	var best_d := max_dist
	for n in get_tree().get_nodes_in_group("mobs"):
		var m := n as Mob
		if m == null or not m.alive:
			continue
		var to: Vector3 = m.global_position + Vector3(0, 1.0, 0) - from
		var dist := to.length()
		if dist > max_dist or dist < 0.5:
			continue
		if dir.angle_to(to / dist) > 0.15:
			continue
		if dist < best_d:
			best_d = dist
			best = m
	return best


## Shadow Step: blink 8m in the facing direction. 15s cooldown.
func _activate_shadow_step() -> void:
	# Issue #210 (Twin Step): one free re-cast within 2 s
	# of a step — a recast window on the cd site.
	var free_recast := false
	if float(ability_cds.get("shadow_step", 0.0)) > 0.0:
		if _tree_variant("shadow_step") == "twin_step" \
				and _tree_twin_armed \
				and Time.get_ticks_msec() < _tree_twin_until:
			free_recast = true
			_tree_twin_armed = false
		else:
			if hud != null:
				hud.toast("Shadow Step on cooldown.")
				AudioManager.sfx("ui_error")
			return
	if not free_recast:
		ability_cds["shadow_step"] = (15.0) * cooldown_mult() \
			* _tree_skill_mod("shadow_step", "cd_mult", 1.0)
		if _tree_variant("shadow_step") == "twin_step":
			_tree_twin_armed = true
			_tree_twin_until = Time.get_ticks_msec() + 2000
	# Issue #210 (From the Dark): the step sets the recency.
	_tree_dark_stamp = Time.get_ticks_msec()
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# Longer Shadows trait: +2m blink range.
	var blink_dist := 10.0 if has_trait("longer_shadows") else 8.0
	var origin := global_position
	var target := global_position + fwd * blink_dist
	# Don't blink through walls: raycast and stop short.
	var params := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), target + Vector3(0, 1.0, 0))
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(params)
	if not hit.is_empty():
		target = global_position + fwd * (global_position.distance_to(hit["position"]) - 1.0)
	Effects.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.3, 0.3, 0.35), 20, 5.0)
	global_position = target
	Effects.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.6, 0.5, 0.9), 20, 5.0)
	AudioManager.sfx("shadow_step")
	# Amendment 1 section C.2 (Umbral Strike): at arrival,
	# the step bites — weapon damage x the step_dmg
	# aggregate to enemies within 2 m, server-executed
	# with the assassinate strike's damage discipline. At
	# zero aggregate the step damages nothing and moves
	# exactly as today (neutrality).
	var step_dmg := _tree_skill_mod("shadow_step",
		"step_dmg", 0.0)
	if step_dmg > 0.0:
		var sdmg := damage * step_dmg
		var me_step := int(multiplayer.get_unique_id())
		for n in get_tree().get_nodes_in_group("mobs"):
			var m := n as Mob
			if m != null and m.alive and m.global_position.distance_to(global_position) <= 2.0:
				if multiplayer.is_server():
					m.take_damage(sdmg, me_step, global_position)
				else:
					m.rpc_id(NetworkManager.server_peer_id, "take_damage", sdmg, me_step, global_position)
	# Unseen trait: next attack after the blink crits.
	if has_trait("unseen"):
		unseen_crit_ready = true
	# Double Take trait: leave a decoy at the origin for 3s.
	if has_trait("double_take"):
		var dungeon := get_tree().get_first_node_in_group("dungeon")
		if dungeon != null:
			dungeon.rpc("spawn_decoy", origin, int(multiplayer.get_unique_id()))
	# Affinity: +3 if landing within 5m of an enemy, else +1.
	var pts := 1.0
	for n in get_tree().get_nodes_in_group("mobs"):
		var m := n as Mob
		if m != null and m.alive and m.global_position.distance_to(global_position) < 5.0:
			pts = 3.0
			break
	gain_affinity("shadow_step", pts)
	if hud != null:
		hud.refresh_abilities(self)


## Fan of Knives: blades damage all enemies within 5m. 20s cooldown.
## Issue #69 Phase 2: requires dagger in hand (not thrown).
func _activate_fan() -> void:
	if _dagger_out:
		if hud != null:
			hud.toast("Dagger is out — catch it first.")
			AudioManager.sfx("ui_error")
		return
	if float(ability_cds.get("fan", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Fan of Knives on cooldown.")
			AudioManager.sfx("ui_error")
		return
	ability_cds["fan"] = (20.0) * cooldown_mult() / atk_spd_mult() \
		* _tree_skill_mod("fan", "cd_mult", 1.0)
	var dmg := damage * _buff_mult("damage") * rank_mult() * 1.2 \
		* _tree_mult("fan") * _tree_veil_mult()
	# Unseen trait: first attack after veil/blink crits for 2x.
	if unseen_crit_ready:
		dmg *= 2.0
		unseen_crit_ready = false
	AudioManager.sfx("fan")
	Effects.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.8, 0.85, 0.9), 30, 7.0)
	# Ricochet trait: fan radius 5m → 6m (hits more targets).
	var fan_radius := 6.0 if has_trait("ricochet") else 5.0
	if multiplayer.is_server():
		var from := int(multiplayer.get_unique_id())
		var cast_id := "fan_%d" % _cast_seq
		# Issue #210 (Deadeye): the fan hits marked targets
		# harder — the mob's mark state is the read.
		var deadeye_pct := _tree_behavior_pct("deadeye")
		# Issue #210 (Shuriken Storm, shape ruled on the
		# corrected spec): the fan's +2-at-80% identity on
		# its real radial-burst form — each in-radius
		# target is struck two additional times at 80%
		# (damage-only; the cast's affinity/combo
		# bookkeeping stays on the first strike).
		var shuriken := _tree_variant("fan") == "shuriken_storm"
		for n in get_tree().get_nodes_in_group("mobs"):
			var m := n as Mob
			if m == null or not m.alive:
				continue
			if m.global_position.distance_to(global_position) < fan_radius:
				var was_alive := m.alive
				var was_slowed := m.is_slowed()
				var hit_dmg := dmg
				if deadeye_pct > 0.0 and m.is_marked():
					hit_dmg = dmg * (1.0 + deadeye_pct / 100.0)
				if multiplayer.is_server():
					m.take_damage(hit_dmg, from, global_position)
				else:
					m.rpc_id(NetworkManager.server_peer_id, "take_damage", hit_dmg, from, global_position)
				if shuriken:
					for extra in 2:
						if multiplayer.is_server():
							m.take_damage(hit_dmg * 0.8, from, global_position)
						else:
							m.rpc_id(NetworkManager.server_peer_id, "take_damage", hit_dmg * 0.8, from, global_position)
				# Affinity: +2 per enemy hit, max +8/cast.
				gain_affinity_capped("fan", 2.0, m.get_instance_id(), cast_id, 8.0)
				# Combo Finisher: Shatter Cascade (issue #8) -- Fan of Knives
				# killing blow on a frost-slowed enemy: frost nova burst.
				if Combo.note_kill(m, was_alive) and was_slowed and Combo.check_fan_kill(m):
					Combo.apply_frost_nova(get_tree(), m.global_position, dmg, from)
					Effects.burst(get_parent(), m.global_position + Vector3(0, 1.0, 0), Color(0.7, 0.9, 1.0), 30, 6.0)
					AudioManager.sfx("frost_hit", m.global_position)
					Combo.announce_finisher(get_tree(), "shatter_cascade")
	else:
		rpc("fan_fx", global_position)
	if hud != null:
		hud.refresh_abilities(self)


@rpc("any_peer", "call_local")
func fan_fx(pos: Vector3) -> void:
	Effects.burst(get_parent(), pos + Vector3(0, 1.0, 0), Color(0.8, 0.85, 0.9), 30, 7.0)
	AudioManager.sfx("fan", pos)


# --- Signature skills (Phase 4) ---
# Implemented by subagents; stubs here for parse integrity.

## Mage: key 8 activates the signature of the specialized skill's family.
func _activate_mage_signature() -> void:
	if specialization == "":
		if hud != null:
			hud.toast("Specialize in a skill first (pause menu).")
		return
	var fid := Player.family_of(specialization)
	var sig := family_signature(fid)
	if sig.is_empty():
		if hud != null:
			hud.toast("Signature not unlocked yet (reach 100 affinity).")
			AudioManager.sfx("ui_error")
		return
	match String(sig["id"]):
		"inferno":
			_activate_inferno()
		"glacial_prison":
			_activate_glacial_prison()
		"tempest":
			_activate_tempest()


## INFERNO (fire signature): target a location — a massive firestorm descends,
## huge AoE burn zone for 5s. 60s cooldown. ~1.5x rank-V meteor total.
func _activate_inferno() -> void:
	if float(ability_cds.get("inferno", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Inferno on cooldown.")
			AudioManager.sfx("ui_error")
		return
	if _camera == null:
		return
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var target := from + dir * 25.0
	var params := PhysicsRayQueryParameters3D.create(from, target)
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(params)
	var point: Vector3 = hit["position"] if not hit.is_empty() else target
	point.y = maxf(point.y, 0.1)
	ability_cds["inferno"] = (60.0) * cooldown_mult() / atk_spd_mult() * _tree_skill_mod("inferno", "cd_mult", 1.0)
	_cast_seq += 1
	# 10 ticks x 0.6 = 6.0x base ≈ 1.5x rank-V meteor (4.0x), plus burn.
	var dmg := damage * _buff_mult("damage") * 0.6 * trait_damage_mult("fireball") * _tree_fire_mult("inferno")
	rpc("cast_inferno", point, dmg, int(multiplayer.get_unique_id()), _cast_seq)
	# Fuel for the Flame (issue #206): casting Inferno opens
	# the 5 s fire-damage window the behavior prices.
	if not tree_aggregates.is_empty() and (tree_aggregates.get(
			"behaviors", {}) as Dictionary).has(
			"fuel_for_the_flame"):
		_tree_fuel_until = Time.get_ticks_msec() + 5000
	AudioManager.sfx("milestone")
	if hud != null:
		hud.toast("INFERNO!")
		hud.refresh_abilities(self)


@rpc("any_peer", "call_local")
func cast_inferno(point: Vector3, dmg: float, owner: int, seq: int) -> void:
	Effects.telegraph_ring(get_parent(), point, 8.0, Color(1.0, 0.4, 0.1))
	Effects.burst(get_parent(), point + Vector3(0, 1.0, 0), Color(1.0, 0.5, 0.1), 60, 10.0)
	Effects.scorch(get_parent(), point, 8.0)
	var flames := Effects.make_flame()
	flames.amount = 60
	get_parent().add_child(flames)
	flames.global_position = point + Vector3(0, 1.0, 0)
	flames.emitting = true
	AudioManager.sfx("explosion", point)
	AudioManager.sfx("meteor_incoming", point)
	# 10 ticks over 5 seconds.
	for i in 10:
		await get_tree().create_timer(0.5).timeout
		if not is_inside_tree():
			break
		if multiplayer.is_server():
			for n in get_tree().get_nodes_in_group("mobs"):
				var m := n as Mob
				if m == null or not m.alive:
					continue
				if m.global_position.distance_to(point) < 8.0:
					if multiplayer.is_server():
						m.take_damage(dmg, owner, point)
					else:
						m.rpc_id(NetworkManager.server_peer_id, "take_damage", dmg, owner, point)
					m.apply_burn(3.0, dmg * 0.3, owner)
			# Phoenix Pyre (issue #206 variant): the tick also
			# heals allies in the radius for a fraction of its
			# damage (the Holy Light precedent). Heal fraction
			# is an authored placeholder.
			if _tree_variant("inferno") == "phoenix_pyre":
				for pn in get_tree().get_nodes_in_group("players"):
					var pl := pn as Player
					if pl != null and pl.alive and pl.global_position.distance_to(point) < 8.0:
						pl.heal(dmg * 0.25)
		if i % 3 == 2 and is_inside_tree():
			Effects.burst(get_parent(), point + Vector3(0, 1.0, 0), Color(1.0, 0.45, 0.1), 20, 7.0)
	flames.emitting = false
	get_parent().get_tree().create_timer(1.0).timeout.connect(flames.queue_free)


## GLACIAL PRISON (frost signature): freeze all enemies within 8m solid for 3s.
## 60s cooldown. Frozen enemies also trigger Shatter (+25% team damage).
func _activate_glacial_prison() -> void:
	if float(ability_cds.get("glacial_prison", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Glacial Prison on cooldown.")
			AudioManager.sfx("ui_error")
		return
	ability_cds["glacial_prison"] = (60.0) * cooldown_mult() / atk_spd_mult() * _tree_skill_mod("glacial_prison", "cd_mult", 1.0)
	_cast_seq += 1
	# Issue #210: Stasis Burst's authored damage — one full
	# basic-skill hit (damage x 1.0), captured at activation.
	var burst := damage if _tree_variant("glacial_prison") \
		== "stasis_burst" else 0.0
	rpc("cast_glacial_prison", global_position, int(multiplayer.get_unique_id()), _cast_seq, burst)
	AudioManager.sfx("milestone")
	if hud != null:
		hud.toast("GLACIAL PRISON!")
		hud.refresh_abilities(self)


@rpc("any_peer", "call_local")
func cast_glacial_prison(center: Vector3, owner: int, seq: int, burst: float = 0.0) -> void:
	# Issue #210: radius_add + freeze_add read off the
	# caster (this node) at cast.
	var radius := 8.0 + _tree_skill_mod("glacial_prison",
		"radius_add", 0.0)
	var freeze := 3.0 + _tree_skill_mod("glacial_prison",
		"freeze_add", 0.0)
	Effects.telegraph_ring(get_parent(), center, radius, Color(0.6, 0.85, 1.0))
	Effects.burst(get_parent(), center + Vector3(0, 1.0, 0), Color(0.7, 0.9, 1.0), 50, 9.0)
	AudioManager.sfx("frost_hit", center)
	AudioManager.sfx("blizzard_cast", center)
	if multiplayer.is_server():
		var frozen: Array = []
		for n in get_tree().get_nodes_in_group("mobs"):
			var m := n as Mob
			if m == null or not m.alive:
				continue
			if m.global_position.distance_to(center) < radius:
				# 0.0 mult = frozen solid; also sets shatter for team synergy.
				m.apply_slow(freeze, 0.0)
				# Brittle Ice (Amendment 1): store the
				# shatter — caster damage x the prison's
				# shatter_pct aggregate, read on this node
				# (the caster). Zero at zero aggregate.
				m.prison_shatter = damage * _tree_skill_mod(
					"glacial_prison", "shatter_pct", 0.0)
				m.prison_shatter_owner = owner
				frozen.append(m)
		# Stasis Burst (issue #210): at freeze end the
		# prison's targets take the authored burst damage.
		if burst > 0.0 and not frozen.is_empty():
			await get_tree().create_timer(freeze).timeout
			if not is_inside_tree():
				return
			for m in frozen:
				if is_instance_valid(m) and m.alive:
					m.take_damage(burst, owner, center)
			Effects.burst(get_parent(), center + Vector3(0, 1.0, 0), Color(0.7, 0.9, 1.0), 40, 8.0)
			AudioManager.sfx("frost_hit", center)


## TEMPEST (storm signature): 6s channeled storm — lightning strikes random
## nearby enemies every 0.5s. 90s cooldown. Per-strike 1.5x chain lightning.
func _activate_tempest() -> void:
	if float(ability_cds.get("tempest", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Tempest on cooldown.")
			AudioManager.sfx("ui_error")
		return
	ability_cds["tempest"] = (90.0) * cooldown_mult() / atk_spd_mult() * _tree_skill_mod("tempest", "cd_mult", 1.0)
	_cast_seq += 1
	# Issue #210: Stormcharged's 10 s window arms here (the
	# fuel_for_the_flame window shape).
	if _tree_behavior_pct("stormcharged") > 0.0:
		_tree_storm_until = Time.get_ticks_msec() + 10000
	var dmg := damage * _buff_mult("damage") * 0.8 * 1.5 * trait_damage_mult("lightning") * _tree_mult("tempest")
	rpc("cast_tempest", dmg, int(multiplayer.get_unique_id()), _cast_seq)
	AudioManager.sfx("milestone")
	if hud != null:
		hud.toast("TEMPEST!")
		hud.refresh_abilities(self)


@rpc("any_peer", "call_local")
func cast_tempest(dmg: float, owner: int, seq: int) -> void:
	# Issue #210: radius_add + duration_add (1 s = 2 strikes
	# per step) read off the caster (this node) at cast.
	var radius := 15.0 + _tree_skill_mod("tempest",
		"radius_add", 0.0)
	var strikes := 12 + int(round(_tree_skill_mod("tempest",
		"duration_add", 0.0) / 0.5))
	AudioManager.sfx("lightning_cast", global_position)
	Effects.telegraph_ring(get_parent(), global_position, radius, Color(0.7, 0.9, 1.0))
	# 12 strikes over 6 seconds (stock); the storm follows the caster.
	for i in strikes:
		await get_tree().create_timer(0.5).timeout
		if not is_inside_tree():
			break
		if multiplayer.is_server():
			var candidates: Array = []
			for n in get_tree().get_nodes_in_group("mobs"):
				var m := n as Mob
				if m != null and m.alive and m.global_position.distance_to(global_position) < radius:
					candidates.append(m)
			if candidates.is_empty():
				continue
			var target: Mob = candidates[randi() % candidates.size()]
			var sky: Vector3 = target.global_position + Vector3(0, 8.0, 0)
			var hit_pos: Vector3 = target.global_position + Vector3(0, 1.0, 0)
			if multiplayer.is_server():
				target.take_damage(dmg, owner, global_position)
			else:
				target.rpc_id(NetworkManager.server_peer_id, "take_damage", dmg, owner, global_position)
			rpc("chain_fx", sky, hit_pos)
			AudioManager.sfx("lightning_zap", hit_pos)
	# Eye of the Storm (issue #210): when the channel ends,
	# a final strike at 200% on the nearest target.
	if multiplayer.is_server() and is_inside_tree() \
			and _tree_variant("tempest") == "eye_of_the_storm":
		var nearest: Mob = null
		var best := radius
		for n in get_tree().get_nodes_in_group("mobs"):
			var m := n as Mob
			if m == null or not m.alive:
				continue
			var d := m.global_position.distance_to(global_position)
			if d < best:
				best = d
				nearest = m
		if nearest != null:
			nearest.take_damage(dmg * 2.0, owner, global_position)
			rpc("chain_fx", nearest.global_position + Vector3(0, 8.0, 0), nearest.global_position + Vector3(0, 1.0, 0))
			AudioManager.sfx("lightning_zap", nearest.global_position)


## Warrior: signature totems via T (uses totem charges).
## Sanctuary: 120s cooldown. Doom: 90s cooldown. Fixed power (rank 1).
func _activate_signature_totem(totem_id: String) -> void:
	var cd_key := totem_id
	var cd := 120.0 if totem_id == "sanctuary_totem" else 90.0
	if float(ability_cds.get(cd_key, 0.0)) > 0.0:
		if hud != null:
			hud.toast("Signature on cooldown.")
			AudioManager.sfx("ui_error")
		return
	if totem_charges <= 0:
		if hud != null:
			hud.toast("No totem charges! Level up to earn more.")
			AudioManager.sfx("ui_error")
		return
	totem_charges -= 1
	ability_cds[cd_key] = (cd) * cooldown_mult() \
		* _tree_skill_mod(cd_key, "cd_mult", 1.0)
	var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
	if dungeon != null:
		dungeon.rpc("place_totem", totem_id, global_position, int(multiplayer.get_unique_id()), 1)
	_tree_note_totem_placed()
	AudioManager.sfx("milestone")
	if hud != null:
		var sig_name := "Sanctuary Totem" if totem_id == "sanctuary_totem" else "Doom Totem"
		hud.toast("%s placed!" % sig_name)
		hud.refresh_abilities(self)


## Sanctuary Totem (Warden signature): damage immunity while in the aura.
var _sanctuary_t := 0.0


@rpc("any_peer", "call_local")
func apply_sanctuary(duration: float) -> void:
	if not is_multiplayer_authority():
		return
	_sanctuary_t = maxf(_sanctuary_t, duration)


## Rogue: F-cycle signatures.
func _activate_assassinate() -> void:
	if float(ability_cds.get("assassinate", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Assassinate on cooldown.")
			AudioManager.sfx("ui_error")
		return
	if _camera == null:
		return
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var target := _nearest_mob_aimed(from, dir, 25.0)
	if target == null:
		if hud != null:
			hud.toast("No target in sight.")
			AudioManager.sfx("ui_error")
		return
	ability_cds["assassinate"] = (45.0) * cooldown_mult() / atk_spd_mult() \
		* _tree_skill_mod("assassinate", "cd_mult", 1.0)
	var origin := global_position
	# Blink to behind the target (far side relative to our position).
	var away: Vector3 = target.global_position - global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -global_transform.basis.z
	var dest := target.global_position + away * 1.8
	# Don't blink through walls: raycast and stop short.
	var params := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), dest + Vector3(0, 1.0, 0))
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(params)
	if not hit.is_empty():
		var hit_dist: float = global_position.distance_to(hit["position"]) - 1.0
		dest = global_position + (dest - global_position).normalized() * maxf(hit_dist, 0.5)
	Effects.burst(get_parent(), origin + Vector3(0, 1.0, 0), Color(0.2, 0.2, 0.25), 25, 6.0)
	global_position = dest
	Effects.burst(get_parent(), dest + Vector3(0, 1.0, 0), Color(0.6, 0.5, 0.9), 25, 6.0)
	AudioManager.sfx("shadow_step")
	# Strike for 300% damage (server-authoritative).
	var strike := damage * _buff_mult("damage") * rank_mult() * 3.0 \
		* _tree_mult("assassinate")
	# Issue #210 (From the Dark): +X% when cast within 2 s
	# of Smoke Veil or Shadow Step (the recency stamp).
	var dark_pct := _tree_behavior_pct("from_the_dark")
	if dark_pct > 0.0 and Time.get_ticks_msec() \
			- _tree_dark_stamp <= 2000:
		strike *= 1.0 + dark_pct / 100.0
	# Issue #210 (Veilwalker): the post-veil window also
	# feeds the strike.
	strike *= _tree_veil_mult()
	var me := int(multiplayer.get_unique_id())
	# The strike routes through the mob's assassinate_hit
	# wrapper so a kill is attributable at the kill sites
	# (Coup de Grâce); damage discipline unchanged.
	if multiplayer.is_server():
		target.assassinate_hit(strike, me, global_position)
	else:
		target.rpc_id(NetworkManager.server_peer_id, "assassinate_hit", strike, me, global_position)
	Effects.burst(get_parent(), target.global_position + Vector3(0, 1.2, 0), Color(1.0, 0.85, 0.9), 30, 7.0)
	AudioManager.sfx("fan")
	if hud != null:
		hud.toast("Assassinate!")
		hud.refresh_abilities(self)


func _activate_execution() -> void:
	if float(ability_cds.get("execution", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Execution on cooldown.")
			AudioManager.sfx("ui_error")
		return
	if _camera == null:
		return
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var target := _nearest_mob_aimed(from, dir, 25.0)
	if target == null:
		if hud != null:
			hud.toast("No target in sight.")
			AudioManager.sfx("ui_error")
		return
	ability_cds["execution"] = (60.0) * cooldown_mult() / atk_spd_mult() \
		* _tree_skill_mod("execution", "cd_mult", 1.0)
	var me := int(multiplayer.get_unique_id())
	var base := damage * _buff_mult("damage") * rank_mult() \
		* _tree_mult("execution") * _tree_veil_mult()
	var is_boss: bool = (target.get("data") as MobData).is_boss
	var frac := target.hp / maxf(target.max_hp, 0.01)
	var dmg := base * 2.0
	var executed := false
	var exec_thr := 0.15 + _tree_skill_mod(
		"execution", "threshold_add", 0.0)
	if not is_boss and frac < exec_thr:
		# Instant kill: overwhelming damage routes through the normal death path.
		dmg = 999999.0
		executed = true
	elif is_boss:
		# Issue #210 (Headsman): bosses face the threshold
		# at half effect instead of being immune to it.
		if _tree_variant("execution") == "headsman" \
				and frac < exec_thr * 0.5:
			dmg = 999999.0
			executed = true
		else:
			dmg = base * 5.0
	if multiplayer.is_server():
		target.take_damage(dmg, me, global_position)
	else:
		target.rpc_id(NetworkManager.server_peer_id, "take_damage", dmg, me, global_position)
	Effects.burst(get_parent(), target.global_position + Vector3(0, 1.2, 0), Color(1.0, 0.15, 0.1), 35, 8.0)
	if executed:
		AudioManager.sfx("mob_die")
		if hud != null:
			hud.toast("EXECUTED!")
	else:
		AudioManager.sfx("fan")
		if hud != null:
			hud.toast("Execution!")
	if hud != null:
		hud.refresh_abilities(self)


@rpc("any_peer", "call_local")
func heal(amount: float) -> void:
	if not is_multiplayer_authority():
		return
	if not alive:
		return
	hp = minf(max_hp, hp + amount)
	health_changed.emit(hp, max_hp)
	_update_health_bar()
	Effects.burst(get_parent(), global_position + Vector3(0, 1.2, 0), Color(0.4, 1.0, 0.5), 8, 3.0)


## War Horn totem: +25% damage while inside the aura (scaled by aura strength).
var _warhorn_t := 0.0
var _warhorn_strength := 1.0


@rpc("any_peer", "call_local")
func apply_warhorn(duration: float, strength: float = 1.0) -> void:
	if not is_multiplayer_authority():
		return
	_warhorn_t = maxf(_warhorn_t, duration)
	_warhorn_strength = strength


@rpc("any_peer", "call_local")
func set_stealthed(s: bool) -> void:
	stealthed = s
	# Visual: translucent for other players' views.
	if _sprite != null:
		_sprite.modulate.a = 0.35 if s else 1.0


## Gilded Cage (Warden): root this player for the duration.
@rpc("any_peer", "call_local")
func apply_caged(duration: float) -> void:
	_caged_t = maxf(_caged_t, duration)
	if hud != null:
		hud.toast("Caged! Break the dome!")


@rpc("any_peer", "call_local")
func clear_caged() -> void:
	_caged_t = 0.0


## Stoneskin totem: -30% damage taken while in the aura (scaled by aura strength).
var _stoneskin_t := 0.0
var _stoneskin_strength := 1.0


@rpc("any_peer", "call_local")
func apply_stoneskin(duration: float, strength: float = 1.0) -> void:
	if not is_multiplayer_authority():
		return
	_stoneskin_t = maxf(_stoneskin_t, duration)
	_stoneskin_strength = strength


## Reinforce (Architect): -50% damage taken while shelled.
var _reinforce_t := 0.0
var _reinforce_shell: MeshInstance3D = null


@rpc("any_peer", "call_local")
func apply_reinforce(duration: float,
		strength: float = 0.5) -> void:
	if not is_multiplayer_authority():
		return
	_reinforce_t = maxf(_reinforce_t, duration)
	_reinforce_strength = strength
	_update_reinforce_shell()


func _update_reinforce_shell() -> void:
	if _reinforce_shell == null:
		_reinforce_shell = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.2, 2.2, 1.2)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.6, 0.58, 0.55, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.material = mat
		_reinforce_shell.mesh = bm
		_reinforce_shell.position = Vector3(0, 1.1, 0)
		add_child(_reinforce_shell)
	_reinforce_shell.visible = _reinforce_t > 0.0


## Rally totem: +30% move speed while in the aura (scaled by aura strength).
var _rally_t := 0.0
var _rally_strength := 1.0


@rpc("any_peer", "call_local")
func apply_rally(duration: float, strength: float = 1.0) -> void:
	if not is_multiplayer_authority():
		return
	_rally_t = maxf(_rally_t, duration)
	_rally_strength = strength


## Shared Vitality (Warden trait): Stoneskin also grants +10% move speed.
var _shared_vitality_t := 0.0


@rpc("any_peer", "call_local")
func apply_shared_vitality(duration: float) -> void:
	if not is_multiplayer_authority():
		return
	_shared_vitality_t = maxf(_shared_vitality_t, duration)


## War Drums (Conqueror trait): Rally also grants +10% attack speed.
var _war_drums_t := 0.0


@rpc("any_peer", "call_local")
func apply_war_drums(duration: float) -> void:
	if not is_multiplayer_authority():
		return
	_war_drums_t = maxf(_war_drums_t, duration)


func _can_act() -> bool:
	return (_cooldown <= 0.0 and gameplay_focused()
		and (hud == null or not hud.is_paused))


## Issue #144 Phase 1: the device-independent gameplay-focus predicate
## (characterization R1-R4), successor to the raw mouse-capture check.
## Keyboard/mouse satisfy it exactly as before — mouse captured. A pad
## session satisfies it logically: a joypad has been seen, and none of
## the states that release the mouse for the keyboard player (pause,
## inventory, an interact popup, a terminal session dialog, FPS
## command mode, board reading) is active — the predicate flips on
## the same transitions as capture (R2), needs no mouse-shaped
## recovery (R3), and is plain state a headless test can assert (R4).
## vault_open is deliberately NOT consulted: its historic stuck-set
## wart was fixed in 8673dd1, and the exclusion is consequence-free
## either way — the vault UI runs through the cipher popup shell,
## whose flag IS consulted — so no vault state can set this gate
## wrong. Issue #149: the session-lost / version-mismatch dialog
## state joins the list (its builders release the mouse and
## force-close pause/inventory, so without it the pad leg read true
## behind a terminal modal).
func gameplay_focused() -> bool:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return true
	if not _pad_seen or _command_mode or _reading_board != null:
		return false
	if hud == null:
		return true
	return not (hud.is_paused or hud.inventory_open or hud.cipher_popup_open
		or hud.dest_popup_open or hud.vendor_open or hud.dock_vendor_open
		or hud.bounty_open or hud._session_lost_dialog != null)


## Issue #144 Phase 1 (Q2): look settings, persisted by the settings
## phase through SaveManager profile settings (the FOV pattern).
func look_sens_setting() -> float:
	return float(get_node("/root/SaveManager").get_profile_setting("settings", "look_sens", 1.0))


func look_deadzone_setting() -> float:
	return clampf(float(get_node("/root/SaveManager").get_profile_setting("settings", "look_deadzone", 0.2)), 0.0, 0.9)


func look_invert_y_setting() -> bool:
	return bool(get_node("/root/SaveManager").get_profile_setting("settings", "look_invert_y", false))


## Issue #144 Phase 1: the unified move read behind the Phase 0/1
## actions — keyboard exactly as the old physical polls (the actions
## shadow them 1:1) plus the analog stick, tilt modulating the vector
## magnitude per Q2. The settings deadzone shapes the stick only;
## digital keys always read full strength.
func _move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back", look_deadzone_setting())


## Solo-only: switch class. Resets level to 1, clears stat points and
## bonus stats. Inventory is kept.
func switch_class(new_class: String) -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.get_peers().size() > 0:
		return  # solo only
	# Issue #4 Phase 2: persist the outgoing class's collection before the
	# reset below wipes it (mid-level earnings would otherwise be lost).
	if not family_collection.is_empty():
		SaveManager.save_collections(str(class_id), family_collection)
	class_id = new_class
	class_data = load("res://data/classes/%s.tres" % class_id) as ClassData
	# Reset progression.
	level = 1
	xp = 0
	xp_next = int(25.0 * pow(1, 1.4))
	stat_points = 0
	bonus_damage = 0.0
	bonus_health = 0.0
	bonus_speed = 0.0
	bonus_aura = 0.0
	bonus_atk_spd = 0.0
	selected_ability = 0
	ability_cds.clear()
	totem_charges = 1 if class_id == "warrior" else 0
	eagle_eye_used_wave = -1
	# Affinity resets on class switch (collections are per-class anyway).
	specialization = ""
	affinity.clear()
	family_collection.clear()
	# A class switch is a fresh start for the incoming class (level resets
	# to 1): its run-scoped signature unlocks clear with everything else —
	# the profile book load below restores the record, not the unlock.
	run_signatures.clear()
	# Issue #4 Phase 2: restore the incoming class's earned collection —
	# collections are permanent account meta, not per-run state.
	family_collection = SaveManager.load_collections(new_class)
	_affinity_enemy_cd.clear()
	# Issue #104 Phase 1: gear the new class may not equip comes off.
	var unequipped := _unequip_class_restricted()
	# Issue #113: switching INTO the architect grants the class
	# tools with fresh-start semantics (equip_wrench=true) — the
	# wrench lands equipped, the hammer bagged. Idempotent:
	# tools kept bagged through a switch-away are revived, never
	# doubled; switching away confiscates nothing.
	if class_id == "architect":
		ensure_architect_tools(true)
	_recalc_stats()
	hp = max_hp
	health_changed.emit(hp, max_hp)
	xp_changed.emit(xp, xp_next, level)
	# Rebuild visuals.
	_build_sprite()
	_build_aura_visual()
	$Label3D.text = _display_name()
	if _viewmodel != null:
		_viewmodel.queue_free()
		_build_viewmodel()
	_update_staff_glow()
	_push_aura()
	refresh_abilities()  # rebuild unlocked_abilities for the new class + HUD bar
	if hud != null:
		if not unequipped.is_empty():
			hud.toast("Unequipped (class): %s" % ", ".join(unequipped))
		hud.set_level(level, self)  # refresh "Lv 1 Warrior" label


# --- Affinity Families ---

## Specialize in a skill. Must be level-unlocked.
func specialize(skill_id: String) -> void:
	# Gate: specialization unlocks at SPECIALIZATION_UNLOCK_LEVEL.
	if level < SPECIALIZATION_UNLOCK_LEVEL:
		if hud != null:
			hud.toast("Specialization unlocks at level %d." % SPECIALIZATION_UNLOCK_LEVEL)
			AudioManager.sfx("ui_error")
		return
	var found := false
	for a in Player.class_abilities(str(get("class_id"))):
		if str(a["id"]) == skill_id and int(a["unlock"]) <= level:
			found = true
			break
	if not found:
		return
	specialization = skill_id
	if hud != null:
		hud.toast("Specialized in %s (2x affinity gain)" % skill_id.capitalize())


## Respec: clear specialization, reset the old skill's affinity to 0.
## Family collections persist (they're collections, not builds).
func respec() -> void:
	if specialization != "":
		affinity[specialization] = 0.0
		# The zeroed affinity was what earned this family's run signature —
		# the unlock goes with it (re-earn by climbing back to 100).
		run_signatures.erase(Player.family_of(specialization))
		specialization = ""
		if hud != null:
			hud.toast("Specialization cleared")


## Grant affinity for a skill, with lockout/focus and anti-cheese.
## enemy_id: use -1 for non-enemy events (still requires the skill be specialized).
## Returns the actual points granted (0 if locked out or on cooldown).
func gain_affinity(skill_id: String, points: float, enemy_id: int = -1) -> float:
	# Lockout: only the specialized skill gains.
	if specialization == "" or specialization != skill_id:
		return 0.0
	# No gain while dead.
	if not alive:
		return 0.0
	# Per-enemy 5s cooldown.
	if enemy_id >= 0:
		var key := "%s:%d" % [skill_id, enemy_id]
		var now := Time.get_ticks_msec()
		if _affinity_enemy_cd.has(key) and now - int(_affinity_enemy_cd[key]) < AFFINITY_ENEMY_CD:
			return 0.0
		_affinity_enemy_cd[key] = now
	var gained := points * FOCUS_MULT * AFFINITY_RATE
	# Issue #206 (spec section 3): the lifetime hook — ONE
	# line in this funnel (gain_affinity_capped inherits it).
	# Post caps, pre gauge-clamp; the counter never clamps.
	tree_lifetime[skill_id] = float(tree_lifetime.get(skill_id, 0.0)) + gained
	var cur := float(affinity.get(skill_id, 0.0))
	affinity[skill_id] = minf(100.0, cur + gained)
	print("[Affinity] %s +%.1f (%.0f/100)" % [skill_id, gained, affinity[skill_id]])
	_check_family_milestones(skill_id)
	return gained


## Grant affinity with a per-cast cap. cast_id groups hits from one cast.
func gain_affinity_capped(skill_id: String, points: float, enemy_id: int, cast_id: String, cap: float) -> float:
	var so_far := float(_affinity_cast_total.get(cast_id, 0.0))
	if so_far >= cap:
		return 0.0
	var granted := gain_affinity(skill_id, minf(points, cap - so_far), enemy_id)
	# Track pre-mult points for the cap.
	_affinity_cast_total[cast_id] = so_far + minf(points, cap - so_far)
	return granted


## Check for family milestone grants after an affinity gain.
func _check_family_milestones(skill_id: String) -> void:
	var fid := Player.family_of(skill_id)
	if fid == "":
		return
	var aff := float(affinity.get(skill_id, 0.0))
	if not family_collection.has(fid):
		family_collection[fid] = {"traits": [], "signature": false}
	var coll: Dictionary = family_collection[fid]
	var fams := Player.families()
	for milestone in [25, 50, 75]:
		if aff >= milestone and not _has_trait(coll, milestone, fams, fid):
			var tdata: Dictionary = fams[fid]["traits"][milestone]
			(coll["traits"] as Array).append(tdata["id"])
			if hud != null:
				hud.toast("Family trait earned: %s — %s" % [tdata["name"], tdata["desc"]])
				AudioManager.sfx("milestone")
	if aff >= 100.0:
		# The run-scoped unlock trips on the milestone itself, whether or
		# not the profile book already holds this signature (Jesse
		# 2026-10-27) — re-earning in a later run is silent bookkeeping.
		run_signatures[fid] = true
		if not bool(coll.get("signature", false)):
			coll["signature"] = true
			var sig: Dictionary = fams[fid]["signature"]
			if hud != null:
				hud.toast("SIGNATURE SKILL UNLOCKED: %s!" % sig["name"])


func _has_trait(coll: Dictionary, milestone: int, fams: Dictionary, fid: String) -> bool:
	var tid: String = fams[fid]["traits"][milestone]["id"]
	return tid in (coll.get("traits", []) as Array)


## True if the player has a family trait (collections persist across respecs).
func has_trait(trait_id: String) -> bool:
	for fid in family_collection:
		var coll: Dictionary = family_collection[fid]
		if trait_id in (coll.get("traits", []) as Array):
			return true
	return false


## Damage multiplier from family traits for a skill (1.1 if its family's +10% damage trait owned).
func trait_damage_mult(skill_id: String) -> float:
	var fid := Player.family_of(skill_id)
	# Only families with a direct +damage trait are listed; others return 1.0.
	var dmg_traits := {"fire": "kindled", "frost": "deep_chill", "storm": "charged",
		"precision": "true_aim"}
	if dmg_traits.has(fid) and has_trait(dmg_traits[fid]):
		# true_aim only applies to marked/revealed; handled at the hit site, not here.
		if fid == "precision":
			return 1.0
		return 1.1
	return 1.0


## True if the player has unlocked a family's signature skill.
func has_signature(sig_id: String) -> bool:
	for fid in family_collection:
		var coll: Dictionary = family_collection[fid]
		if bool(coll.get("signature", false)):
			var fams := Player.families()
			if fams.has(fid) and str(fams[fid]["signature"]["id"]) == sig_id:
				return true
	return false


## Returns the signature skill dict for a family, or {} if not unlocked
## IN THIS RUN. The gate is run_signatures (Jesse 2026-10-27): every
## consumer — mage hotbar slots, warrior/rogue cycle membership, the mage
## cast itself — routes through here, so the profile collection book alone
## never grants a usable signature at a new level.
func family_signature(fid: String) -> Dictionary:
	if not bool(run_signatures.get(fid, false)):
		return {}
	var fams := Player.families()
	if fams.has(fid):
		return fams[fid]["signature"]
	return {}
	refresh_abilities()
	if hud != null:
		hud.refresh_stats()
		hud.refresh_loadout(self)
		hud.refresh_inventory(self)
		hud.set_level(1, self)
		hud.toast("Switched to %s! Level reset to 1." % class_id.capitalize())
	AudioManager.sfx("ability_unlock")


## Issue #133: gate for the periodic sync RPCs. Firing an RPC into a
## peer that is no longer connected prints "Trying to call an RPC via
## a multiplayer peer which is not connected" every tick — after the
## host died mid-run (2026-10-14) the guest's log filled with 1,148 of
## them in ~2.5 minutes. True when there is no peer object at all
## (headless/local paths keep their pre-#133 behavior) or the peer
## reports CONNECTED (the offline peer always does, so solo is
## untouched); false only for a present-but-dead peer.
func _mp_peer_connected() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp == null or mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _physics_process(delta: float) -> void:
	# Issue #113 Phase 3: the server ticks repair channels on its own
	# copies of player nodes (validity includes alive/not-downed).
	# Issue #113 Phase 4: the server Smash cooldown ticks here too.
	if multiplayer.is_server():
		_server_repair_tick(delta)
		_server_revive_tick(delta)
		# Issue #172: the target-side pool discipline — the pool
		# zeroes the moment this node is observed not-downed on
		# the server (bleed-out, death, any exit), and its
		# fraction stays synced at the snapshot cadence while a
		# pool is live.
		if not downed:
			_srv_zero_revive_pool()
		elif _srv_revive_pool > 0.0:
			_srv_pool_sync_t += delta
			if _srv_pool_sync_t >= SNAPSHOT_INTERVAL:
				_srv_pool_sync_t = 0.0
				_srv_sync_pool_frac()
		if _srv_smash_cd > 0.0:
			_srv_smash_cd = maxf(0.0, _srv_smash_cd - delta)
		if _srv_lightning_cd > 0.0:
			_srv_lightning_cd = maxf(0.0, _srv_lightning_cd - delta)
	if downed:
		if is_multiplayer_authority():
			_tick_downed(delta)
			# Issue #163: keep the snapshot stream alive while downed —
			# downed/alive ride it, and a stream that stops at the down
			# strands every replica's flags at the fall (R1).
			_emit_snapshot(delta)
		return
	if not alive:
		if is_multiplayer_authority():
			_emit_snapshot(delta)
		return
	if is_multiplayer_authority():
		_tick_revive_channel(delta)
		_tick_repair_channel(delta)
		_tick_plant_hold(delta)
		# Issue #193: while a menu surface is up — pause,
		# inventory, cipher, destination board, the census
		# the event handlers already use — polled movement
		# reads zero: opening a menu must not walk the
		# player. The rod-cancel below eats from the same
		# vector, so a menu opening mid-session no longer
		# cancels the cast either; the bobber stays out
		# until a real move input after the menu closes.
		var menu_locked: bool = hud != null and (hud.is_paused or hud.inventory_open or hud.cipher_popup_open or hud.dest_popup_open)
		var mv := Vector2.ZERO if menu_locked else _move_vector()
		var ix := mv.x
		var iz := mv.y
		# Gilded Cage: rooted while caged.
		if _caged_t > 0.0:
			_caged_t -= delta
			ix = 0.0
			iz = 0.0
		# Issue #126 Phase 2: no more movement lock — WASD input while
		# the bobber is in the water CANCELS the session (the fisher
		# stays free and vulnerable, per the redesign). The mirror flag
		# is cleared locally at once; the server's fx_clear reconciles.
		if rod_out and _bobber_out and (ix != 0.0 or iz != 0.0):
			set_bobber_out(false) # (also clears the bite mirror)
			_director_request("request_cancel")
		# Cast charge accumulates while LMB is held in rod-out.
		if _cast_charge >= 0.0:
			_cast_charge = minf(1.0, _cast_charge + delta / 1.5)
			_apply_rod_bend()
			if hud != null and hud.has_method("set_charge_meter"):
				hud.set_charge_meter(_cast_charge, true)
		# Issue #126 Phase 3: with the rod out and no bobber down, the
		# legend's Cast / "aim at water" context follows the aim —
		# re-probe each tick and flip the legend when it changes.
		if rod_out and not _bobber_out and hud != null:
			var ls := legend_state()
			if ls != _rod_legend_cache:
				_rod_legend_cache = ls
				click_state_changed.emit()
		# Issue #144 Phase 1 (Q2): right-stick look — rate-based and
		# focus-gated like the mouse path, sensitivity / deadzone /
		# invert-Y from the settings phase.
		var lk := Input.get_vector("look_left", "look_right", "look_up", "look_down", look_deadzone_setting())
		if lk != Vector2.ZERO and not menu_locked and gameplay_focused() and (hud == null or not hud.is_paused):
			var lsens := look_sens_setting()
			_yaw -= lk.x * LOOK_STICK_RATE * lsens * delta
			var pd := -lk.y * LOOK_STICK_RATE * lsens * delta
			if look_invert_y_setting():
				pd = -pd
			_pitch = clampf(_pitch + pd, -1.2, 1.2)
			rotation.y = _yaw
			if _camera != null:
				_camera.rotation.x = _pitch
		var wish := Vector3(ix, 0, iz)
		if wish.length() > 1.0:
			wish = wish.normalized()
		var move_vec: Vector3 = global_transform.basis * wish
		move_vec.y = 0.0
		_dash_cd = maxf(0.0, _dash_cd - delta)
		_warhorn_t = maxf(0.0, _warhorn_t - delta)
		_stoneskin_t = maxf(0.0, _stoneskin_t - delta)
		if _reinforce_t > 0.0:
			_reinforce_t = maxf(0.0, _reinforce_t - delta)
			if _reinforce_t <= 0.0:
				_update_reinforce_shell()
		_rally_t = maxf(0.0, _rally_t - delta)
		_shared_vitality_t = maxf(0.0, _shared_vitality_t - delta)
		_war_drums_t = maxf(0.0, _war_drums_t - delta)
		_sanctuary_t = maxf(0.0, _sanctuary_t - delta)
		# Stealth expires.
		if _stealth_t > 0.0:
			_stealth_t -= delta
			if _stealth_t <= 0.0 and stealthed:
				stealthed = false
				# Issue #210 (Veilwalker): EXITING the veil
				# opens the 4 s damage window.
				if _tree_behavior_pct("veilwalker") > 0.0:
					_tree_veil_until = Time.get_ticks_msec() + 4000
				if _mp_peer_connected():
					rpc("set_stealthed", false)
				# Unseen trait: first attack after the veil ends crits.
				if has_trait("unseen"):
					unseen_crit_ready = true
		# Ability cooldowns tick.
		var expired := []
		for id in ability_cds:
			ability_cds[id] = maxf(0.0, float(ability_cds[id]) - delta)
			if ability_cds[id] <= 0.0:
				expired.append(id)
		for id in expired:
			ability_cds.erase(id)
		if not expired.is_empty() and hud != null:
			hud.refresh_abilities(self)
		if _dash_t > 0.0:
			_dash_t -= delta
			velocity.x = _dash_dir.x * DASH_SPEED
			velocity.z = _dash_dir.z * DASH_SPEED
			# FOV kick while dashing.
			if _camera != null:
				_camera.fov = lerpf(_camera.fov, _base_fov() + 7.0, delta * 12.0)
		else:
			# Issue #210 slice B5 (spec section 3):
			# Second Wind folds where move_speed is
			# consumed — below 25% HP, +X% move speed.
			var spd := _buff_mult("speed")
			if hp < max_hp * 0.25:
				spd *= 1.0 + _tree_behavior_pct(
					"second_wind") / 100.0
			velocity.x = move_vec.x * move_speed * spd
			velocity.z = move_vec.z * move_speed * spd
			if _camera != null:
				_camera.fov = lerpf(_camera.fov, _base_fov(), delta * 8.0)
		if _jump_queued:
			_jump_queued = false
			if is_on_floor():
				velocity.y = JUMP_VELOCITY
				AudioManager.sfx("jump")
		var fall_speed := -velocity.y
		if is_on_floor():
			if velocity.y <= 0.0:
				velocity.y = -0.5
		else:
			velocity.y -= GRAVITY * delta
		move_and_slide()
		# Landing thud scaled by fall speed.
		if not _was_on_floor and is_on_floor():
			AudioManager.sfx("land", null, 1.0, clampf(fall_speed / 12.0, 0.25, 1.0))
			if fall_speed > 6.0:
				Effects.burst(get_parent(), global_position + Vector3(0, 0.2, 0), Color(0.7, 0.65, 0.6), 14, 4.0)
		_was_on_floor = is_on_floor()
		# Footsteps while moving on the ground.
		var h_speed := Vector2(velocity.x, velocity.z).length()
		if is_on_floor() and h_speed > 1.5:
			_step_timer -= delta * h_speed
			if _step_timer <= 0.0:
				_step_timer = 4.5
				AudioManager.sfx("footstep", null, randf_range(0.9, 1.1), 0.45)
		else:
			_step_timer = 0.0
		_cooldown = maxf(0.0, _cooldown - delta)
		_dagger_catch_cd = maxf(0.0, _dagger_catch_cd - delta)
		# Issue #69 Phase 1: charge the dagger while RMB held (0→1 over 0.8s).
		if _charging:
			_dagger_charge = minf(1.0, _dagger_charge + delta * atk_spd_mult() / DAGGER_CHARGE_TIME)
			if hud != null and hud.has_method("set_charge_meter"):
				hud.set_charge_meter(_dagger_charge, true)
		_update_pickup_prompt()
		_emit_snapshot(delta)
	else:
		_refresh_puppet_presentation()
		if _has_remote:
			global_position = global_position.lerp(_remote_pos, clampf(delta * 10.0, 0.0, 1.0))
			# Issue #72 Phase 1: interpolate yaw (short-way, no snapping).
			_yaw = lerp_angle(_yaw, _remote_yaw, clampf(delta * 10.0, 0.0, 1.0))
			# Issue #72 Phase 2: remote peers yaw the sprite to synced facing.
			if _sprite != null:
				_sprite.rotation.y = _yaw
				# Back-sprite integration: front/back follows the same
				# replicated yaw, judged against this peer's camera.
				_update_sprite_presentation()
			# Issue #141: the held-prop holder yaws with the same synced
			# facing — without this write the props keep their build-time
			# orientation while the sprite turns underneath them.
			if _held_prop != null:
				_held_prop.rotation.y = _yaw


func _process(delta: float) -> void:
	# Jesse 2026-10-11: update FPS placement ghost while placing.
	if _placing_type != "" and is_multiplayer_authority():
		_command_update_ghost()
	# Issue #165 (F2): FPS command-mode upkeep (aim + cursor rule).
	if _command_mode and is_multiplayer_authority():
		_command_process()
	# Downed marker pulse (runs on every peer's instance).
	if _downed_marker != null and _downed_marker.visible:
		var t := Time.get_ticks_msec() / 1000.0
		var s := 1.0 + 0.18 * sin(t * 6.0)
		_downed_marker.scale = Vector3.ONE * s
	if is_multiplayer_authority():
		_hl_process(delta)
		if _reading_board != null:
			_update_board_hover()
			# Walking away from the board steps out of reading mode.
			if not is_instance_valid(_reading_board) or \
					_reading_board.global_position.distance_to(global_position) > 4.0:
				exit_reading()
		if _streak_timer > 0.0:
			_streak_timer -= delta
			if _streak_timer <= 0.0:
				_streak_kills = 0
		# Issue #17 Phase 2: screen shake gated by profile setting.
		var shake_on := true
		if has_node("/root/SaveManager"):
			shake_on = bool(get_node("/root/SaveManager").get_profile_setting("settings", "shake_enabled", true))
		if _camera != null and _shake > 0.0 and shake_on:
			_shake -= delta
			var s := _shake * 0.3
			_camera.position = _cam_base + Vector3(randf_range(-s, s), randf_range(-s, s), 0.0)
			if _shake <= 0.0:
				_camera.position = _cam_base
		elif _camera != null and not shake_on:
			_camera.position = _cam_base
		_ping_cd = maxf(0.0, _ping_cd - delta)
		_check_buff_expiry()
	else:
		_bob_t += delta
		if alive:
			_sprite.position.y = 1.0 + sin(_bob_t * 2.2) * 0.04


# --- Combat ---

## Shift dash: burst of speed in the current move direction (or facing
## if standing still), with i-frames for the dash duration.
func _try_dash() -> void:
	if _dash_cd > 0.0 or _dash_t > 0.0:
		return
	var mv := _move_vector()
	var ix := mv.x
	var iz := mv.y
	var wish := Vector3(ix, 0, iz)
	if wish.length() < 0.1:
		wish = Vector3(0, 0, -1)  # dash forward when standing still
	_dash_dir = (global_transform.basis * wish.normalized())
	_dash_dir.y = 0.0
	_dash_dir = _dash_dir.normalized()
	_dash_t = DASH_TIME
	_dash_cd = DASH_COOLDOWN
	AudioManager.sfx("dash")
	Effects.burst(get_parent(), global_position + Vector3(0, 0.5, 0), Color(0.85, 0.9, 1.0), 10, 3.0)
	if hud != null:
		hud.flash_dash()


func _do_attack() -> void:
	# Issue #69 Phase 2: melee disabled while the dagger is out.
	if class_id == "rogue" and _dagger_out:
		return
	# War Drums: +10% attack speed while the trait buff is active.
	# Issue #184: ATK SPD divides at this reset site, fresh per swing.
	_cooldown = attack_cooldown / (1.1 if _war_drums_t > 0.0 else 1.0) / atk_spd_mult()
	_attack_anim()
	if class_id == "mage":
		_cast_spell()
		return
	if class_id == "architect":
		_cast_architect_ability()
		return
	AudioManager.sfx("swing")
	var from := int(multiplayer.get_unique_id())
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# Unseen trait: first attack after veil/blink crits for 2x.
	# Issue #210 slice B5: the universal basic-attack fold.
	var melee_dmg := damage * _buff_mult("damage") \
		* _tree_skill_mod("basic_attack", "dmg_mult", 1.0)
	if unseen_crit_ready:
		melee_dmg *= 2.0
		unseen_crit_ready = false
		Effects.burst(get_parent(), global_position + Vector3(0, 1.2, 0), Color(1.0, 0.9, 0.4), 15, 4.0)
	for node in get_tree().get_nodes_in_group("mobs"):
		var mob := node as Mob
		if mob == null or not mob.alive:
			continue
		var to_mob: Vector3 = mob.global_position - global_position
		to_mob.y = 0.0
		var dist := to_mob.length()
		if dist > attack_range or dist < 0.001:
			continue
		if fwd.angle_to(to_mob / dist) > 0.75:
			continue
		# Issue #210 slice B5: Wayfarer's Edge — +50%
		# against full-health targets, read per target.
		var dealt := melee_dmg
		if tree_wayfarers_edge() and mob.hp >= mob.max_hp:
			dealt *= 1.5
		if multiplayer.is_server():
			mob.take_damage(dealt, from, global_position)
		else:
			mob.rpc_id(NetworkManager.server_peer_id, "take_damage", dealt, from, global_position)
		# Affinity: hit on marked target → +1 mark, per-enemy 5s cd.
		if mob.is_marked():
			gain_affinity("mark", 1.0, mob.get_instance_id())
	# RTS: damage enemy units and buildings in the Warlord's Domain.
	if rts_faction >= 0:
		_damage_rts_targets(fwd, from)


## Issue #69 Phase 1: Throw the dagger at current charge.
## Range: 6m (tap) → 16m (full). Damage: 0.6x → 1.4x dagger hit.
func _throw_dagger() -> void:
	# Issue #69 Phase 2: can't throw while dagger is out or on catch cooldown.
	if _dagger_out or _dagger_catch_cd > 0.0:
		return
	_charging = false
	var charge := clampf(_dagger_charge, 0.0, 1.0)
	_dagger_charge = 0.0
	if hud != null and hud.has_method("set_charge_meter"):
		hud.set_charge_meter(0.0, false)
	_dagger_out = true
	_cooldown = 0.5  # Brief recovery after throw.
	_attack_anim()
	var from := int(multiplayer.get_unique_id())
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var throw_range := lerpf(DAGGER_RANGE_MIN, DAGGER_RANGE_MAX, charge)
	var throw_dmg := damage * lerpf(DAGGER_DMG_MIN, DAGGER_DMG_MAX, charge) * _buff_mult("damage") * _tree_skill_mod("basic_attack", "dmg_mult", 1.0)
	# Unseen crit applies.
	if unseen_crit_ready:
		throw_dmg *= 2.0
		unseen_crit_ready = false
	AudioManager.sfx("dagger_throw")
	var spawn_pos := global_position + Vector3(0, 1.4, 0) + fwd * 0.8
	var dagger_vel := fwd * 24.0
	# SteamMultiplayerPeer can't rpc_id its own peer ID: when this instance is
	# the server, call directly (same outcome — the handler is call_local).
	if multiplayer.is_server():
		_request_dagger_spawn(spawn_pos, dagger_vel, throw_dmg, from, throw_range)
	else:
		rpc_id(NetworkManager.server_peer_id, "_request_dagger_spawn", spawn_pos, dagger_vel, throw_dmg, from, throw_range)


@rpc("any_peer", "call_local")
func _request_dagger_spawn(pos: Vector3, vel: Vector3, dmg: float, owner: int, range_m: float) -> void:
	if not multiplayer.is_server():
		return
	var dagger := ThrownDagger.new()
	dagger.setup(vel, dmg, owner, range_m)
	get_parent().add_child(dagger)
	dagger.global_position = pos


## Issue #69 Phase 2: Dagger started returning (for HUD/Fan lockout feedback).
func _on_dagger_returning() -> void:
	pass  # _dagger_out already true; HUD could show "returning" here.


## Issue #69 Phase 2: Dagger caught. 1.2s cooldown before next throw.
@rpc("any_peer", "call_local")
func _on_dagger_caught() -> void:
	_dagger_out = false
	_dagger_catch_cd = DAGGER_CATCH_COOLDOWN / atk_spd_mult()
	AudioManager.sfx("dagger_catch")


func _damage_rts_targets(fwd: Vector3, from: int) -> void:
	var dmg := damage * _buff_mult("damage")
	for node in get_tree().get_nodes_in_group("rts_units"):
		if int(node.get("faction")) == rts_faction:
			continue
		if not bool(node.get("alive")):
			continue
		var to: Vector3 = node.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist > attack_range or dist < 0.001:
			continue
		if fwd.angle_to(to / dist) > 0.75:
			continue
		if multiplayer.is_server():
			node.rpc_take_damage(dmg, multiplayer.get_unique_id())
		else:
			node.rpc_id(NetworkManager.server_peer_id, "rpc_take_damage", dmg,
				multiplayer.get_unique_id())
	for node in get_tree().get_nodes_in_group("rts_buildings"):
		if int(node.get("faction")) == rts_faction:
			continue
		var to: Vector3 = node.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist > attack_range + 1.0 or dist < 0.001:
			continue
		if fwd.angle_to(to / dist) > 0.75:
			continue
		if multiplayer.is_server():
			node.rpc_take_damage(dmg, multiplayer.get_unique_id())
		else:
			node.rpc_id(NetworkManager.server_peer_id, "rpc_take_damage", dmg,
				multiplayer.get_unique_id())



## Echoes (issue #9 Phase 2): log an ability cast to the recorder.
## Runtime autoload lookup avoids compile-time dependencies.
func _notify_echo_ability(ability_id: String) -> void:
	var rec: Node = get_tree().root.get_node_or_null("EchoRecorder")
	if rec != null:
		rec.call("record_ability", ability_id)


func _cast_spell() -> void:
	# Echo recording (issue #9 Phase 2): log the cast. No-op when not recording.
	_notify_echo_ability(_selected_ability_id())
	match _selected_ability_id():
		"frost":
			AudioManager.sfx("frost_cast")
			_cast_frost_shard()
		"lightning":
			AudioManager.sfx("lightning_cast")
			_cast_chain_lightning()
		"meteor":
			AudioManager.sfx("meteor_cast")
			_cast_meteor()
		"barrage":
			AudioManager.sfx("barrage_cast")
			_cast_barrage()
		"blizzard":
			AudioManager.sfx("blizzard_cast")
			_cast_blizzard()
		"holy_light":
			AudioManager.sfx("holy_light_cast")
			_cast_holy_light()
		_:
			AudioManager.sfx("fireball_cast")
			_cast_fireball()


## Architect: Q/1-6 select, left-click places/casts (mage input pattern).
## The Architect has no basic attack — the turret is the level-1 damage.
var _structure_seq := 0


func _cast_architect_ability() -> void:
	# Echo recording (issue #9 Phase 2): log the cast. No-op when not recording.
	_notify_echo_ability(_selected_ability_id())
	match _selected_ability_id():
		"sentry_turret", "bulwark_wall", "spike_trap", "keystone":
			_place_structure(_selected_ability_id())
		"reinforce":
			_cast_reinforce()
		"demolish":
			_cast_demolish()
		"hammer_smash":
			_cast_hammer_smash()


## Cursor raycast onto the ground (blizzard pattern).
func _cursor_ground_point() -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var target := from + dir * 20.0
	var params := PhysicsRayQueryParameters3D.create(from, target)
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(params)
	var point: Vector3 = hit["position"] if not hit.is_empty() else target
	point.y = maxf(point.y, 0.1)
	return point


func _place_structure(structure_id: String) -> void:
	var cds := {"sentry_turret": 12.0, "bulwark_wall": 8.0, "spike_trap": 10.0, "keystone": 30.0}
	var cd: float = cds.get(structure_id, 10.0)
	if float(ability_cds.get(structure_id, 0.0)) > 0.0:
		if hud != null:
			hud.toast("Still recharging!")
		AudioManager.sfx("ui_error")
		return
	# Per-type caps, checked locally for instant feedback (dungeon enforces too).
	var me := int(multiplayer.get_unique_id())
	var same := 0
	for n in get_tree().get_nodes_in_group("structures"):
		var s := n as Structure
		if s != null and s.owner_peer == me and not s.is_queued_for_deletion() \
				and s.structure_id == structure_id:
			same += 1
	if structure_id == "spike_trap" and same >= 3:
		if hud != null:
			hud.toast("Trap limit reached (3)!")
		AudioManager.sfx("ui_error")
		return
	if structure_id == "keystone" and same >= 1:
		if hud != null:
			hud.toast("Only one keystone!")
		AudioManager.sfx("ui_error")
		return
	var point := _cursor_ground_point()
	ability_cds[structure_id] = (cd) * cooldown_mult() \
		* _tree_skill_mod(structure_id, "cd_mult", 1.0)
	_structure_seq += 1
	var uid := "%d_%d" % [me, _structure_seq]
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null:
		dungeon.rpc("place_structure", structure_id, point, me, ability_rank(), uid)
	if hud != null:
		hud.refresh_abilities(self)


## Reinforce: stone shell on the ally nearest the cursor (or self).
func _cast_reinforce() -> void:
	if float(ability_cds.get("reinforce", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Reinforce on cooldown!")
		return
	var point := _cursor_ground_point()
	var best: Player = null
	var best_d := 3.0
	for n in get_tree().get_nodes_in_group("players"):
		if n == self:
			continue
		var p := n as Player
		if p == null or not p.alive:
			continue
		var to: Vector3 = p.global_position - point
		to.y = 0.0
		if to.length() < best_d:
			best_d = to.length()
			best = p
	ability_cds["reinforce"] = (25.0) * cooldown_mult() \
		* _tree_skill_mod("reinforce", "cd_mult", 1.0)
	# Issue #210 (Tempered): the 5 s window arms at the
	# cast, whatever the shell's target.
	_tree_tempered_until = Time.get_ticks_msec() + 5000
	AudioManager.sfx("totem_place")
	var target: Player = best if best != null else self
	# Issue #169: when the target's authority is THIS peer (a
	# self-target — the common case), rpc_id would be self-addressed
	# and a Steam peer cannot rpc_id its own id (the #165 D1
	# family): the reinforce silently never landed. Call directly.
	# Issue #210: shell_pct scales the shell's strength
	# (its 0.5 base) at the apply site.
	var shell := 0.5 * (1.0 + _tree_skill_mod("reinforce",
		"shell_pct", 0.0))
	if int(target.get_multiplayer_authority()) == int(multiplayer.get_unique_id()):
		target.apply_reinforce(6.0, shell)
	else:
		target.rpc_id(target.get_multiplayer_authority(), "apply_reinforce", 6.0, shell)
	if hud != null:
		hud.refresh_abilities(self)


## Demolish: detonate every owned structure for 50% of its max HP as AoE.
func _cast_demolish() -> void:
	if float(ability_cds.get("demolish", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Demolish on cooldown!")
		return
	var me := int(multiplayer.get_unique_id())
	var mine := 0
	for n in get_tree().get_nodes_in_group("structures"):
		var s := n as Structure
		if s != null and s.owner_peer == me and not s.is_queued_for_deletion():
			mine += 1
	if mine == 0:
		if hud != null:
			hud.toast("No structures to demolish!")
		AudioManager.sfx("ui_error")
		return
	ability_cds["demolish"] = (45.0) * cooldown_mult() \
		/ atk_spd_mult() * _tree_skill_mod("demolish",
			"cd_mult", 1.0)
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null:
		dungeon.rpc("demolish_structures", me)
	if hud != null:
		hud.refresh_abilities(self)


## Hammer Smash (issue #113 Phase 4): the Forge Hammer's AOE ability —
## the hammer grants NO melee swing; this ability is its only offense.
## Client side: gate on the hammer being equipped (fishing-gate
## pattern), mirror the cooldown for the HUD, and send a cast INTENT.
## The damage value rides the intent, computed from the caster's local
## stats exactly like Fan of Knives / the mage spells (the snapshot
## does not replicate damage/buffs, so the server cannot recompute
## it); the server validates everything else and applies the hit.
func _cast_hammer_smash() -> void:
	if not has_hammer_equipped():
		if hud != null:
			hud.toast("Requires Forge Hammer — equip it to Smash!")
		AudioManager.sfx("ui_error")
		return
	if float(ability_cds.get("hammer_smash", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Hammer Smash on cooldown!")
		AudioManager.sfx("ui_error")
		return
	ability_cds["hammer_smash"] = SMASH_COOLDOWN * cooldown_mult() / atk_spd_mult() * _tree_skill_mod("hammer_smash", "cd_mult", 1.0)
	var dmg := damage * _buff_mult("damage") * rank_mult() * SMASH_DAMAGE_MULT * _tree_mult("hammer_smash")
	# Issue #210 (Tempered + Aegis Shell at the cast
	# expression).
	if Time.get_ticks_msec() < _tree_tempered_until:
		dmg *= 1.0 + _tree_behavior_pct("tempered") / 100.0
	if tree_aegis_active():
		dmg *= 1.25
	if multiplayer.is_server():
		request_hammer_smash(dmg)
	else:
		rpc_id(NetworkManager.server_peer_id, "request_hammer_smash", dmg)
	if hud != null:
		hud.refresh_abilities(self)


## Server Smash endpoint: validates the intent (sender is this node's
## authority, architect, Forge Hammer in the WEAPON slot via the
## replicated equipped_ids, alive, server cooldown ready), picks the
## target set from the server copy's position, and applies damage +
## stun server-side. FX broadcast only on a validated cast.
@rpc("any_peer", "call_local")
func request_hammer_smash(claimed_damage: float) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	if not alive or downed or class_id != "architect" or not has_hammer_equipped():
		return
	if _srv_smash_cd > 0.0 or claimed_damage <= 0.0:
		return
	# Issue #188 (F1): the enforced cooldown takes the caster's
	# cooldown_mult like every other cooldown in the game —
	# this server copy holds the caster's equipped special, so
	# the factor is evaluated HERE, on the enforcing node, and
	# the HUD mirror's multiplied value becomes the truth.
	_srv_smash_cd = SMASH_COOLDOWN * cooldown_mult() / atk_spd_mult() * _tree_skill_mod("hammer_smash", "cd_mult", 1.0)
	var attacker := int(get_multiplayer_authority())
	for n in get_tree().get_nodes_in_group("mobs"):
		var m := n as Mob
		if m == null or not m.alive:
			continue
		if m.global_position.distance_to(global_position) <= SMASH_RADIUS:
			m.take_damage(claimed_damage, attacker, global_position)
			if m.alive:
				m.apply_stun(SMASH_STUN_TIME)
	# Issue #210 (Seismic Smash): a ring at 50% damage
	# beyond the smash's own area, damage only.
	if _tree_variant("hammer_smash") == "seismic_smash":
		for n in get_tree().get_nodes_in_group("mobs"):
			var rm := n as Mob
			if rm == null or not rm.alive:
				continue
			var rd := rm.global_position.distance_to(
				global_position)
			if rd > SMASH_RADIUS and rd <= SMASH_RADIUS * 1.5:
				rm.take_damage(claimed_damage * 0.5,
					attacker, global_position)
	rpc("hammer_smash_fx", global_position)


@rpc("any_peer", "call_local")
func hammer_smash_fx(pos: Vector3) -> void:
	Effects.burst(get_parent(), pos + Vector3(0, 0.4, 0), Color(0.85, 0.6, 0.3), 26, 5.5)
	Effects.burst(get_parent(), pos + Vector3(0, 0.15, 0), Color(0.55, 0.45, 0.35), 18, 4.0)
	AudioManager.sfx("hammer_smash", pos)


## Holy Light: bathes the map in radiant light for 10s and gently heals the
## caster + nearby allies (15% max HP, 15m). 20s cooldown. No damage.
const HOLY_LIGHT_HEAL_RADIUS := 15.0
const HOLY_LIGHT_HEAL_FRAC := 0.15
## Issue #91 Phase 1: Holy Light v2 arm/charge/strike state machine.
## Timing: 1.0s charge + 10s hold + 2s wind-down = 13s total. Cooldown (20s)
## starts at STRIKE, not at arm. Arming/disarming/cancelling is free.
const HL_CHARGE_TIME := 1.0
const HL_HOLD_TIME := 10.0
const HL_WINDDOWN_TIME := 2.0
const HL_COOLDOWN := 20.0
## Jesse 2026-10-10: after the ability ends, the beam lingers as a healing
## zone for 15s, slowly fading. Turned the "beam never cleans up" bug into
## a feature.
const HL_LINGER_TIME := 15.0
const HL_AIM_RANGE := 25.0
enum HLState { IDLE, ARMED, CHARGING, ACTIVE }
## Issue #95 Phase 2: setter emits click_state_changed so the mouse legend
## re-renders live. Only emits on actual change (no per-frame spam).
var _hl_state: int = HLState.IDLE:
	set(v):
		if _hl_state == v:
			return
		_hl_state = v
		click_state_changed.emit()
var _hl_aim := Vector3.ZERO
var _hl_charge_t := 0.0
var _hl_active_t := 0.0
var _hl_reticle: MeshInstance3D = null
var _hl_beam_root: Node3D = null
## Issue #91 Phase 2: active beams by owner peer ID. Issue #171:
## beams are PER-CAST — each owner's value is a LIST of beam
## entries, one per cast: {node, aim, target_aim, beam_mesh,
## light, rings, tick_t, owner, seq}. Overlapping beams coexist
## (Holy Light stacks); every lookup addresses an entry by its
## spawn sequence, and a stale seq is a no-op.
var _hl_beams := {}
## Issue #162: per-instance spawn sequence for unique beam-root
## names. Issue #171: allocated by the striker at strike time
## and passed through the spawn RPC, so the sequence — and
## therefore the beam root name HolyLightBeam_<owner>_<seq> —
## is identical on every peer by construction.
var _hl_spawn_seq := 0
## Issue #171: the seq of this peer's currently ACTIVE beam
## (steering and wind-down address it; lingering beams carry
## their own seqs and are never the steering target).
var _hl_active_seq := 0


## Issue #171: find one beam entry by (owner, seq); an empty
## dictionary when absent.
func _hl_find_beam(owner_id: int, seq: int) -> Dictionary:
	var list: Array = _hl_beams.get(owner_id, [])
	for b in list:
		if int((b as Dictionary).get("seq", 0)) == seq:
			return b
	return {}


## Issue #171: this peer's ACTIVE beam entry ({} when none).
func _hl_active_beam() -> Dictionary:
	return _hl_find_beam(int(multiplayer.get_unique_id()), _hl_active_seq)
## Issue #91 Phase 2: 10Hz aim update timer (owner -> server, unreliable).
var _hl_aim_send_t := 0.0

## Issue #91 Phase 1: per-frame update for the arm/charge/active state machine.
## Only the owning client runs this (visual + timing; server handles damage).
func _hl_process(delta: float) -> void:
	# Issue #91 Phase 2: all peers lerp remote beams toward target aim.
	_hl_update_beam_visuals(delta)
	# Issue #162: the damage/heal tick is NOT run here anymore — it is
	# server-owned (the dungeon's server process ticks every player's
	# registry via server_tick_holy_light). It used to run only inside
	# the caster's authority process, which never executes on the
	# server for a client-caster, leaving client beams inert.
	if _hl_state == HLState.IDLE:
		return
	if _hl_state == HLState.ARMED or _hl_state == HLState.CHARGING:
		# Aim tracks the cursor live.
		_hl_aim = _hl_ground_aim()
		if _hl_reticle != null and is_instance_valid(_hl_reticle):
			_hl_reticle.global_position = _hl_aim + Vector3(0, 0.15, 0)
			if _hl_state == HLState.CHARGING:
				# Reticle pulses and tightens during charge.
				var p := 1.0 - (_hl_charge_t / HL_CHARGE_TIME) * 0.3
				var pulse := 1.0 + 0.1 * sin(Time.get_ticks_msec() / 1000.0 * 12.0)
				_hl_reticle.scale = Vector3.ONE * p * pulse
	if _hl_state == HLState.CHARGING:
		_hl_charge_t += delta
		if _hl_charge_t >= HL_CHARGE_TIME:
			_hl_strike()
	elif _hl_state == HLState.ACTIVE:
		_hl_active_t += delta
		# Issue #91 Phase 2: owner steers the beam; aim tracks cursor live.
		# Issue #171: steering addresses the ACTIVE seq only — a
		# lingering beam from an earlier cast is never steered.
		_hl_aim = _hl_ground_aim()
		var beam := _hl_active_beam()
		if not beam.is_empty():
			var node: Node3D = beam.get("node")
			if node != null and is_instance_valid(node):
				node.global_position = _hl_aim
			beam["aim"] = _hl_aim
			beam["target_aim"] = _hl_aim
		# 10Hz aim updates to server (unreliable).
		_hl_aim_send_t += delta
		if _hl_aim_send_t >= 0.1:
			_hl_aim_send_t = 0.0
			if multiplayer.is_server():
				hl_aim_update(_hl_aim, _hl_active_seq)
			elif _mp_peer_connected():
				# Issue #133: same dead-peer class as push_snapshot —
				# 10 Hz aim updates must not fire into a dead peer.
				rpc_id(NetworkManager.server_peer_id, "hl_aim_update", _hl_aim, _hl_active_seq)
		# Wind-down: beam narrows and dims.
		if _hl_active_t >= HL_HOLD_TIME:
			_hl_winddown(delta)
		if _hl_active_t >= HL_HOLD_TIME + HL_WINDDOWN_TIME:
			_hl_state = HLState.IDLE
			_hl_active_t = 0.0
			# Jesse 2026-10-10: don't just abandon the beam — it lingers
			# as a fading heal zone for 15s (was a bug, now a feature).
			_hl_start_linger()
	# Jesse 2026-10-10: lingering beams fade over 15s, then clean up.
	_hl_process_linger(delta)


## Issue #91 Phase 2: lerp all beam visuals toward their target aim points.
## Owner moves directly (set in _hl_process); remotes lerp for smoothness.
func _hl_update_beam_visuals(delta: float) -> void:
	var my_id := int(multiplayer.get_unique_id())
	for owner_id in _hl_beams.keys():
		if owner_id == my_id:
			continue  # Owner moves directly.
		for beam in _hl_beams[owner_id]:
			var node: Node3D = beam.get("node")
			if node == null or not is_instance_valid(node):
				continue
			var target: Vector3 = beam.get("target_aim", beam.get("aim"))
			node.global_position = node.global_position.lerp(target, clampf(delta * 8.0, 0.0, 1.0))


## Issue #91 Phase 2: wind-down — beam narrows and dims, decay SFX.
func _hl_winddown(delta: float) -> void:
	var beam := _hl_active_beam()
	if beam.is_empty():
		return
	# Play decay SFX once at wind-down start.
	if not bool(beam.get("winddown_sfx", false)):
		beam["winddown_sfx"] = true
		AudioManager.sfx("holy_light_decay", _hl_aim)
	var wind_t := _hl_active_t - HL_HOLD_TIME
	var frac := clampf(wind_t / HL_WINDDOWN_TIME, 0.0, 1.0)
	# Beam narrows.
	var beam_mesh_node: Variant = beam.get("beam_mesh")
	if beam_mesh_node != null and is_instance_valid(beam_mesh_node):
		var beam_mesh := beam_mesh_node as MeshInstance3D
		if beam_mesh != null:
			var s := 1.0 - frac * 0.7
			beam_mesh.scale = Vector3(s, 1.0, s)
	# Light dims (tween also handles this; this is for the beam mesh).
	# Jesse 2026-10-11: fetch as Variant first — assigning a freed instance
	# to a typed var throws before is_instance_valid can run.
	var light_node: Variant = beam.get("light")
	if light_node != null and is_instance_valid(light_node):
		var light := light_node as SpotLight3D
		if light != null:
			light.light_energy = 12.0 * (1.0 - frac)
	# Rings dissolve upward.
	var rings: Array = beam.get("rings", [])
	for i in range(rings.size()):
		var ring_node: Variant = rings[i]
		if ring_node != null and is_instance_valid(ring_node):
			var ring := ring_node as MeshInstance3D
			if ring == null:
				continue
			ring.position.y += delta * (2.0 + float(i))
			var mat := ring.material_override as StandardMaterial3D
			if mat != null:
				var c := mat.albedo_color
				c.a = 0.7 * (1.0 - frac)
				mat.albedo_color = c


## Issue #162: public entry for the server-owned tick — the dungeon's
## server process calls this on EVERY player each frame, so beams are
## ticked regardless of which seat cast them.
func server_tick_holy_light(delta: float) -> void:
	_hl_server_tick(delta)


## Issue #91 Phase 2: server runs 0.5s damage/heal ticks at the latest aim.
## Jesse 2026-10-10: lingering beams (post-ability heal zone) heal but no
## longer damage.
func _hl_server_tick(delta: float) -> void:
	# Issue #171: EVERY live entry ticks — overlapping beams
	# stack their damage/heal per tick by design; there is no
	# stacking code, the iteration is the stacking.
	for owner_id in _hl_beams.keys():
		for beam in _hl_beams[owner_id]:
			var tick_t := float(beam.get("tick_t", 0.0)) + delta
			if tick_t < 0.5:
				beam["tick_t"] = tick_t
				continue
			beam["tick_t"] = 0.0
			var aim: Vector3 = beam.get("aim", Vector3.ZERO)
			var lingering := bool(beam.get("lingering", false))
			# Issue #210 slice B5: Dawnbringer — a
			# lingering zone whose caster owns the
			# variant keeps ticking (damage AND heal)
			# at half rate for its first 4 s.
			var dawn := bool(beam.get("dawn", false)) \
				and float(beam.get("linger_t", 0.0)) < 4.0
			if not lingering or dawn:
				# Damage: 1.0x mage base per tick in the 4m beam column.
				var dmg := _hl_beam_damage()
				if dawn:
					dmg *= 0.5
				for n in get_tree().get_nodes_in_group("mobs"):
					var mob := n as Mob
					if mob == null or not bool(mob.get("alive")):
						continue
					var flat := Vector2(mob.global_position.x - aim.x, mob.global_position.z - aim.z)
					if flat.length() <= 4.0:
						mob.take_damage(dmg, owner_id, aim)
			# Heal: 15% max HP to allies within 15m of the beam point.
			for n in get_tree().get_nodes_in_group("players"):
				var p := n as Player
				if p == null or not bool(p.get("alive")):
					continue
				if p.global_position.distance_to(aim) <= HOLY_LIGHT_HEAL_RADIUS:
					var heal_amount := float(p.get("max_hp")) * HOLY_LIGHT_HEAL_FRAC * (1.0 + _tree_skill_mod("holy_light", "heal_pct", 0.0))
					if dawn:
						heal_amount *= 0.5
					# Issue #162 routing audit: when the heal target's
					# authority is THIS peer (the host healing himself),
					# rpc_id would be self-addressed — a Steam peer cannot
					# rpc_id its own id (the #165 D1 family), so the heal
					# silently never landed. Call directly on this peer,
					# exactly like the no-peer case.
					if multiplayer.multiplayer_peer == null or int(p.get_multiplayer_authority()) == int(multiplayer.get_unique_id()):
						p.call("heal", heal_amount)
					else:
						p.rpc_id(int(p.get_multiplayer_authority()), "heal", heal_amount)


## Issue #91 Phase 2: beam damage per 0.5s tick (1.0x mage base).
func _hl_beam_damage() -> float:
	# Mage base damage; non-mages use their own base.
	# Issue #210 slice B5: holy_light's modifiers live in
	# the universal branch (familyless, spec section 3).
	return damage * _buff_mult("damage") \
		* _tree_mult("holy_light")


## Issue #91 Phase 1: 7 arms/disarms Holy Light (no longer instant-cast).
## Arming is free; the 20s cooldown starts at STRIKE, not at arm.
func _cast_holy_light() -> void:
	if _hl_state == HLState.ARMED or _hl_state == HLState.CHARGING:
		_hl_disarm()
		return
	if _hl_state != HLState.IDLE:
		return
	if float(ability_cds.get("holy_light", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Holy Light on cooldown!")
		return
	_hl_arm()


## Issue #95 Phase 2: current mouse-legend state for the HUD. Data-driven —
## the MouseLegend registry is keyed by (state, class_id), so new states
## (or classes) are new data rows, never UI code changes.
func legend_state() -> String:
	if _charging and class_id == "rogue":
		return "charging"
	if _hl_state == HLState.CHARGING:
		return "hl_charging"
	if _hl_state == HLState.ARMED:
		return "hl_armed"
	# Issue #126 Phase 3: rod-out legend contexts. The bite and bobber
	# mirrors come from the fishing director; with no bobber out, an
	# aim probe at a mid charge decides Cast vs "aim at water".
	if rod_out:
		if _bite_ready:
			return "fishing_hook"
		if _bobber_out:
			return "fishing_wait"
		var d := _fishing_director()
		if d != null and d.has_method("is_fishable_at") \
				and bool(d.call("is_fishable_at", _cast_landing(0.5))):
			return "fishing_ready"
		return "fishing_aim"
	# Issue #113 Phase 3: repair context (wrench equipped + a damaged
	# friendly repairable in reach).
	if _near_repairable and has_wrench_equipped():
		return "repair_ready"
	return "standard"


func _set_near_repairable(v: bool) -> void:
	if v == _near_repairable:
		return
	_near_repairable = v
	click_state_changed.emit()


## Enter the armed state: gold reticle follows the crosshair ground point.
func _hl_arm() -> void:
	_hl_state = HLState.ARMED
	_hl_aim = _hl_ground_aim()
	_hl_make_reticle()
	AudioManager.sfx("holy_light_arm")
	if hud != null:
		hud.toast("Holy Light armed — click to charge")


## Disarm from ARMED or CHARGING. Free: nothing spent, no cooldown.
func _hl_disarm() -> void:
	_hl_state = HLState.IDLE
	_hl_charge_t = 0.0
	if _hl_reticle != null and is_instance_valid(_hl_reticle):
		_hl_reticle.queue_free()
	_hl_reticle = null
	AudioManager.sfx("holy_light_disarm")


## Cursor raycast onto the ground at Holy Light range (25m).
func _hl_ground_aim() -> Vector3:
	if _camera == null:
		return global_position
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var target := from + dir * HL_AIM_RANGE
	var params := PhysicsRayQueryParameters3D.create(from, target)
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(params)
	var point: Vector3 = hit["position"] if not hit.is_empty() else target
	point.y = maxf(point.y, 0.1)
	# Clamp to 25m from the player.
	var flat := Vector2(point.x - global_position.x, point.z - global_position.z)
	if flat.length() > HL_AIM_RANGE:
		flat = flat.normalized() * HL_AIM_RANGE
		point.x = global_position.x + flat.x
		point.z = global_position.z + flat.y
	return point


## Gold reticle (flat torus) at the aim point.
func _hl_make_reticle() -> void:
	if _hl_reticle != null and is_instance_valid(_hl_reticle):
		return
	var torus := TorusMesh.new()
	torus.inner_radius = 1.0
	torus.outer_radius = 1.2
	torus.rings = 32
	torus.ring_segments = 8
	_hl_reticle = MeshInstance3D.new()
	_hl_reticle.name = "HolyLightReticle"
	_hl_reticle.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.3, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hl_reticle.material_override = mat
	# Lay flat on the ground.
	_hl_reticle.rotation_degrees = Vector3(90, 0, 0)
	get_parent().add_child(_hl_reticle)
	_hl_reticle.global_position = _hl_aim + Vector3(0, 0.15, 0)


## LMB while armed: begin the 1.0s charge.
func _hl_start_charge() -> void:
	if _hl_state != HLState.ARMED:
		return
	_hl_state = HLState.CHARGING
	_hl_charge_t = 0.0
	AudioManager.sfx("holy_light_riser")


## Charge complete: strike the beam at the aim point. Cooldown starts NOW.
func _hl_strike() -> void:
	_hl_state = HLState.ACTIVE
	_hl_active_t = 0.0
	_hl_aim_send_t = 0.0
	# 20s cooldown starts at STRIKE, not at arm.
	ability_cds["holy_light"] = HL_COOLDOWN * cooldown_mult() / atk_spd_mult() * _tree_skill_mod("holy_light", "cd_mult", 1.0)
	if hud != null:
		hud.refresh_abilities(self)
	# Clear the reticle; the beam takes over.
	if _hl_reticle != null and is_instance_valid(_hl_reticle):
		_hl_reticle.queue_free()
	_hl_reticle = null
	# Issue #171: the spawn sequence is allocated HERE, at
	# strike, and passed through the spawn RPC — every peer
	# keys the beam by the same seq (and names its root from
	# it) by construction.
	_hl_spawn_seq += 1
	_hl_active_seq = _hl_spawn_seq
	rpc("spawn_holy_light", _hl_aim, int(multiplayer.get_unique_id()), _hl_active_seq)
	AudioManager.sfx("holy_light_impact", _hl_aim)


## Issue #91 Phase 2: owner sends aim updates to server at 10Hz (unreliable).
## Issue #171: the update carries the ACTIVE seq; a stale seq
## (the beam already ended) is a no-op on the server.
@rpc("any_peer", "unreliable")
func hl_aim_update(aim: Vector3, seq: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var beam := _hl_find_beam(sender, seq)
	if beam.is_empty():
		return
	beam["aim"] = aim
	beam["target_aim"] = aim
	# Rebroadcast to all peers for remote lerp.
	rpc("hl_beam_aim", sender, aim, seq)


## Issue #91 Phase 2: server rebroadcasts beam aim; remotes lerp toward it.
@rpc("any_peer", "unreliable")
func hl_beam_aim(owner_id: int, aim: Vector3, seq: int) -> void:
	var beam := _hl_find_beam(owner_id, seq)
	if not beam.is_empty():
		beam["target_aim"] = aim


## Issue #91 Phase 2: end a beam early (death/disconnect/manual).
## Issue #171: the end carries the seq — seq 0 ends EVERY beam
## of the owner (the death/disconnect cleanup form). Ending a
## lingering beam never touches the owner's live cast: the
## state resets only when the ACTIVE beam (or all beams) end.
@rpc("any_peer", "call_local", "reliable")
func hl_end_beam(owner_id: int, seq: int) -> void:
	if _hl_beams.has(owner_id):
		var list: Array = _hl_beams[owner_id]
		var kept: Array = []
		for beam in list:
			if seq == 0 or int(beam.get("seq", 0)) == seq:
				var node: Node = beam.get("node")
				if node != null and is_instance_valid(node):
					node.queue_free()
			else:
				kept.append(beam)
		if kept.is_empty():
			_hl_beams.erase(owner_id)
		else:
			_hl_beams[owner_id] = kept
	if owner_id == int(multiplayer.get_unique_id()) \
			and (seq == 0 or seq == _hl_active_seq):
		_hl_state = HLState.IDLE
		_hl_active_t = 0.0


## Jesse 2026-10-10: owner starts the linger phase when the ability ends.
## Marks the beam lingering locally and tells all peers.
## Issue #171: the linger carries the ACTIVE beam's seq — only
## that entry lingers; any older lingering entries are untouched.
func _hl_start_linger() -> void:
	var my_id := int(multiplayer.get_unique_id())
	var beam := _hl_active_beam()
	if beam.is_empty():
		return
	beam["lingering"] = true
	beam["linger_t"] = 0.0
	if _tree_variant("holy_light") == "dawnbringer":
		beam["dawn"] = true
	rpc("hl_linger_beam", my_id, _hl_active_seq)


## Jesse 2026-10-10: all peers mark the beam as lingering (heal zone).
@rpc("any_peer", "call_local")
func hl_linger_beam(owner_id: int, seq: int) -> void:
	var beam := _hl_find_beam(owner_id, seq)
	if not beam.is_empty():
		beam["lingering"] = true
		beam["linger_t"] = 0.0
		# Issue #210 slice B5: Dawnbringer is derived from
		# the owner's synced tree state on every peer.
		var dungeons := get_tree().get_nodes_in_group(
			"dungeon")
		if not dungeons.is_empty():
			var op = dungeons[0].get_player_node(owner_id)
			if op != null and op.has_method(
					"tree_variant_is") and bool(op.call(
					"tree_variant_is", "holy_light",
					"dawnbringer")):
				beam["dawn"] = true


## Jesse 2026-10-10: lingering beams fade over HL_LINGER_TIME, then the
## owner cleans them up everywhere via hl_end_beam.
func _hl_process_linger(delta: float) -> void:
	var my_id := int(multiplayer.get_unique_id())
	var done: Array = [] # [owner_id, seq] pairs whose fade completed
	for owner_id in _hl_beams.keys():
		for beam in _hl_beams[owner_id]:
			if not bool(beam.get("lingering", false)):
				continue
			var t := float(beam.get("linger_t", 0.0)) + delta
			beam["linger_t"] = t
			var frac := clampf(t / HL_LINGER_TIME, 0.0, 1.0)
			# Fade the beam core.
			var beam_mesh: MeshInstance3D = beam.get("beam_mesh")
			if beam_mesh != null and is_instance_valid(beam_mesh):
				var bmat := beam_mesh.material_override as StandardMaterial3D
				if bmat != null:
					var bc := bmat.albedo_color
					bc.a = 0.85 * (1.0 - frac)
					bmat.albedo_color = bc
					bmat.emission_energy_multiplier = 2.0 * (1.0 - frac)
			# Fade the light.
			var light: SpotLight3D = beam.get("light")
			if light != null and is_instance_valid(light):
				light.light_energy = 12.0 * (1.0 - frac)
			# Fade the rings.
			var rings: Array = beam.get("rings", [])
			for ring in rings:
				var rm := ring as MeshInstance3D
				if rm != null and is_instance_valid(rm):
					var rmat := rm.material_override as StandardMaterial3D
					if rmat != null:
						var rc := rmat.albedo_color
						rc.a = 0.7 * (1.0 - frac)
						rmat.albedo_color = rc
			# Owner cleans up everywhere when the fade completes —
			# per entry (issue #171): one beam's expiry never ends
			# another.
			if frac >= 1.0 and owner_id == my_id:
				done.append([owner_id, int(beam.get("seq", 0))])
	for pair in done:
		rpc("hl_end_beam", int(pair[0]), int(pair[1]))


@rpc("any_peer", "call_local")
func spawn_holy_light(aim_point: Vector3, owner_id: int = 0, seq: int = 0) -> void:
	var dungeons := get_tree().get_nodes_in_group("dungeon")
	if dungeons.is_empty():
		return
	var dungeon = dungeons[0]
	var layout = dungeon.get("_layout")
	var center := aim_point
	var map_size := 60.0
	if layout != null:
		map_size = float(layout.grid_size) * layout.cell_size
	if owner_id == 0:
		owner_id = int(multiplayer.get_unique_id())
	if seq <= 0:
		# No sequence from the striker (a direct/local spawn):
		# allocate from this instance's counter.
		_hl_spawn_seq += 1
		seq = _hl_spawn_seq
	# Issue #171: NO clean-replace (the #162 block is deleted) —
	# a recast APPENDS a per-cast entry; the prior beam keeps
	# living (and ticking) alongside the new one. Holy Light
	# stacks.
	# Issue #91 Phase 2: beam container for steering. All visuals are
	# children; moving the container moves the beam. The name is
	# deterministic — HolyLightBeam_<owner>_<seq> with the seq
	# allocated at strike — so it is identical on every peer
	# and two beams can never collide on it.
	var beam_root := Node3D.new()
	beam_root.name = "HolyLightBeam_%d_%d" % [owner_id, seq]
	beam_root.position = center
	dungeon.add_child(beam_root)
	# Track for steering (owner moves directly, remotes lerp).
	var entry := {"node": beam_root, "aim": center, "target_aim": center,
		"owner": owner_id, "seq": seq}
	if not _hl_beams.has(owner_id):
		_hl_beams[owner_id] = []
	(_hl_beams[owner_id] as Array).append(entry)
	# Issue #91 Phase 2: central beam cylinder (emissive gold, r=1.2m).
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.2
	cyl.bottom_radius = 1.2
	cyl.height = 24.0
	cyl.radial_segments = 24
	var beam_mesh := MeshInstance3D.new()
	beam_mesh.name = "BeamCore"
	beam_mesh.mesh = cyl
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.albedo_color = Color(1.0, 0.9, 0.5, 0.85)
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.emission_enabled = true
	beam_mat.emission = Color(1.0, 0.85, 0.4)
	beam_mat.emission_energy_multiplier = 2.0
	beam_mesh.material_override = beam_mat
	beam_mesh.position = Vector3(0, 12.0, 0)
	beam_root.add_child(beam_mesh)
	# Issue #90: SpotLight3D cone aimed down at the beam point.
	var light := SpotLight3D.new()
	light.name = "HolyLight"
	light.position = Vector3(0, 30.0, 0)
	# Aim straight down: SpotLight3D shines along -Z, rotate -90° on X.
	light.rotation_degrees = Vector3(-90, 0, 0)
	light.light_color = Color(1.0, 0.9, 0.55)  # Warm golden.
	light.light_energy = 0.0
	light.spot_range = map_size * 2.0
	light.spot_angle = 45.0  # Wide cone for map-wide coverage.
	light.shadow_enabled = false
	beam_root.add_child(light)
	# Issue #90: 3D yellow rings escalating into the sky (pillar effect).
	var rings: Array[MeshInstance3D] = []
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.85, 0.3, 0.7)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.no_depth_test = false
	for i in range(5):
		var torus := TorusMesh.new()
		torus.inner_radius = 1.5 + float(i) * 0.8
		torus.outer_radius = 1.8 + float(i) * 0.8
		torus.rings = 32
		torus.ring_segments = 12
		var ring := MeshInstance3D.new()
		ring.mesh = torus
		ring.material_override = ring_mat
		# Stack vertically, escalating into the sky (relative to beam root).
		ring.position = Vector3(0, 2.0 + float(i) * 4.0, 0)
		ring.scale = Vector3.ONE * (1.0 + float(i) * 0.3)
		beam_root.add_child(ring)
		rings.append(ring)
	# Store beam parts for wind-down narrowing (on THIS cast's
	# entry — issue #171).
	entry["beam_mesh"] = beam_mesh
	entry["light"] = light
	entry["rings"] = rings
	AudioManager.sfx("holy_light", center)
	if hud != null:
		hud.toast("HOLY LIGHT!")
	# Issue #91 Phase 1: exact timing — 10s hold + 2s wind-down.
	# The old tween stacked to ~21s (parallel 10s ring scale + 10s interval
	# + 2s fade). Now: 0.5s fade-in within the 10s hold, then 2s wind-down.
	# Total beam lifetime: 12s. With the 1s charge: 13s total.
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 12.0, 0.5)
	tw.tween_interval(HL_HOLD_TIME - 0.5)
	tw.tween_property(light, "light_energy", 0.0, HL_WINDDOWN_TIME)
	tw.tween_callback(light.queue_free)
	# Fade rings during wind-down.
	for ring in rings:
		var rtw := ring.create_tween()
		rtw.tween_interval(HL_HOLD_TIME)
		rtw.tween_property(ring, "transparency", 1.0, HL_WINDDOWN_TIME)
		rtw.tween_callback(ring.queue_free)
	tw.tween_callback(light.queue_free)
	# Issue #91 Phase 2: heal now follows the beam via _hl_server_tick()
	# (0.5s ticks at the latest aim point, not a one-time at strike).


func _cast_fireball() -> void:
	if _camera == null:
		return
	_cast_seq += 1
	var basis := _camera.global_transform.basis
	var dir := -basis.z
	var origin: Vector3 = _camera.global_position + dir * 0.7 + Vector3(0, -0.15, 0)
	var dmg := damage * _buff_mult("damage") * rank_mult() * trait_damage_mult("fireball") * _tree_fire_mult("fireball") * _tree_skill_mod("basic_attack", "dmg_mult", 1.0)
	# Twin Suns (issue #206 variant): two bolts at 65% in a
	# +-4 degree spread; the second carries the "twin" tag.
	if _tree_variant("fireball") == "twin_suns":
		var uid := int(multiplayer.get_unique_id())
		rpc("cast_fireball", origin, dir.normalized().rotated(Vector3.UP, deg_to_rad(-4.0)), dmg * 0.65, uid, _cast_seq)
		_cast_seq += 1
		rpc("cast_fireball", origin, dir.normalized().rotated(Vector3.UP, deg_to_rad(4.0)), dmg * 0.65, uid, _cast_seq, "twin")
		return
	rpc("cast_fireball", origin, dir.normalized(), dmg, int(multiplayer.get_unique_id()), _cast_seq)


@rpc("any_peer", "call_local")
func cast_fireball(origin: Vector3, dir: Vector3, dmg: float, owner: int, seq: int, skill_tag := "fireball") -> void:
	var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
	if dungeon == null:
		return
	var fb := Fireball.new()
	fb.name = "Proj_%d_%d" % [owner, seq]
	fb.setup(dir * FIREBALL_SPEED, dmg, owner, skill_tag)
	dungeon.get_node("Projectiles").add_child(fb)
	fb.global_position = origin


func _cast_frost_shard() -> void:
	if _camera == null:
		return
	_cast_seq += 1
	var basis := _camera.global_transform.basis
	var dir := -basis.z
	var origin: Vector3 = _camera.global_position + dir * 0.7 + Vector3(0, -0.15, 0)
	var dmg := damage * _buff_mult("damage") * rank_mult() * trait_damage_mult("frost") * _tree_frost_mult("frost")
	rpc("cast_frost", origin, dir.normalized(), dmg, int(multiplayer.get_unique_id()), _cast_seq)


@rpc("any_peer", "call_local")
func cast_frost(origin: Vector3, dir: Vector3, dmg: float, owner: int, seq: int) -> void:
	var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
	if dungeon == null:
		return
	# Issue #210: slow_add reads off the caster at shard
	# spawn (the fireball-radius pattern); Splinter Volley
	# (the twin_suns shape on the shard path) fires a second
	# shard at 65%.
	var volley := _tree_variant("frost") == "splinter_volley"
	var dirs: Array = [dir]
	var dmgs: Array = [dmg * 0.7]
	if volley:
		dirs = [dir.rotated(Vector3.UP, -0.07),
			dir.rotated(Vector3.UP, 0.07)]
		dmgs = [dmg * 0.7 * 0.65, dmg * 0.7 * 0.65]
	for k in dirs.size():
		var fs := FrostShard.new()
		fs.name = "Frost_%d_%d" % [owner, seq + k * 500]
		fs.setup(dirs[k] * 22.0, dmgs[k], owner)
		fs.slow_duration += _tree_skill_mod("frost",
			"slow_add", 0.0)
		dungeon.get_node("Projectiles").add_child(fs)
		fs.global_position = origin


func _cast_chain_lightning() -> void:
	# Instant: zap nearest mob in 18m, chain to 2 more within 8m of each hit.
	# Issue #166: the damage value is computed from the caster's local
	# stats (the snapshot does not replicate damage/buffs/traits, so
	# the server cannot recompute it) and rides the cast intent,
	# exactly like Fan of Knives / Hammer Smash.
	var dmg := damage * _buff_mult("damage") * rank_mult() * 0.8 * trait_damage_mult("lightning") * _tree_mult("lightning")
	if multiplayer.is_server():
		# Issue #170 (I6): the host cast routes through the
		# validated endpoint — the Hammer Smash template's
		# shape — so the server cooldown gates host casts too.
		request_chain_lightning(dmg)
	else:
		# Client predicts the visual; the server does damage via the
		# validated intent endpoint below. (Before #166 this branch
		# returned without ever telling the server — the cast died
		# at the source and no damage ever landed.)
		_chain_lightning_fx(global_position + Vector3(0, 1.2, 0), global_position + Vector3(0, 1.2, 0) + Vector3(0, 0.1, 0))
		rpc_id(NetworkManager.server_peer_id, "request_chain_lightning", dmg)


## Issue #166: server endpoint for a client's Chain Lightning intent
## (the P3 pattern, templated on request_hammer_smash): validates the
## sender is this node's authority, the caster is a living mage, and
## the claimed damage is sane, then executes the chain on the
## server's world.
@rpc("any_peer", "call_local")
func request_chain_lightning(claimed_damage: float) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	if not alive or downed or class_id != "mage" or claimed_damage <= 0.0:
		return
	# Issue #170: the server cooldown is the only new gate; the
	# claimed-damage trust model is unchanged from #166.
	if _srv_lightning_cd > 0.0:
		return
	_srv_lightning_cd = LIGHTNING_COOLDOWN / atk_spd_mult()
	_execute_chain_lightning(claimed_damage)


## The chain itself: target selection + damage, server-side only
## (host cast directly, or a validated client intent). Kill credit
## follows the caster (this node's multiplayer authority).
func _execute_chain_lightning(dmg: float) -> void:
	_cast_seq += 1
	var from := int(get_multiplayer_authority())
	var hit: Array = []
	var current := _nearest_mob(global_position, 18.0, hit)
	var last_pos := global_position + Vector3(0, 1.2, 0)
	var cast_id := "lightning_%d" % _cast_seq
	# Arc Conduit: lightning chains +1 target.
	var max_chains := 4 if has_trait("arc_conduit") else 3
	# Issue #210: chains_add (aggregate-clamped at +2) and
	# Stormcharged's window fold in beside Arc Conduit's
	# read; the Stormcall finisher below still sets its own
	# designed total when it triggers.
	max_chains += int(_tree_skill_mod("lightning",
		"chains_add", 0.0))
	if _tree_behavior_pct("stormcharged") > 0.0 \
			and Time.get_ticks_msec() < _tree_storm_until:
		max_chains += 1
	var static_bloom := _tree_behavior_pct("static_bloom")
	var forked := _tree_variant("lightning") == "forked_sky"
	# Arcing Brand (Amendment 1): this caster's lightning
	# brand amp; zero means the mechanic does not exist in
	# this game (no application, no reads take effect).
	var brand_amp := _tree_skill_mod("lightning",
		"brand_amp", 0.0)
	# Combo Finisher: Stormcall (issue #8) -- cast while standing inside a
	# War Horn damage aura: chains 6 targets, +25% damage. Per-enemy cooldown
	# is keyed to the first chain target (current is already selected above).
	var storm := Combo.check_lightning_cast(global_position, self, get_tree().get_nodes_in_group("totems"), current)
	if bool(storm["triggered"]):
		max_chains = int(storm["chain_targets"])
		dmg *= float(storm["damage_mult"])
		Combo.announce_finisher(get_tree(), "stormcall")
	for i in max_chains:
		if current == null:
			break
		hit.append(current)
		var mob_pos: Vector3 = current.global_position + Vector3(0, 1.0, 0)
		# Overcharge: 15% chance to double-strike.
		var zap_dmg := dmg * 2.0 if has_trait("overcharge") and randf() < 0.15 else dmg
		# Static Bloom (issue #210): every chain target
		# beyond the first takes +X%.
		if i >= 1 and static_bloom > 0.0:
			zap_dmg *= 1.0 + static_bloom / 100.0
		# Arcing Brand (Amendment 1): a branded target
		# takes the stored amp on a storm hit — the brand
		# is not consumed.
		if brand_amp > 0.0:
			zap_dmg *= 1.0 + current.brand_amp_now()
		# _execute only ever runs on the server.
		current.take_damage(zap_dmg, from, global_position)
		# Forked Sky (issue #210): the first target is
		# struck twice, the second strike at 70%.
		if i == 0 and forked:
			current.take_damage(zap_dmg * 0.7, from,
				global_position)
			rpc("chain_fx", last_pos, mob_pos)
		# The hit brands its target for the next 3 s.
		if brand_amp > 0.0:
			current.apply_brand(3.0, brand_amp, from)
		# Affinity: +2 per enemy zapped, max +8/cast.
		gain_affinity_capped("lightning", 2.0, current.get_instance_id(), cast_id, 8.0)
		rpc("chain_fx", last_pos, mob_pos)
		last_pos = mob_pos
		dmg *= 0.75
		current = _nearest_mob(mob_pos, 8.0, hit)
	if hit.is_empty():
		rpc("chain_fx", last_pos, last_pos + Vector3(0, 0.1, 0))


func _nearest_mob(pos: Vector3, max_dist: float, exclude: Array) -> Mob:
	var best: Mob = null
	var best_d := max_dist
	for n in get_tree().get_nodes_in_group("mobs"):
		var m := n as Mob
		if m == null or not m.alive or m in exclude:
			continue
		var d: float = pos.distance_to(m.global_position)
		if d < best_d and _has_los(pos, m.global_position + Vector3(0, 1.0, 0)):
			best_d = d
			best = m
	return best


## Line-of-sight check: true if no wall cells block the segment.
## Used by Chain Lightning so it can't zap through walls.
func _has_los(from: Vector3, to: Vector3) -> bool:
	var dungeons := get_tree().get_nodes_in_group("dungeon")
	if dungeons.is_empty():
		return true
	var layout = dungeons[0].get("_layout")
	if layout == null:
		return true
	var dist := from.distance_to(to)
	# Sample every ~0.75m along the segment.
	var steps := maxi(2, int(dist / 0.75))
	for i in range(1, steps):
		var p: Vector3 = from.lerp(to, float(i) / float(steps))
		p.y = 1.0  # check at torso height
		if layout.is_solid_world(p):
			return false
	return true


@rpc("any_peer", "call_local")
func chain_fx(a: Vector3, b: Vector3) -> void:
	_chain_lightning_fx(a, b)


func _chain_lightning_fx(a: Vector3, b: Vector3) -> void:
	# Jagged lightning bolt visual.
	var pts := PackedVector3Array()
	var segments := 6
	for i in segments + 1:
		var t := float(i) / float(segments)
		var p: Vector3 = a.lerp(b, t)
		if i > 0 and i < segments:
			p += Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4))
		pts.append(p)
	Effects.lightning(get_parent(), pts, Color(0.7, 0.9, 1.0))
	AudioManager.sfx("lightning_zap", a)


func _cast_meteor() -> void:
	# Target the point under the crosshair (up to 25m); impact after 1s.
	if _camera == null:
		return
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var target := from + dir * 25.0
	var params := PhysicsRayQueryParameters3D.create(from, target)
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(params)
	var point: Vector3 = hit["position"] if not hit.is_empty() else target
	point.y = maxf(point.y, 0.1)
	_cast_seq += 1
	var dmg := damage * _buff_mult("damage") * rank_mult() * 2.0 * trait_damage_mult("meteor") * _tree_fire_mult("meteor")
	# Meteor Shower (issue #206 variant): three meteors at
	# 45% in a triangle (~2.2 m) on the target area.
	if _tree_variant("meteor") == "meteor_shower":
		var uid := int(multiplayer.get_unique_id())
		for k in 3:
			var ang := deg_to_rad(90.0 + 120.0 * float(k))
			var off := Vector3(cos(ang), 0.0, sin(ang)) * 2.2
			rpc("cast_meteor", point + off, dmg * 0.45, uid, _cast_seq)
			_cast_seq += 1
		return
	rpc("cast_meteor", point, dmg, int(multiplayer.get_unique_id()), _cast_seq)


@rpc("any_peer", "call_local")
func cast_meteor(point: Vector3, dmg: float, owner: int, seq: int) -> void:
	# Telegraph ring, then a flaming rock streaks down and impacts.
	Effects.telegraph_ring(get_parent(), point, Meteor.BLAST_RADIUS, Color(1.0, 0.4, 0.1))
	AudioManager.sfx("meteor_incoming", point)
	var meteor := Meteor.new()
	meteor.name = "Meteor_%d_%d" % [owner, seq]
	meteor.setup(point, dmg, owner)
	get_parent().add_child(meteor)


## Arcane Barrage: three fireballs in a spread pattern.
func _cast_barrage() -> void:
	if _camera == null:
		return
	_cast_seq += 1
	var basis := _camera.global_transform.basis
	var base_dir := -basis.z
	var origin: Vector3 = _camera.global_position + base_dir * 0.7 + Vector3(0, -0.15, 0)
	var dmg := damage * _buff_mult("damage") * rank_mult() * 0.6 * trait_damage_mult("barrage") * _tree_mult("barrage")
	# Issue #210: Tempest Fan — five bolts at 50%.
	var fan := _tree_variant("barrage") == "tempest_fan"
	var spread: Array = [-2, -1, 0, 1, 2] if fan else [-1, 0, 1]
	for i in spread:
		var dir := base_dir.rotated(Vector3.UP, i * 0.12).normalized()
		# Overcharge: 15% chance per bolt to double-strike.
		var bolt_dmg := dmg * 2.0 if has_trait("overcharge") and randf() < 0.15 else dmg
		if fan:
			bolt_dmg *= 0.5
		rpc("cast_fireball", origin, dir, bolt_dmg, int(multiplayer.get_unique_id()), _cast_seq + i, "barrage")


## Blizzard: freezing storm at target point, 4s of damage + slow ticks.
func _cast_blizzard() -> void:
	if _camera == null:
		return
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var target := from + dir * 20.0
	var params := PhysicsRayQueryParameters3D.create(from, target)
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(params)
	var point: Vector3 = hit["position"] if not hit.is_empty() else target
	point.y = maxf(point.y, 0.1)
	_cast_seq += 1
	var blizz_dmg := damage * _buff_mult("damage") * rank_mult() * 0.4 * trait_damage_mult("blizzard") * _tree_frost_mult("blizzard")
	rpc("cast_blizzard", point, blizz_dmg, int(multiplayer.get_unique_id()), _cast_seq)


@rpc("any_peer", "call_local")
func cast_blizzard(point: Vector3, dmg: float, owner: int, seq: int) -> void:
	# Issue #210: radius_add + Whiteout (radius x1.5, tick
	# dmg x1.4, ticks at 0.75 s) + duration_add (one 0.5 s
	# tick per step) read off the caster (this node) at cast.
	var radius := 4.0 + _tree_skill_mod("blizzard",
		"radius_add", 0.0)
	var whiteout := _tree_variant("blizzard") == "whiteout"
	if whiteout:
		radius *= 1.5
	var tick_dmg := dmg * (1.4 if whiteout else 1.0)
	var interval := 0.75 if whiteout else 0.5
	var ticks := 8 + int(round(_tree_skill_mod("blizzard",
		"duration_add", 0.0) / 0.5))
	# Snowy visual: blue-white particles falling in the radius.
	var storm := Effects.make_snow()
	storm.amount = 60
	get_parent().add_child(storm)
	storm.global_position = point + Vector3(0, 3.0, 0)
	storm.emitting = true
	AudioManager.sfx("blizzard_loop", point)
	Effects.telegraph_ring(get_parent(), point, radius, Color(0.6, 0.85, 1.0))
	# 8 ticks over 4 seconds (stock).
	var cast_id := "blizzard_%d" % seq
	var granted_mobs := {}
	for i in ticks:
		await get_tree().create_timer(interval).timeout
		if not is_inside_tree():
			break
		if multiplayer.is_server():
			var dungeon := get_tree().get_first_node_in_group("dungeon")
			var caster: Player = dungeon.get_player_node(owner) as Player if dungeon != null else null
			for n in get_tree().get_nodes_in_group("mobs"):
				var m := n as Mob
				if m == null or not m.alive:
					continue
				if m.global_position.distance_to(point) < radius:
					# Shatterglass reads the target's slow
					# state at the tick (issue #210).
					var dealt := tick_dmg * tree_shatterglass_mult(m)
					if multiplayer.is_server():
						m.take_damage(dealt, owner, point)
					else:
						m.rpc_id(NetworkManager.server_peer_id, "take_damage", dealt, owner, point)
					# Permafrost: slows last +2s.
					var bdur := 1.0
					if caster != null and caster.has_trait("permafrost"):
						bdur += 2.0
					m.apply_slow(bdur, 0.5)
					# Affinity: +2 per enemy, once per enemy per cast.
					if caster != null and not granted_mobs.has(m.get_instance_id()):
						granted_mobs[m.get_instance_id()] = true
						caster.gain_affinity("blizzard", 2.0, m.get_instance_id())
	get_parent().get_tree().create_timer(0.5).timeout.connect(storm.queue_free)


# --- Departure board reading mode (station) ---

## Enter cursor-vote mode on the 3D departure board (local only).
func enter_reading(board: DepartureBoard) -> void:
	if not is_multiplayer_authority() or not alive or board == null:
		return
	_reading_board = board
	_reading_hover = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud != null:
		hud.set_hint(READ_HINT)
	AudioManager.sfx("ui_click")


## Leave reading mode. Safe to call when not reading.
func exit_reading() -> void:
	if _reading_board == null:
		return
	_reading_board.set_hover("")
	_reading_board = null
	_reading_hover = ""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if hud != null:
		hud.set_hint("")


## Modal input while reading: E steps away, Esc pauses, left-click votes.
func _reading_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.physical_keycode == KEY_E:
			exit_reading()
			get_viewport().set_input_as_handled()
		elif k.physical_keycode == KEY_ESCAPE:
			# Jesse 2026-10-11: Esc cancels FPS placement first.
			if _placing_type != "":
				command_cancel_placement()
				get_viewport().set_input_as_handled()
				return
			exit_reading()
			if hud != null:
				hud.show_pause()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _reading_hover != "":
			var st := get_tree().get_first_node_in_group("station")
			if st != null:
				st.rpc("cast_vote", _reading_hover)
				AudioManager.sfx("ui_click")
			get_viewport().set_input_as_handled()


## Cursor raycast against the board's row hitboxes (physics layer 4).
func _update_board_hover() -> void:
	if _reading_board == null or _camera == null:
		return
	var mp := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mp)
	var to := from + _camera.project_ray_normal(mp) * 10.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 8 # layer 4: departure board rows only
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var tid := ""
	if not hit.is_empty():
		var col = hit["collider"]
		if col is Area3D and col.has_meta("theme_id"):
			tid = str(col.get_meta("theme_id"))
	if tid != _reading_hover:
		_reading_hover = tid
		_reading_board.set_hover(tid)


# --- Pickups & inventory ---

func _nearest_pickup() -> ItemPickup:
	var best: ItemPickup = null
	var best_d := PICKUP_RANGE * special_pickup_mult
	for node in get_tree().get_nodes_in_group("pickups"):
		var pickup := node as ItemPickup
		if pickup == null or not pickup.is_available():
			continue
		var to: Vector3 = pickup.global_position - global_position
		to.y = 0.0 # horizontal distance only; the loot's hover height shouldn't matter
		var d := to.length()
		if d < best_d:
			best_d = d
			best = pickup
	return best


func _update_pickup_prompt() -> void:
	if hud == null:
		return
	# Issue #113 Phase 3: repair context for the prompt + mouse legend.
	var repair := repair_target_at(global_position) if has_wrench_equipped() else {}
	_set_near_repairable(not repair.is_empty())
	# Reading mode owns the hint label.
	if _reading_board != null:
		hud.set_hint(READ_HINT)
		return
	# Revive prompt takes priority over loot.
	if _nearest_downed_teammate() != null:
		if _prompt_pickup != null:
			_prompt_pickup = null
		if _prompt_repair:
			_prompt_repair = false
			hud.set_pickup_prompt(false, "")
		hud.set_hint("Hold {interact} to revive teammate")
		return
	# Repair prompt (wrench equipped + damaged friendly repairable near).
	if not repair.is_empty():
		if _prompt_pickup != null:
			_prompt_pickup = null
		_prompt_repair = true
		hud.set_pickup_prompt(true, "%s — Hold {interact} to repair (%d/%d HP)" % [
			str(repair["name"]), int(ceil(float(repair["hp"]))),
			int(ceil(float(repair["max_hp"])))])
		return
	if _prompt_repair:
		_prompt_repair = false
		hud.set_pickup_prompt(false, "")
	# Cipher note / lockbox / departure board / vendor stall prompt.
	var c := _nearest_interact_node()
	if c != null:
		if _prompt_pickup != null:
			_prompt_pickup = null
		_prompt_interact = true
		hud.set_pickup_prompt(true, str(c.prompt_text()))
		return
	# Interact node gone: clear its stale prompt (the pickup branch below only
	# reacts to pickup changes, so it would leave "Browse vendor" up forever).
	if _prompt_interact:
		_prompt_interact = false
		hud.set_pickup_prompt(false, "")
		return
	var p := _nearest_pickup()
	if p != _prompt_pickup:
		_prompt_pickup = p
		if p != null:
			if p.is_key:
				hud.set_pickup_prompt(true, "Take Key")
			elif p.item != null:
				hud.set_pickup_prompt(true, p.item.display_name)
			else:
				hud.set_pickup_prompt(false, "")
		else:
			hud.set_pickup_prompt(false, "")


## Nearest cipher note, lockbox, departure board, vendor stall, train
## skip lever, bounty board, vault locker, depart lever, or farm plot
## within E range. (Issue #126 Phase 3: the deleted spots' group
## entry swept from this scan — the layout's pier data is scenery,
## not an interactable.)
func _nearest_interact_node() -> Node3D:
	var best: Node3D = null
	var best_d := 2.5
	for group in ["cipher_plaques", "departure_board", "vendor_stall", "skip_lever", "bounty_board", "vault_locker", "depart_lever", "cab_button", "vault_door", "rooftop_door", "farm_plots", "dock_merchant", "vault_mechanisms", "transfer_trigger", "floor_transfer"]:
		for n in get_tree().get_nodes_in_group(group):
			var node := n as Node3D
			if node == null or not node.visible:
				continue
			var d := node.global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				best = node
	return best


## Jesse 2026-10-11: toggles RTS command mode (warlord domain only).
## Issue #165 (F2, Jesse's mouse rule): first-person command keeps
## the mouse CAPTURED and targets by aim — only menus un-capture,
## for their lifetime (see _command_process).
func _toggle_command_mode() -> void:
	_command_mode = not _command_mode
	if _command_mode:
		# Cache the player's RTS faction.
		_command_faction = int(get("rts_faction"))
		if hud != null:
			hud.set_hint("Command: aim + {attack} select | {alt_attack} order | {interact} building | {ability} exits")
	else:
		command_cancel_placement()
		for u in _command_selected:
			if is_instance_valid(u) and u.has_method("set_selected"):
				u.rpc("set_selected", false)
		_command_selected.clear()
		_command_aim = Vector3.INF
		if _aim_marker != null and is_instance_valid(_aim_marker):
			_aim_marker.queue_free()
		_aim_marker = null
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if hud != null:
			hud.set_hint("")


## Issue #165 (F2): per-frame FPS command upkeep — the aim point
## and its marker follow the camera-center aim, and the cursor
## belongs to the aim (CAPTURED) except while an RTS menu is open
## (VISIBLE for the menu's lifetime, re-captured when it closes).
func _command_process() -> void:
	_command_aim = _command_aim_point()
	if _aim_marker == null:
		_aim_marker = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.42
		tm.outer_radius = 0.55
		_aim_marker.mesh = tm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.9, 1.0, 0.8)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_aim_marker.material_override = mat
		_aim_marker.top_level = true
		add_child(_aim_marker)
	_aim_marker.visible = _command_aim != Vector3.INF
	if _aim_marker.visible:
		_aim_marker.global_position = _command_aim + Vector3(0, 0.06, 0)
	if hud != null and hud.is_paused:
		return
	var menu_open := false
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null:
		var rhud = dungeon.get_node_or_null("RTSHUD")
		if rhud != null:
			if rhud.has_method("is_build_menu_open") and bool(rhud.call("is_build_menu_open")):
				menu_open = true
			var tp = rhud.get("_train_panel")
			if tp != null and (tp as CanvasItem).visible:
				menu_open = true
	var want := Input.MOUSE_MODE_VISIBLE if menu_open else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != want:
		Input.mouse_mode = want


## Nearest friendly RTS building within interact range.
func _nearest_command_building() -> Node3D:
	var best: Node3D = null
	var best_d := 4.0
	for n in get_tree().get_nodes_in_group("rts_buildings"):
		if int(n.get("faction")) != _command_faction:
			continue
		if n.get("destroyed") == true:
			continue
		var d := (n as Node3D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


## E in command mode: open the building's menu (train/build).
func _command_interact_building() -> void:
	var b := _nearest_command_building()
	if b == null:
		return
	# Reuse the RTS HUD train panel (works in any view).
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null:
		return
	var rts_hud := dungeon.get_node_or_null("RTSHUD")
	if rts_hud != null and rts_hud.has_method("show_train_menu"):
		rts_hud.call("show_train_menu", b)
		get_viewport().set_input_as_handled()


## Issue #165 (F2): the FPS command aim point — the ground under
## the camera-center aim (physics ray first, y=0 plane fallback),
## Vector3.INF when the aim meets neither. This replaces the old
## free-cursor raycast: with the mouse captured there is no
## cursor, so the crosshair IS the pointer.
func _command_aim_point() -> Vector3:
	var cam := get("_camera") as Camera3D
	if cam == null:
		return Vector3.INF
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 200.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.get("position")
	if absf(dir.y) > 0.001:
		var t := -origin.y / dir.y
		if t > 0:
			return origin + dir * t
	return Vector3.INF


## Issue #165 (F2): the unit/building the aim points at — a ray
## from high above the aim point straight down over the units'
## pick areas; on no hit, the proximity fallback (nearest within
## 2.0 m, the top-down camera's _pick_enemy_at tolerance) over
## units, then buildings by the same rule.
func _command_pointed(aim: Vector3) -> Node3D:
	if aim == Vector3.INF:
		return null
	var query := PhysicsRayQueryParameters3D.create(aim + Vector3(0, 30, 0), aim + Vector3(0, -2, 0))
	query.collide_with_bodies = false
	query.collide_with_areas = true
	query.collision_mask = RTSUnit.PICK_LAYER
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var area := hit.get("collider") as Area3D
		if area != null and area.get_parent() != null and area.get_parent().is_in_group("rts_units"):
			return area.get_parent() as Node3D
	var best: Node3D = null
	var best_d := 2.0
	for n in get_tree().get_nodes_in_group("rts_units"):
		var d := aim.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n
	if best != null:
		return best
	for n in get_tree().get_nodes_in_group("rts_buildings"):
		var d := aim.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


## Left-click in command mode (issue #165 F2): select the pointed
## own-faction unit, through the replicated selection path.
func _command_select() -> void:
	for u in _command_selected:
		if is_instance_valid(u) and u.has_method("set_selected"):
			u.rpc("set_selected", false)
	_command_selected.clear()
	var pointed := _command_pointed(_command_aim_point())
	if pointed != null and pointed.is_in_group("rts_units") \
			and int(pointed.get("faction")) == _command_faction:
		_command_selected.append(pointed)
		if pointed.has_method("set_selected"):
			pointed.rpc("set_selected", true)
	get_viewport().set_input_as_handled()


## Right-click in command mode (issue #165 F1+F2): order the
## selection — pointed enemy unit/building -> attack; otherwise
## -> move to the aim point.
func _command_order() -> void:
	if _command_selected.is_empty():
		return
	var aim := _command_aim_point()
	if aim == Vector3.INF:
		return
	var target: Node3D = null
	var pointed := _command_pointed(aim)
	if pointed != null and (pointed.is_in_group("rts_units") or pointed.is_in_group("rts_buildings")) \
			and int(pointed.get("faction")) != _command_faction:
		target = pointed
	for u in _command_selected:
		if not is_instance_valid(u):
			continue
		# Issue #165 (D1/F1): the house direct-call pattern — a
		# Steam peer cannot rpc_id its own peer ID (peer-id
		# hygiene: the remote leg targets
		# NetworkManager.server_peer_id, never a hardcoded 1).
		if target != null:
			if multiplayer.is_server():
				u.rpc_order_attack(target.get_path())
			else:
				u.rpc_id(NetworkManager.server_peer_id, "rpc_order_attack", target.get_path())
		else:
			if multiplayer.is_server():
				u.rpc_order_move(aim)
			else:
				u.rpc_id(NetworkManager.server_peer_id, "rpc_order_move", aim)
	get_viewport().set_input_as_handled()


## Jesse 2026-10-11: FPS building placement (B in command mode).
## Mirrors RTSCamera.start_placement but positions the ghost via the
## FPS camera raycast instead of screen coordinates.
func command_start_placement(btype: String) -> void:
	command_cancel_placement()
	_placing_type = btype
	_placing_ghost = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.0, 2.0, 3.0)
	_placing_ghost.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.3, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_placing_ghost.material_override = mat
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null and dungeon.has_node("RTS"):
		dungeon.get_node("RTS").add_child(_placing_ghost)
	else:
		get_tree().current_scene.add_child(_placing_ghost)
	if hud != null:
		hud.set_hint("{attack} to place %s | {alt_attack}/{close} cancels" % btype.replace("_", " ").capitalize())


func command_cancel_placement() -> void:
	_placing_type = ""
	if _placing_ghost != null and is_instance_valid(_placing_ghost):
		_placing_ghost.queue_free()
	_placing_ghost = null
	if _command_mode and hud != null:
		hud.set_hint("Command: {interact} on building | {attack} select | {alt_attack} order | {ability} exits")


## Update ghost position from the camera raycast each frame while placing.
func _command_update_ghost() -> void:
	if _placing_ghost == null or not is_instance_valid(_placing_ghost):
		return
	var ground := _command_aim_point()
	if ground == Vector3.INF:
		_placing_valid = false
		return
	_placing_ghost.position = Vector3(ground.x, 1.0, ground.z)
	_placing_valid = _command_valid_build_spot(ground)
	var mat := _placing_ghost.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(0.2, 0.9, 0.3, 0.4) if _placing_valid else Color(0.9, 0.2, 0.2, 0.4)


func _command_valid_build_spot(ground: Vector3) -> bool:
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if ground.distance_to((b as Node3D).global_position) < 5.0:
			return false
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null and dungeon.has_method("is_on_water"):
		if dungeon.call("is_on_water", ground) == true:
			return false
	return true


## Confirm placement: needs selected villagers as builders.
func _command_confirm_placement() -> void:
	if _placing_type == "" or not _placing_valid:
		return
	var ground := _command_aim_point()
	if ground == Vector3.INF:
		return
	# Builders = selected villagers (mirrors RTSCamera._confirm_placement).
	var builders: Array = []
	for n in _command_selected:
		if is_instance_valid(n) and str(n.get("unit_type")) == "villager":
			builders.append(n.get_path())
	if builders.is_empty():
		var dungeon2 := get_tree().get_first_node_in_group("dungeon")
		var rhud := dungeon2.get_node_or_null("RTSHUD") if dungeon2 else null
		if rhud != null and rhud.has_method("show_toast"):
			rhud.call("show_toast", "Please select villager/s before building")
		return
	var btype := _placing_type
	command_cancel_placement()
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null and dungeon.has_method("rpc_start_construction"):
		# Issue #165 (D1/F1): the house direct-call pattern — a
		# Steam peer cannot rpc_id its own peer ID (peer-id
		# hygiene: NetworkManager.server_peer_id on the remote leg).
		if multiplayer.is_server():
			dungeon.rpc_start_construction(_command_faction, btype, Vector3(ground.x, 0, ground.z), builders)
		else:
			dungeon.rpc_id(NetworkManager.server_peer_id, "rpc_start_construction", _command_faction, btype, Vector3(ground.x, 0, ground.z), builders)
	get_viewport().set_input_as_handled()


func _try_pickup() -> void:
	# Cipher/board interactions take priority over loot.
	var interact := _nearest_interact_node()
	if interact != null:
		interact.interact(self)
		if hud != null:
			hud.set_pickup_prompt(false, "")
		get_viewport().set_input_as_handled()
		return
	# In supermarket mode, the checkout auto-sells on walk-through;
	# E at a shop pedestal buys potions.
	var dungeons := get_tree().get_nodes_in_group("dungeon")
	if not dungeons.is_empty():
		var dungeon = dungeons[0]
		if bool(dungeon.get("is_supermarket")):
			# Check shop pedestals.
			for child in dungeon.get_node_or_null("Pickups").get_children():
				if child.name.begins_with("Shop_") and child.global_position.distance_to(global_position) < 2.5:
					dungeon.rpc("buy_potion", child.get_meta("item_id"), child.get_meta("price"))
					return
	var best := _nearest_pickup()
	if best != null:
		_prompt_pickup = null
		if hud != null:
			hud.set_pickup_prompt(false, "")
		best.request_claim(int(multiplayer.get_unique_id()))
	elif hud != null:
		hud.toast("No loot in reach.")


@rpc("any_peer", "call_local")
func on_sold(amount: int) -> void:
	if not is_multiplayer_authority():
		return
	supermarket_cash += 0  # already added server-side; just toast here
	if hud != null:
		hud.toast("Sold loot for $%d!" % amount)
		AudioManager.sfx("cash_register")


## Supermarket checkout (owner side): tally this player's supermarket
## loot and remove it from the REAL bag. Inventory is per-peer
## authoritative (issue #105) and never replicates, so the server's
## copy of a client's bag is a spawn-time snapshot — a server-side
## tally (the old way) always totals 0 for groceries picked up in the
## level, and would pay out for carried-in groceries without ever
## removing them from the real bag. The tally therefore runs here, on
## the owner's instance; the server credits from the reported total.
func tally_and_remove_groceries() -> int:
	var total := 0
	var kept: Array = []
	# Issue #104 marker-preservation audit: entries are carried by
	# reference (never rebuilt), so "equipped_slot" markers survive.
	for entry in inventory:
		var item = entry["item"]
		if bool(item.get("supermarket_loot")):
			total += int(item.get("sell_value")) * int(entry["count"])
		else:
			kept.append(entry)
	if total > 0:
		inventory = kept
		_recalc_stats()
		if hud != null:
			hud.refresh_inventory(self)
	return total


## Checkout delegation: the server asks the owner to tally + remove
## its groceries (tally_and_remove_groceries) and report the total
## back; the server then credits the sale from the reported total.
@rpc("any_peer", "call_local")
func rpc_collect_groceries() -> void:
	if not is_multiplayer_authority():
		return
	var total := tally_and_remove_groceries()
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null:
		dungeon.rpc_id(NetworkManager.server_peer_id, "rpc_report_checkout_total", total)


## Checkout feedback for an empty bag (Jesse 2026-10-19): a zero sell
## used to be silent, indistinguishable from the sell not happening.
@rpc("any_peer", "call_local")
func on_checkout_empty() -> void:
	if not is_multiplayer_authority():
		return
	if hud != null:
		hud.toast("Nothing to sell — your bag has no groceries.")


@rpc("any_peer", "call_local")
func on_bought(item_id: String, price: int) -> void:
	if not is_multiplayer_authority():
		return
	if hud != null:
		hud.toast("Bought %s for $%d!" % [item_id.replace("_", " ").capitalize(), price])
		if hud.vendor_open:
			hud.refresh_vendor_cash()
		AudioManager.sfx("cash_register")


@rpc("any_peer", "call_local")
func on_buy_failed(price: int) -> void:
	if not is_multiplayer_authority():
		return
	if hud != null:
		hud.toast("Not enough cash! Need $%d." % price)


## Issue #142: a purchase whose grant could not land (inventory full)
## was refunded in full server-side — money never vanishes silently.
@rpc("any_peer", "call_local")
func on_buy_refunded(price: int) -> void:
	if not is_multiplayer_authority():
		return
	if hud != null:
		hud.toast("Purchase refunded: $%d." % price)
		if hud.vendor_open:
			hud.refresh_vendor_cash()


## Issue #160: a dispose drop debits the DROPPER's dock mirrors on
## the server — the exact inverse of the #155 claim credit, same
## discipline (server-only, sender must own this node). Without it
## the mirror kept the disposed goods: reclaiming the drop then
## double-credited, and the stale balance stayed sellable.
@rpc("any_peer", "call_local")
func report_dispose(item_id: String, count: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = int(multiplayer.get_unique_id())
	if peer != get_multiplayer_authority():
		return
	_debit_dock_mirrors(peer, item_id, count)


## The debit table — the #155 claim hook's mirror image (clamped:
## a mirror never goes below zero on a drop).
func _debit_dock_mirrors(peer: int, item_id: String, count: int) -> void:
	if count <= 0:
		return
	if item_id == "seed_packet":
		FarmPlot.grant_seeds(peer, -mini(count, FarmPlot.seed_count(peer)))
	elif item_id == "seed_packet_fine":
		# Issue #155 (ii): disposing a quality packet debits the
		# FINE bucket (clamped, like every mirror debit).
		FarmPlot.grant_seeds(peer, -mini(count, FarmPlot.seed_count(peer, FarmPlot.TIER_FINE)), FarmPlot.TIER_FINE)
	elif item_id == DockEconomy.CASH_ITEM:
		DockEconomy.debit_cash(peer, count)
	elif item_id == DockEconomy.BAIT_ITEM or item_id == DockEconomy.FERTILIZER_ITEM \
			or item_id.begins_with("fish_") or item_id.begins_with("crop_"):
		# Issue #160 (verification leg): EVERY tracked dock-stock
		# item debits — the grant legs credit fish/crops/fertilizer
		# into the same stock mirror, and dispose drops any bag
		# item, not only the claim classes above.
		DockEconomy.debit_stock(peer, item_id, count)


@rpc("any_peer", "call_local")
func receive_item(item_id: String, sell_value: int = -1, claim_from: String = "", claim_count: int = 0, claim_tag: int = 0) -> void:
	if not is_multiplayer_authority():
		return
	var item := ItemDB.get_item(item_id)
	if item == null:
		# A claim on an unresolvable item consumes the drop (it could
		# never be granted); non-claim grants just no-op, as before.
		_report_claim(claim_from, claim_count, claim_tag)
		return
	# Issue #142: units this grant moves — a world-pickup claim carries
	# the drop's whole count (stacks are unbounded, so a claim takes
	# all of it or, when full, none); every other grant moves one.
	var add_n := claim_count if claim_count > 0 else 1
	# Apex relic (issue #5): earns the special into the vault instead of
	# entering the inventory. The passive applies when equipped (issue #6).
	if not item.grants_special.is_empty():
		var sp := SpecialData.get_special(item.grants_special)
		SpecialData.earn_for(self, item.grants_special)
		if hud != null and sp != null:
			hud.toast("Relic claimed: %s — equip it in the Relic Vault!" % sp.display_name)
		AudioManager.sfx("unlock")
		_report_claim(claim_from, claim_count, claim_tag)
		return
	# Danger-model scaled drops carry their sell value from the pickup.
	# Duplicate before mutating so the shared ItemDB entry stays pristine.
	if sell_value >= 0 and sell_value != item.sell_value:
		item = item.duplicate() as ItemData
		item.sell_value = sell_value
	# Same-type items combine into the existing stack.
	for entry in inventory:
		var e_item := entry["item"] as ItemData
		if e_item != null and e_item.id == item.id:
			entry["count"] = int(entry["count"]) + add_n
			_recalc_stats()
			health_changed.emit(hp, max_hp)
			var rare := _pickup_feedback(item)
			if hud != null:
				hud.toast("Picked up: %s (x%d)" % [item.display_name, int(entry["count"])])
				hud.refresh_inventory(self)
				hud.refresh_loadout(self)
				if rare:
					hud.toast("%s %s!" % [ItemData.rarity_name(item.rarity).to_upper(), item.display_name.to_upper()])
			_report_claim(claim_from, claim_count, claim_tag)
			return
	if inventory.size() >= INVENTORY_MAX:
		if hud != null:
			hud.toast("Inventory full! Press {inventory} to manage it.")
		# Issue #142: a claim that lands nothing reports a zero take —
		# the drop stays in the world (ItemPickup.report_claim).
		_report_claim(claim_from, 0, claim_tag)
		return
	# Issue #104 Phase 1: new pickups NEVER auto-equip. (If a stack of
	# this item already exists, the merge path above grows it in place —
	# an equipped stack stays equipped and grows.)
	inventory.append({"item": item, "count": add_n, "equipped_slot": ""})
	_recalc_stats()
	health_changed.emit(hp, max_hp)
	var rare := _pickup_feedback(item)
	if hud != null:
		hud.toast("Picked up: %s  (I: inventory)" % item.display_name)
		hud.refresh_inventory(self)
		hud.refresh_loadout(self)
		if rare:
			hud.toast("%s %s!" % [ItemData.rarity_name(item.rarity).to_upper(), item.display_name.to_upper()])
	_report_claim(claim_from, claim_count, claim_tag)


## Issue #142: report a world-pickup claim's outcome to the pickup
## (see ItemPickup.report_claim): how many units this grant actually
## took. Non-claim grants pass no claim source and never report. The
## claimer's own request flag clears here too — the claim has resolved
## from their side whatever the outcome.
func _report_claim(claim_from: String, taken: int, tag: int = 0) -> void:
	if claim_from == "":
		return
	var pk := get_node_or_null(claim_from)
	if pk == null:
		return
	if pk.has_method("resolve_my_claim"):
		pk.call("resolve_my_claim")
	if multiplayer.is_server():
		pk.call("report_claim", taken, tag)
	else:
		pk.rpc_id(NetworkManager.server_peer_id, "report_claim", taken, tag)


## Pickup sound pitched by rarity. Returns true for rare+ finds (caller shows
## a special toast after the normal pickup message).
func _pickup_feedback(item: ItemData) -> bool:
	AudioManager.sfx("pickup", null, 1.0 + float(item.rarity) * 0.12)
	return item.rarity >= ItemData.Rarity.RARE


## TEMPORARY #136 diagnostic: inventory-removal audit. Every path that
## removes or replaces inventory stacks reports through here — one log
## line (prefix [#136-INVENTORY-AUDIT]) plus a bounded in-memory copy
## the suite can assert on. No behavior change. Removal of this
## instrumentation rides with the #136 fix/closure.
const INVENTORY_AUDIT_MAX := 64
var inventory_audit_log: Array[String] = []


func _audit_inventory(site: String, item_id: String, count: int, index: int, slot: String = "", extra: String = "") -> void:
	var line := "[#136-INVENTORY-AUDIT] site=%s item=%s count=%d index=%d slot=%s class=%s level=%d tick=%d" % [
		site, item_id, count, index, slot, class_id, level, Time.get_ticks_msec()]
	if extra != "":
		line += " " + extra
	print(line)
	inventory_audit_log.append(line)
	while inventory_audit_log.size() > INVENTORY_AUDIT_MAX:
		inventory_audit_log.pop_front()


## Destroy the selected stack entirely.
func dispose_item(index: int) -> void:
	if not is_multiplayer_authority():
		return
	if index < 0 or index >= inventory.size():
		return
	var entry: Dictionary = inventory[index]
	var item := entry["item"] as ItemData
	# Issue #104 Phase 1: disposing an EQUIPPED stack is blocked.
	if _entry_equipped_slot(entry) != "":
		if hud != null:
			hud.toast("Unequip first.")
		return
	# Issue #146 (Jesse's tracker-20 ruling): where no dungeon pickup
	# path exists in this scene (the train station), disposing is
	# BLOCKED outright — no station pickup path is built, and the
	# item stays in the player's inventory. In-level disposal is the
	# #142 drop below. (The #136 audit hook sits past this block: a
	# blocked attempt disposes nothing, so it is not a disposal.)
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null:
		if hud != null:
			hud.toast("Can't dispose here.")
		return
	_audit_inventory("dispose_item", item.id, int(entry["count"]), index, _entry_equipped_slot(entry))
	# Issue #142: disposing drops the stack in the world as a pickup
	# (spawned through the dungeon's path — all peers see it, late
	# joiners re-sync it) instead of destroying it. The drop spawns
	# BEFORE the removal so a spawn failure can never eat the stack.
	# The Architect's tools drop like any other item (Jesse's ruling:
	# world items are never persisted, so the #113 run-start re-grant
	# — which works from saved state — has no duplication path here).
	var base := ItemDB.get_item(item.id)
	var mult := 1.0
	if base != null and base.sell_value > 0 and item.sell_value != base.sell_value:
		mult = float(item.sell_value) / float(base.sell_value)
	var drop_pos := global_position - global_transform.basis.z * 0.9
	dungeon.spawn_pickup_allocated(item.id, drop_pos, mult, int(entry["count"]))
	# Issue #160: the drop debits this peer's dock mirrors on the
	# server (report_dispose) — bag and mirror leave together, so a
	# later claim (by anyone, including the dropper) re-credits from
	# zero instead of doubling.
	if multiplayer.is_server():
		report_dispose(item.id, int(entry["count"]))
	else:
		rpc_id(NetworkManager.server_peer_id, "report_dispose", item.id, int(entry["count"]))
	inventory.remove_at(index)
	_recalc_stats()
	health_changed.emit(hp, max_hp)
	if hud != null:
		hud.toast("Dropped: %s x%d" % [item.display_name, int(entry["count"])])
		hud.refresh_inventory(self)
		hud.refresh_loadout(self)


## Use one consumable from the selected inventory stack.
func use_item(index: int) -> void:
	if not is_multiplayer_authority():
		return
	if not alive:
		return
	if index < 0 or index >= inventory.size():
		return
	var entry: Dictionary = inventory[index]
	var item := entry["item"] as ItemData
	if item == null or not item.consumable:
		if hud != null:
			hud.toast("That item can't be used.")
		return
	# Issue #113 Phase 1: upgrade kits apply to the equipped weapon
	# stack instead of granting an effect; they have their own
	# consumption rules (never consumed on a refused use).
	if item.upgrade_levels > 0:
		_use_upgrade_kit(entry, index, item)
		return
	var now := Time.get_ticks_msec() / 1000.0
	var effect := ""
	if item.heal_fraction > 0.0:
		var amount := max_hp * item.heal_fraction
		hp = minf(max_hp, hp + amount)
		effect = "+%d HP" % int(amount)
		Effects.burst(get_parent(), global_position + Vector3(0, 1.2, 0), Color(0.3, 1.0, 0.4), 18, 4.0)
	if item.buff_stat != "" and _buffs.has(item.buff_stat) and item.buff_duration > 0.0:
		_buffs[item.buff_stat]["mult"] = item.buff_mult
		_buffs[item.buff_stat]["until"] = now + item.buff_duration
		_buff_announced[item.buff_stat] = true
		effect += (" " if effect != "" else "") + "+%d%% %s (%ds)" % [
			int((item.buff_mult - 1.0) * 100.0), item.buff_stat, int(item.buff_duration)]
	# Issue #102 Phase 4: wave-counted buffs (buff_waves). Defense uses
	# mult < 1.0 (damage taken multiplier), shown as a reduction.
	if item.buff_stat != "" and int(item.buff_waves) > 0 and _wave_buffs.has(item.buff_stat):
		_wave_buffs[item.buff_stat]["mult"] = item.buff_mult
		_wave_buffs[item.buff_stat]["waves"] = int(item.buff_waves)
		var pct := int(absf(item.buff_mult - 1.0) * 100.0)
		var sign := "+" if item.buff_mult >= 1.0 else "-"
		effect += (" " if effect != "" else "") + "%s%d%% %s (%d waves)" % [
			sign, pct, item.buff_stat, int(item.buff_waves)]
	entry["count"] = int(entry["count"]) - 1
	if int(entry["count"]) <= 0:
		_audit_inventory("use_item", item.id, 1, index, _entry_equipped_slot(entry))
		inventory.remove_at(index)
	# Rare-fish buff build (dock-mirror integrity): consuming a
	# tracked dock good debits the server mirror through the same
	# validated report_dispose path as a dispose drop — bag and
	# mirror leave together. The debit table in _debit_dock_mirrors
	# decides what is tracked, so an eaten fish or crop can never
	# stay sellable from the mirror (the #160 phantom).
	if multiplayer.is_server():
		report_dispose(item.id, 1)
	else:
		rpc_id(NetworkManager.server_peer_id, "report_dispose", item.id, 1)
	_recalc_stats()
	health_changed.emit(hp, max_hp)
	AudioManager.sfx("drink")
	if hud != null:
		hud.toast("Used %s: %s" % [item.display_name, effect])
		hud.refresh_inventory(self)
		hud.refresh_loadout(self)


## Issue #113 Phase 1: apply one upgrade kit to the EQUIPPED weapon
## stack. Refused uses (no weapon equipped, weapon already at the cap)
## show a toast and do NOT consume the kit. A successful use consumes
## one kit and raises the weapon stack's upgrade_level, clamped at
## UPGRADE_LEVEL_CAP (a +2 kit at level 4 lands on +5, not +6).
func _use_upgrade_kit(entry: Dictionary, index: int, item: ItemData) -> void:
	var weapon := equipped_entry("WEAPON")
	if weapon.is_empty():
		if hud != null:
			hud.toast("Equip a weapon first")
		return
	var level := int(weapon.get("upgrade_level", 0))
	if level >= UPGRADE_LEVEL_CAP:
		if hud != null:
			hud.toast("Weapon fully upgraded (+%d)" % UPGRADE_LEVEL_CAP)
		return
	var new_level := mini(UPGRADE_LEVEL_CAP, level + item.upgrade_levels)
	weapon["upgrade_level"] = new_level
	var kit_had := int(entry["count"])
	entry["count"] = int(entry["count"]) - 1
	if int(entry["count"]) <= 0:
		_audit_inventory("use_upgrade_kit", item.id, kit_had, index, _entry_equipped_slot(entry))
		inventory.remove_at(index)
	_recalc_stats()
	health_changed.emit(hp, max_hp)
	# Sound Engineer's dedicated cue for this (landed with the #113 cues).
	AudioManager.sfx("upgrade_apply")
	if hud != null:
		var witem := weapon.get("item") as ItemData
		hud.toast("%s upgraded to +%d" % [
			witem.display_name if witem != null else "Weapon", new_level])
		hud.refresh_inventory(self)
		hud.refresh_loadout(self)


## Issue #102 Phase 3: the server spends one seed when a farm plot is
## planted. Inventory is per-peer authoritative, so the server rpc_ids the
## planter and the client drops one packet from its own stack
## (mirrors the receive_item grant path). Issue #155 (ii): the item
## is the SPENT TIER's packet (parameterized; default regular).
@rpc("any_peer", "call_local")
func consume_seed_item(item_id: String = "seed_packet") -> void:
	if not is_multiplayer_authority():
		return
	for i in range(inventory.size()):
		var entry: Dictionary = inventory[i]
		var item := entry["item"] as ItemData
		if item != null and item.id == item_id:
			var had := int(entry["count"])
			entry["count"] = int(entry["count"]) - 1
			if int(entry["count"]) <= 0:
				_audit_inventory("consume_seed_item", item.id, had, i, _entry_equipped_slot(entry))
				inventory.remove_at(i)
			_recalc_stats()
			if hud != null:
				hud.refresh_inventory(self)
				hud.refresh_loadout(self)
			return


## Issue #102 Phase 4: the server spends one dock good (sold fish/crop,
## bait, fertilizer) from the peer's own stack. Mirrors consume_seed_item:
## inventory is per-peer authoritative, so the server rpc_ids the owner and
## the client drops from its own stack.
@rpc("any_peer", "call_local")
func consume_dock_good(item_id: String) -> void:
	if not is_multiplayer_authority():
		return
	for i in range(inventory.size()):
		var entry: Dictionary = inventory[i]
		var item := entry["item"] as ItemData
		if item != null and item.id == item_id:
			var had := int(entry["count"])
			entry["count"] = int(entry["count"]) - 1
			if int(entry["count"]) <= 0:
				_audit_inventory("consume_dock_good", item.id, had, i, _entry_equipped_slot(entry))
				inventory.remove_at(i)
			_recalc_stats()
			if hud != null:
				hud.refresh_inventory(self)
				hud.refresh_loadout(self)
			return


## Issue #102 Phase 4: spend n farm cash from the peer's own stack.
@rpc("any_peer", "call_local")
func consume_farm_cash(n: int) -> void:
	if not is_multiplayer_authority():
		return
	for i in range(inventory.size()):
		var entry: Dictionary = inventory[i]
		var item := entry["item"] as ItemData
		if item != null and item.id == "farm_cash":
			var had := int(entry["count"])
			entry["count"] = int(entry["count"]) - n
			if int(entry["count"]) <= 0:
				_audit_inventory("consume_farm_cash", item.id, had, i, _entry_equipped_slot(entry))
				inventory.remove_at(i)
			_recalc_stats()
			if hud != null:
				hud.refresh_inventory(self)
				hud.refresh_loadout(self)
			return


## Issue #102 Phase 4: farm cash balance as seen in this peer's inventory
## (display mirror; the server's DockEconomy ledger is authoritative).
func farm_cash_count() -> int:
	for entry in inventory:
		var item := entry["item"] as ItemData
		if item != null and item.id == "farm_cash":
			return int(entry["count"])
	return 0


## Issue #102 Phase 4: tick down wave-counted buffs. The dungeon broadcasts
## this per cleared wave (server); each peer decrements its own player.
@rpc("any_peer", "call_local")
func on_wave_cleared() -> void:
	for stat in _wave_buffs:
		var w: Dictionary = _wave_buffs[stat]
		w["waves"] = maxi(0, int(w["waves"]) - 1)


## Base camera FOV from the settings panel (default 75).
func _base_fov() -> float:
	if has_node("/root/SaveManager"):
		return float(get_node("/root/SaveManager").get_profile_setting("settings", "fov", 75.0))
	return 75.0


func _buff_mult(stat: String) -> float:
	var mult := 1.0
	var b: Dictionary = _buffs.get(stat, {"mult": 1.0, "until": 0.0})
	if Time.get_ticks_msec() / 1000.0 < float(b["until"]):
		mult *= float(b["mult"])
	# Issue #102 Phase 4: wave-counted buffs stack multiplicatively too.
	var wb: Dictionary = _wave_buffs.get(stat, {"mult": 1.0, "waves": 0})
	if int(wb["waves"]) > 0:
		mult *= float(wb["mult"])
	# War Horn totem aura: +25% damage, scaled by Warden/Conqueror aura strength.
	if stat == "damage" and _warhorn_t > 0.0:
		mult *= 1.0 + 0.25 * _warhorn_strength
	# Rally totem aura: +30% speed, scaled by aura strength.
	if stat == "speed" and _rally_t > 0.0:
		mult *= 1.0 + 0.3 * _rally_strength
	# Shared Vitality: Stoneskin also grants +10% move speed.
	if stat == "speed" and _shared_vitality_t > 0.0:
		mult *= 1.1
	return mult


func _check_buff_expiry() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for stat in ["speed", "damage"]:
		if _buff_announced.get(stat, false) and now >= float(_buffs[stat]["until"]):
			_buff_announced[stat] = false
			if hud != null:
				hud.toast("%s boost wore off." % stat.capitalize())


@rpc("any_peer", "call_local")
func take_damage(amount: float, attacker_name: String = "") -> void:
	if not is_multiplayer_authority():
		return
	if not alive:
		return
	# Pause menu = breather: mobs keep acting, but a paused player's
	# health doesn't budge. Per-peer, so multiplayer keeps working.
	if hud != null and hud.is_paused:
		return
	# Inventory open = alternative pause screen (Jesse 2026-10-13):
	# the same breather rule at the same seam. Every damage source
	# delivers here via rpc_id to this player's authority peer, and
	# hud on that peer is the local HUD — so this gate holds in solo
	# and multiplayer alike, with no state sync needed.
	if hud != null and hud.inventory_open:
		return
	# Dash i-frames.
	if _dash_t > 0.0:
		return
	# Sanctuary Totem (Warden signature): complete damage immunity.
	if _sanctuary_t > 0.0:
		return
	# Stoneskin: -30% damage taken, scaled by Warden aura strength.
	if _stoneskin_t > 0.0:
		amount *= 1.0 - 0.3 * _stoneskin_strength
	# Reinforce (Architect): -50% damage taken. (take_damage applies no
	# knockback, so there is nothing further to skip.)
	if _reinforce_t > 0.0:
		amount *= 1.0 - _reinforce_strength
	# Issue #210 (Rooted Ward): standing inside any of
	# your own totems' radii reduces damage taken.
	var ward_pct := _tree_behavior_pct("rooted_ward")
	if ward_pct > 0.0:
		var my_peer := int(multiplayer.get_unique_id())
		for n in get_tree().get_nodes_in_group("totems"):
			if int(n.get("owner_peer")) == my_peer \
					and global_position.distance_to(n.global_position) < float(n.call("aura_radius")):
				amount *= 1.0 - ward_pct / 100.0
				break
	# Barnacle Bulwark (issue #102): wave-counted damage reduction.
	amount *= _buff_mult("defense")
	# Remember who hit us so the death screen can name the killer.
	if not attacker_name.is_empty():
		run_death_cause = attacker_name
	hp = maxf(0.0, hp - amount)
	_shake = 0.3
	health_changed.emit(hp, max_hp)
	_update_health_bar()
	AudioManager.sfx("player_hurt")
	if hud != null:
		hud.flash_damage()
	if hp <= 0.0 and second_wind_armed:
		# Iron Resolve (issue #6): once per run, survive a killing blow at 1 HP.
		hp = 1.0
		second_wind_armed = false
		second_wind_used = true
		health_changed.emit(hp, max_hp)
		if hud != null:
			hud.show_toast("SECOND WIND! Iron Resolve holds you at 1 HP.")
		AudioManager.sfx("unlock")
		return
	if hp <= 0.0:
		_die()


func _die() -> void:
	# In co-op, go down instead of dying outright — a teammate can revive.
	if not downed and multiplayer.get_peers().size() > 0:
		_enter_downed()
		return
	_do_death()


func _enter_downed() -> void:
	downed = true
	alive = false
	no_death_streak = 0 # Relic Vault (issue #6): going down breaks the streak.
	_bleedout = REVIVE_WINDOW
	_revive_channel = 0.0
	died.emit()
	AudioManager.sfx("player_die")
	rpc("set_downed", true)
	if hud != null:
		hud.show_downed(REVIVE_WINDOW)


@rpc("any_peer", "call_local")
func set_downed(d: bool) -> void:
	downed = d
	if not d:
		_hide_downed_marker()
		return
	# Downed marker: world-space "!" above the player so teammates can spot
	# them in a fight (Jesse 2026-10-10). Code-generated, no art assets.
	# Hidden on the downed player's own instance — they have the HUD timer.
	if not is_multiplayer_authority():
		_show_downed_marker()


## Pulsing "!" marker above a downed teammate. Renders through walls
## (no_depth_test) so they're findable in a chaotic fight.
func _show_downed_marker() -> void:
	if _downed_marker == null:
		_downed_marker = Label3D.new()
		_downed_marker.name = "DownedMarker"
		_downed_marker.text = "!"
		_downed_marker.font_size = 128
		_downed_marker.modulate = Color(1.0, 0.25, 0.25)
		_downed_marker.outline_size = 16
		_downed_marker.outline_modulate = Color(0, 0, 0, 1)
		_downed_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_downed_marker.no_depth_test = true
		_downed_marker.position = Vector3(0, 2.4, 0)
		add_child(_downed_marker)
	_downed_marker.visible = true


func _hide_downed_marker() -> void:
	if _downed_marker != null:
		_downed_marker.visible = false


## Called on the downed player's authority by the server, against
## its validated channel record (issue #163 Part 3).
@rpc("any_peer", "call_local")
func revive() -> void:
	if not is_multiplayer_authority():
		return
	# Issue #163 Part 3: the only road in is the server's validated
	# completion (or a direct local call on this instance) — a
	# bare client rpc is refused, so the channel record is the
	# sole path and R3's unvalidated endpoint is closed.
	# Issue #172: that completion is now the pool's — the server
	# fires it from _srv_credit_revive when the pool fills.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_peer_id:
		return
	if not downed:
		return
	downed = false
	_bleedout = 0.0
	alive = true
	hp = max_hp * 0.5
	health_changed.emit(hp, max_hp)
	rpc("set_downed", false)
	AudioManager.sfx("revive")
	if hud != null:
		hud.hide_downed()
		hud.hide_revive_progress() # issue #172: the pooled bar clears with the revive
		hud.toast("Revived! Back in the fight.")


func _do_death() -> void:
	downed = false
	alive = false
	no_death_streak = 0 # Relic Vault (issue #6): dying breaks the streak.
	died.emit()
	AudioManager.sfx("player_die")
	# TEMPORARY #136 diagnostic: record the full stack list before the wipe.
	if not inventory.is_empty():
		var parts: Array[String] = []
		var total := 0
		for e in inventory:
			var it := e["item"] as ItemData
			parts.append("%sx%d" % [it.id if it != null else "?", int(e["count"])])
			total += int(e["count"])
		_audit_inventory("death_clear", "", total, -1, "", "stacks=" + ",".join(parts))
	inventory.clear()
	_recalc_stats()
	if hud != null:
		hud.hide_downed()
		hud.refresh_inventory(self)
		hud.refresh_loadout(self)
	die()


## Death presentation. In solo the run ends here: show the death screen
## with run stats (no auto-respawn). In co-op the party keeps playing, so
## the toast + 3s respawn path is kept.
func die() -> void:
	# Issue #91 Phase 1: death disarms Holy Light.
	# Issue #91 Phase 2: death also ends an active beam.
	if _hl_state == HLState.ARMED or _hl_state == HLState.CHARGING:
		_hl_disarm()
	if _hl_state == HLState.ACTIVE:
		rpc("hl_end_beam", int(multiplayer.get_unique_id()), 0) # issue #171: seq 0 = all my beams (death cleanup)
	# Bounty Board (issue #7): a death fails this player's no_death bounty.
	# Server-authoritative: clients route through the server.
	var bdgn := get_tree().get_first_node_in_group("dungeon")
	if bdgn != null and bdgn.has_method("bounty_death_local"):
		if multiplayer.is_server():
			bdgn.bounty_death_local(multiplayer.get_unique_id())
		else:
			bdgn.rpc_id(NetworkManager.server_peer_id, "notify_bounty_death")
	if multiplayer.get_peers().size() == 0:
		# Solo run over: the save point is gone.
		# Record daily attempt if this was today's seed.
		if Dungeon.next_seed == DailyRun.get_today_seed():
			var stats := run_stats()
			var score := int(stats.get("cycle", 1)) * 1000 + int(stats.get("level", 1)) * 10 + int(stats.get("kills", 0))
			# Echoes (issue #9 Phase 2): stop the 10Hz recording. If this is
			# the player's best daily score, save the echo for ghost racing.
			# Runtime autoload lookup avoids compile-time dependencies.
			var _rec: Node = get_tree().root.get_node_or_null("EchoRecorder")
			var _daily: Node = get_tree().root.get_node_or_null("DailyRun")
			if _rec != null and _daily != null:
				var echo_data: Dictionary = _rec.call("stop_recording")
				var is_best := score > int(_daily.call("get_best_score"))
				_daily.call("record_attempt", score)
				if is_best and int(echo_data.get("sample_count", 0)) > 0:
					_rec.call("save_echo", echo_data,
						_rec.call("echo_path_for_date", _daily.call("get_today_string")))
					# Phase 3: share the best echo to the Workshop (guarded,
					# silent no-op offline).
					var _ws: Node = get_tree().root.get_node_or_null("WorkshopEcho")
					if _ws != null:
						_ws.call("upload_today_best")
			else:
				DailyRun.record_attempt(score)
		# Issue #205 (Jesse's Act 2 ruling): death inside a
		# building respawns at that building's ground floor —
		# the run is NOT over.
		if Dungeon.floor_active():
			NetworkManager.rpc("load_floor",
				Dungeon.floor_key, 0, false)
			return
		SaveManager.clear_run(SaveManager.MODE_SOLO, NetworkManager.active_run_slot)
		if hud != null:
			hud.show_death_screen(run_stats())
		return
	# Multiplayer: check for party wipe (server clears the run).
	# Route through the server since die() runs on the player's authority.
	# (SteamMultiplayerPeer can't rpc_id its own peer ID: call directly as server.)
	var dgn := get_tree().get_first_node_in_group("dungeon")
	if dgn != null and dgn.has_method("notify_player_died"):
		if multiplayer.is_server():
			dgn.notify_player_died()
		else:
			dgn.rpc_id(NetworkManager.server_peer_id, "notify_player_died")
	if hud != null:
		hud.toast("You died! You lost all your items.")
	await get_tree().create_timer(3.0).timeout
	if not is_inside_tree():
		return
	var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
	if dungeon != null:
		global_position = dungeon.get_spawn_point()
	hp = max_hp
	alive = true
	health_changed.emit(hp, max_hp)


## Run statistics for the death screen. Persists across level transitions
## (saved in get_state), resets on a new run (play_solo clears the save).
func run_stats() -> Dictionary:
	var cycle := 1
	var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
	if dungeon != null:
		cycle = dungeon.get_cycle_number()
	var secs := maxi(0, int((Time.get_ticks_msec() - run_start_msec) / 1000))
	return {
		"time_sec": secs,
		"kills": run_kills,
		"level": level,
		"cycle": cycle,
		"damage": run_damage_dealt,
		"cause": run_death_cause,
	}


@rpc("any_peer", "call_local")
func gain_xp(amount: int, track_kill: bool = true) -> void:
	if not is_multiplayer_authority():
		return
	# Issue #11 Phase 1: Ascension buff (account-wide, per-player in MP).
	var asc_mult := SaveManager.get_ascension_xp_mult()
	xp += int(amount * xp_mult * asc_mult)
	if track_kill:
		_register_kill()
	var grew := false
	var prev_level := level
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = int(25.0 * pow(level, 1.4))
		stat_points += 3
		grew = true
		leveled_up.emit(level)
	_recalc_stats()
	xp_changed.emit(xp, xp_next, level)
	# Specialization unlocks at 20.
	if prev_level < SPECIALIZATION_UNLOCK_LEVEL and level >= SPECIALIZATION_UNLOCK_LEVEL:
		if hud != null:
			hud.announce("Specialization unlocked — choose a skill in the abilities menu")
			AudioManager.sfx("ability_unlock")
	if grew:
		Effects.burst(get_parent(), global_position + Vector3(0, 1.2, 0), Color(1.0, 0.8, 0.2), 26, 6.0)
		AudioManager.sfx("levelup")
		var new_ability := refresh_abilities()
		_update_staff_glow()
		_push_aura()
		_check_milestone()
		if hud != null:
			hud.toast(PromptText.resolve("Level up! +3 stat points ({pause} to spend)."))
			if not new_ability.is_empty():
				hud.toast("New ability unlocked: %s!" % [String(new_ability["name"])])
				AudioManager.sfx("ability_unlock")
			hud.refresh_loadout(self)


func _check_milestone() -> void:
	var names := {25: "Milestone: +10% damage & health!", 50: "Milestone: +10% damage & health!",
		75: "Milestone: +15% damage & health!", 100: "PARAGON! +25% to everything!"}
	if names.has(level):
		_recalc_stats()
		AudioManager.sfx("milestone")
		if hud != null:
			hud.announce(String(names[level]))


var _streak_kills := 0
var _streak_timer := 0.0


## Multi-kill announcements: 2 = Double Kill, 3 = Triple Kill, 4+ = Rampage.
func _register_kill() -> void:
	run_kills += 1
	_streak_kills += 1
	_streak_timer = 3.0
	# Affinity: kill while veiled → +1 smoke_veil, max +10/activation.
	if stealthed:
		gain_affinity_capped("smoke_veil", 1.0, -1, "veil_%d" % _cast_seq, 10.0)
	if hud == null:
		return


@rpc("any_peer", "call_local")
func notify_mark_kill() -> void:
	if not is_multiplayer_authority():
		return
	gain_affinity("mark", 3.0)
	match _streak_kills:
		2:
			hud.announce("DOUBLE KILL!")
			AudioManager.sfx("pickup", null, 1.3)
		3:
			hud.announce("TRIPLE KILL!")
			AudioManager.sfx("pickup", null, 1.45)
		4:
			hud.announce("RAMPAGE!")
			AudioManager.sfx("levelup", null, 1.2)


## Issue #189 (section 3): a target THIS player marked has
## died — by any means, at either of the mob's two
## kill-decision sites. Eagle Eye becomes usable again THIS
## wave. Only a spent Eagle Eye refreshes: the wave-equality
## guard means an unspent one gains nothing and no second
## charge can ever bank. Silent by ruling (section 4): no
## toast, no sfx — the slot visibly re-enables via
## Issue #210 (Coup de Grâce): the server reports that
## this player's Assassinate strike killed — a killing
## Assassinate resets its own cooldown.
## Issue #210 slice B5 (spec section 3): Adrenaline — the
## server reports a kill credited to this player (routed
## through the two mob death sites, the coup discipline);
## the buff writes a timed var read by the atk_spd chain.
@rpc("any_peer", "call_local")
func notify_tree_kill() -> void:
	if not is_multiplayer_authority():
		return
	var pct := _tree_behavior_pct("adrenaline")
	if pct > 0.0:
		_tree_adrenaline_pct = pct
		_tree_adrenaline_until = \
			Time.get_ticks_msec() + 3000


@rpc("any_peer", "call_local")
func notify_coup_kill() -> void:
	if not is_multiplayer_authority():
		return
	if _tree_variant("assassinate") == "coup_de_grace":
		ability_cds["assassinate"] = 0.0
		if hud != null:
			hud.refresh_abilities(self)


## refresh_abilities.
@rpc("any_peer", "call_local")
func notify_marked_target_died() -> void:
	if not is_multiplayer_authority():
		return
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	var wave := 0
	if dungeon != null and "wave" in dungeon:
		wave = int(dungeon.get("wave"))
	if eagle_eye_used_wave == wave:
		eagle_eye_used_wave = -1
		if hud != null:
			hud.refresh_abilities(self)


## Spend one stat point. Returns false when there is nothing to spend.
func spend_point(stat: String) -> bool:
	if stat_points <= 0:
		return false
	match stat:
		"damage":
			bonus_damage += 2.0
		"health":
			bonus_health += 12.0
			hp += 12.0
		"speed":
			bonus_speed += 0.15
		"atk_spd":
			# Issue #184: flat per point — NO cap and NO class
			# gate (the aura arm's gate/cap are its own; this
			# stat is universal by design). Issue #192
			# (Jesse's tuning order): +1% per point (was
			# +0.1%); stored v1 bonuses rescale in
			# SaveManager.migrate_run so spent points keep
			# their value.
			bonus_atk_spd += 0.01
		"aura":
			if class_id != "mage":
				return false
			if bonus_aura >= 20.0:
				return false  # capped at 20
			bonus_aura += 1.0
			_update_staff_glow()
			_push_aura()
			if bonus_aura >= 20.0:
				# Relic Vault (issue #6): 20 aura EARNS the Holy Light special
				# into the account vault; the key-7 ability itself is granted
				# only while it is equipped for the run.
				SpecialData.earn_for(self, "holy_light")
				refresh_abilities()
				# Issue #88: communicate the equip requirement in-game.
				if hud != null and equipped_special != "holy_light":
					hud.toast("Holy Light earned! Equip it in the Relic Vault (station annex) to use [7].")
		_:
			return false
	stat_points -= 1
	_recalc_stats()
	hp = minf(hp, max_hp)
	health_changed.emit(hp, max_hp)
	if hud != null:
		hud.refresh_stats()
		hud.refresh_loadout(self)
	return true


# --- Relic Vault specials (issue #6) ---
# Condition-gated bonus rewards outside the level/affinity tracks. Exactly
# one equipped per run; earn checks run server-side, grants land in the
# earner's own account profile (never the host's).

## Apply the run's equipped special: derived effects + Holy Light migration.
## Called on spawn, on state restore, and on equip/unequip. Idempotent.
func _apply_equipped_special() -> void:
	# Migration: mages that invested 20 aura keep Holy Light via earn.
	# Issue #206 (spec section 5): the earn reads the COMBINED
	# aura (base + tree), as specced.
	if class_id == "mage" and bonus_aura + _tree_stat("aura") >= SpecialData.AURA_EARN_REQ:
		SpecialData.earn_for(self, "holy_light")
	# Derived effects reset first: unequipping or switching can never stack.
	cash_mult = 1.0
	second_wind_armed = false
	special_hp_mult = 1.0
	special_pickup_mult = 1.0
	special_cooldown_mult = 1.0
	match equipped_special:
		"iron_resolve":
			if not second_wind_used:
				second_wind_armed = true
		"greed_charm":
			var charm := SpecialData.get_special("greed_charm")
			if charm != null:
				cash_mult = float(charm.effect_params.get("cash_mult", 1.25))
		"holy_light":
			pass # key-7 entry granted by refresh_abilities() below
		"apex_boar_hide", "apex_horror_eye", "apex_warden_sigil":
			# Apex relics (issue #5): multipliers read from effect_params.
			var apex := SpecialData.get_special(equipped_special)
			if apex != null:
				special_hp_mult = float(apex.effect_params.get("max_hp_mult", 1.0))
				special_pickup_mult = float(apex.effect_params.get("pickup_mult", 1.0))
				special_cooldown_mult = float(apex.effect_params.get("cooldown_mult", 1.0))
	_recalc_stats()
	refresh_abilities()


## Level cleared without dying: bump the streak. Three in a row earns Iron Resolve.
func bump_no_death_streak() -> void:
	no_death_streak += 1
	if no_death_streak >= SpecialData.IRON_RESOLVE_STREAK:
		SpecialData.earn_for(self, "iron_resolve")


## Server drives, owners apply: bump the streak on the player's own instance
## so the saved state (solo + MP roster submit) carries it.
@rpc("any_peer", "call_local")
func rpc_level_cleared_streak() -> void:
	if not is_multiplayer_authority():
		return
	bump_no_death_streak()


## Grant a special into the earner's OWN account profile. Server-side earn
## checks route here; the authority guard drops it everywhere but home.
## Idempotent: toasts only on a genuinely new earn.
@rpc("any_peer", "call_local")
func rpc_earn_special(special_id: String) -> void:
	if not is_multiplayer_authority():
		return
	if SpecialData.earn(special_id):
		var data := SpecialData.get_special(special_id)
		if data != null and hud != null:
			hud.show_toast("SPECIAL EARNED: %s — %s" % [data.display_name, data.description])
		AudioManager.sfx("relic_pickup")


## Serialize run-persistent state so it survives procedural level transitions.
## Issue #111 PF Phase 2: the player_state keys apply_state consumes.
## Any OTHER key in a loaded state is stashed in _state_extras and
## merged back by get_state() — unknown keys (written by a newer build
## or a future converter) survive a load -> continue -> save cycle
## losslessly instead of being silently dropped at restore.
const STATE_KEYS: Array[String] = [
	"level", "xp", "xp_next", "stat_points", "bonus_damage",
	"bonus_health", "bonus_speed", "bonus_aura", "bonus_atk_spd", "inventory",
	"run_start_msec", "run_kills", "run_damage_dealt",
	"supermarket_cash", "bounty_progress", "totem_charges",
	"specialization", "affinity", "family_collection", "run_signatures",
	"tree_seed", "tree_owned", "tree_lifetime",
	"equipped_special", "no_death_streak", "second_wind_armed",
	"second_wind_used",
]
var _state_extras: Dictionary = {}


## Issue #111 minor 1: inventory entries the most recent apply_state
## dropped because their item id no longer resolves in ItemDB
## ([{"id": String, "count": int}]). Empty when the restore was clean.
var last_restore_dropped: Array = []


func _deep_dup(v: Variant) -> Variant:
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	if v is Array:
		return (v as Array).duplicate(true)
	return v


func get_state() -> Dictionary:
	var inv: Array = []
	for entry in inventory:
		var item := entry["item"] as ItemData
		if item != null:
			# Issue #104 Phase 1: persist the equip marker as "slot".
			# Issue #113 Phase 1: persist the stack's upgrade level
			# (additive known key; old saves without it read as 0).
			inv.append({"id": item.id, "count": int(entry["count"]),
				"slot": _entry_equipped_slot(entry),
				"upgrade_level": int(entry.get("upgrade_level", 0))})
	var state := {
		"level": level,
		"xp": xp,
		"xp_next": xp_next,
		"stat_points": stat_points,
		"bonus_damage": bonus_damage,
		"bonus_health": bonus_health,
		"bonus_speed": bonus_speed,
		"bonus_aura": bonus_aura,
		"bonus_atk_spd": bonus_atk_spd,
		"inventory": inv,
		"run_start_msec": run_start_msec,
		"run_kills": run_kills,
		"run_damage_dealt": run_damage_dealt,
		"supermarket_cash": supermarket_cash,
		"bounty_progress": bounty_progress.duplicate(true),
		"totem_charges": totem_charges,
		"specialization": specialization,
		"affinity": affinity.duplicate(true),
		"family_collection": family_collection.duplicate(true),
		"run_signatures": run_signatures.duplicate(true),
		# Issue #206 (spec section 7): three additive keys,
		# no SAVE_VERSION bump — derived state stays unsaved.
		"tree_seed": tree_seed,
		"tree_owned": tree_owned.duplicate(),
		"tree_lifetime": tree_lifetime.duplicate(true),
		# Relic Vault (issue #6): equipped special + earn tracking.
		"equipped_special": equipped_special,
		"no_death_streak": no_death_streak,
		"second_wind_armed": second_wind_armed,
		"second_wind_used": second_wind_used,
	}
	# PF Phase 2: carried-through unknown keys ride along (live fields
	# above always win — a key that becomes consumed later takes over).
	for k in _state_extras:
		if not state.has(k):
			state[k] = _deep_dup(_state_extras[k])
	return state


## Restore state after a level transition. Full heal on arrival.
func apply_state(s: Dictionary) -> void:
	# TEMPORARY #136 diagnostic: per-item totals claimed by the incoming
	# state, diffed against the reconstruction at the end of the
	# function — only actual drops are audited.
	var _audit_before := {}
	for e in (s.get("inventory", []) as Array):
		if e is Dictionary:
			var eid := str((e as Dictionary).get("id", ""))
			if eid != "":
				_audit_before[eid] = int(_audit_before.get(eid, 0)) \
					+ int((e as Dictionary).get("count", 1))
	# PF Phase 2: stash every key this build does NOT consume, so
	# get_state() can merge it back verbatim (lossless round-trip).
	_state_extras.clear()
	for k in s.keys():
		if not STATE_KEYS.has(k):
			_state_extras[k] = _deep_dup(s[k])
	level = int(s.get("level", 1))
	xp = int(s.get("xp", 0))
	xp_next = int(s.get("xp_next", 25))
	stat_points = int(s.get("stat_points", 0))
	bonus_damage = float(s.get("bonus_damage", 0.0))
	bonus_health = float(s.get("bonus_health", 0.0))
	bonus_speed = float(s.get("bonus_speed", 0.0))
	bonus_aura = float(s.get("bonus_aura", 0.0))
	bonus_atk_spd = float(s.get("bonus_atk_spd", 0.0))
	run_start_msec = int(s.get("run_start_msec", Time.get_ticks_msec()))
	run_kills = int(s.get("run_kills", 0))
	run_damage_dealt = float(s.get("run_damage_dealt", 0.0))
	supermarket_cash = int(s.get("supermarket_cash", 0))
	bounty_progress = (s.get("bounty_progress", {}) as Dictionary).duplicate(true)
	totem_charges = int(s.get("totem_charges", 0))
	specialization = str(s.get("specialization", ""))
	affinity = (s.get("affinity", {}) as Dictionary).duplicate(true)
	family_collection = (s.get("family_collection", {}) as Dictionary).duplicate(true)
	run_signatures = (s.get("run_signatures", {}) as Dictionary).duplicate(true)
	# Legacy states saved before the run gate existed carry no
	# run_signatures key: a signature counts as run-earned there only if
	# THIS run's own affinity already reached 100 in that family (the book
	# flag plus maxed affinity is exactly what earning it produced) —
	# anything less stays locked until the milestone trips in play.
	if run_signatures.is_empty():
		var fams_legacy := Player.families()
		for fid_l in family_collection:
			var coll_l: Dictionary = family_collection[fid_l]
			if bool(coll_l.get("signature", false)) and fams_legacy.has(fid_l):
				for sk_l in fams_legacy[fid_l]["skills"]:
					if float(affinity.get(sk_l, 0.0)) >= 100.0:
						run_signatures[fid_l] = true
	# Issue #206: the stored seed wins; aggregates recompute
	# here so the recalc at this function's tail folds them.
	tree_seed = int(s.get("tree_seed", DeepTree.TREE_SEED))
	if tree_seed == 0:
		tree_seed = DeepTree.TREE_SEED
	tree_owned = []
	for tid in (s.get("tree_owned", []) as Array):
		tree_owned.append(int(tid))
	tree_lifetime = (s.get("tree_lifetime", {}) as Dictionary).duplicate(true)
	_recompute_tree_aggregates()
	# Relic Vault (issue #6): equipped special + earn tracking.
	equipped_special = str(s.get("equipped_special", ""))
	no_death_streak = int(s.get("no_death_streak", 0))
	second_wind_armed = bool(s.get("second_wind_armed", false))
	second_wind_used = bool(s.get("second_wind_used", false))
	_apply_equipped_special()
	inventory.clear()
	last_restore_dropped.clear()
	var raw_inv: Array = s.get("inventory", [])
	# Issue #104 Phase 1: a state is NEW-format when its entries carry the
	# "slot" key at all (even all-empty — a player who deliberately
	# unequipped everything must not be re-migrated). Marker-less states
	# are old saves and get the auto-equip migration below.
	var has_markers := false
	for e in raw_inv:
		if e is Dictionary and (e as Dictionary).has("slot"):
			has_markers = true
			break
	var claimed: Dictionary = {} # slot name -> true (one stack per slot)
	for e in raw_inv:
		var item := ItemDB.get_item(str(e.get("id", "")))
		if item != null:
			var marker := ""
			if has_markers:
				# Re-validate the saved marker: it must name the item's
				# own slot, the item must still be gear, this class must
				# still be allowed, and the slot must be unclaimed —
				# otherwise the marker is dropped.
				var want := str(e.get("slot", ""))
				if want != "" and want == ItemData.slot_name(item.slot) \
						and ItemData.is_gear(item) and _class_may_equip(item) \
						and not claimed.has(want):
					marker = want
					claimed[want] = true
			inventory.append({"item": item, "count": maxi(1, int(e.get("count", 1))),
				"equipped_slot": marker,
				# Issue #113 Phase 1: upgrade level (absent in old saves = 0).
				"upgrade_level": clampi(int(e.get("upgrade_level", 0)), 0, UPGRADE_LEVEL_CAP)})
		else:
			# Issue #111 minor 1: the id no longer resolves (item removed
			# or renamed between versions, DLC absent). The stack is
			# still dropped — it can't be instantiated — but never
			# silently: log it, collect it, and toast after the restore.
			var drop_id := str(e.get("id", ""))
			var drop_count := maxi(1, int(e.get("count", 1)))
			last_restore_dropped.append({"id": drop_id, "count": drop_count})
			push_warning("[Restore] Dropped unknown item '%s' x%d (not in ItemDB)" % [drop_id, drop_count])
	if not has_markers and not raw_inv.is_empty():
		_migrate_auto_equip()
	# Issue #113 Phase 3: restoring an architect re-grants any missing
	# starting tool into the bag (disposed tools are never permanently
	# lost; legacy architect saves gain both tools here — no converter).
	if class_id == "architect":
		ensure_architect_tools(false)
	alive = true
	_recalc_stats()
	_update_staff_glow()
	_push_aura()
	refresh_abilities()
	hp = max_hp
	health_changed.emit(hp, max_hp)
	xp_changed.emit(xp, xp_next, level)
	if hud != null:
		hud.refresh_inventory(self)
		hud.refresh_loadout(self)
		hud.refresh_stats()
		# Issue #140: the level label is written ONLY at HUD setup
		# and on level-up — a restore landing after setup (every
		# continued guest) must refresh it explicitly, the
		# switch_class precedent. Without this the restored guest
		# presents "Lv 1" while every field is correct.
		hud.set_level(level, self)
	# Issue #111 minor 1: one-line player notice when the restore
	# dropped stacks (see last_restore_dropped).
	if not last_restore_dropped.is_empty() and hud != null:
		hud.show_toast("Some items could not be restored")
	# TEMPORARY #136 diagnostic: audit only the items this reconstruction
	# actually dropped (a lossless apply emits nothing).
	var _audit_after := {}
	for e in inventory:
		var it1 := e["item"] as ItemData
		if it1 != null:
			_audit_after[it1.id] = int(_audit_after.get(it1.id, 0)) + int(e["count"])
	for id in _audit_before:
		var lost := int(_audit_before[id]) - int(_audit_after.get(id, 0))
		if lost > 0:
			_audit_inventory("apply_state", id, lost, -1)


## This peer's own level-entry state, captured on THIS machine at spawn
## (and again after a continued-state restore). The early-departure
## forfeit rolls back to it. Issue #134: the snapshot used to be taken
## by the server from its local node for the peer — for a remote peer
## that node is a replica whose authoritative fields (xp, inventory,
## stat points) never replicate, so the "entry state" was a fabricated
## fresh spawn and the forfeit destroyed the guest's real character.
var _entry_snapshot: Dictionary = {}


## Capture the entry state for a possible forfeit. Called by the
## dungeon on the OWNING peer only, once the spawn state is final.
func capture_entry_snapshot() -> void:
	_entry_snapshot = get_state()


## Roll back to this peer's own captured entry state. No capture, no
## forfeit — a missing snapshot must never be replaced by a guess.
func apply_forfeit_local() -> void:
	if _entry_snapshot.is_empty():
		return
	apply_forfeit(_entry_snapshot)


## Forfeit restore (Station Annex Phase 4): roll progression back to the
## level-entry snapshot. HP and alive status are NEVER touched — a dead
## player stays dead, a hurt player stays hurt.
func apply_forfeit(s: Dictionary) -> void:
	var keep_hp := hp
	var was_alive := alive
	apply_state(s)
	# apply_state() full-heals and marks alive; restore the true vitals and
	# refresh the HUD so the bars show the unhealed state.
	hp = minf(keep_hp, max_hp)
	alive = was_alive
	health_changed.emit(hp, max_hp)
	xp_changed.emit(xp, xp_next, level)
	if hud != null:
		hud.refresh_inventory(self)
		hud.refresh_stats()


## Server signals an early-departure forfeit (mirrors the heal pattern:
## the server can't write fields on a client-owned player node
## directly). Issue #134: the signal carries NO state — the rollback
## target is this peer's own captured entry snapshot, never a
## server-authored state.
@rpc("any_peer", "call_local")
func apply_forfeit_net() -> void:
	if int(get_multiplayer_authority()) != multiplayer.get_unique_id():
		return
	apply_forfeit_local()


## Issue #72/#104/#126/#133/#163: the 10 Hz state push. Extracted
## (issue #163) so the downed and dead authority paths emit too —
## downed/alive ride this stream, and replicas converge from it.
func _emit_snapshot(delta: float) -> void:
	_snapshot -= delta
	if _snapshot <= 0.0:
		_snapshot = SNAPSHOT_INTERVAL
		# Issue #133: never fire into a dead peer (the Oct 14 spam
		# site — 10 Hz of not-connected errors after the host died).
		if _mp_peer_connected():
			rpc("push_snapshot", global_position, hp, level, alive, _yaw, equipped_ids, rod_out, max_hp, downed, _revive_pool_frac, bonus_atk_spd + _tree_stat("atk_spd"))


## Issue #164 (parts A + C): a puppet's presentation follows its
## CURRENT authority and identity, re-derived every tick. _ready
## hides the sprite/label and writes the name ONCE — if authority
## or the advertised steam id was wrong at that instant (the
## engine-default authority at _ready, a Steam layer that had
## not initialized when the handshake went out), the wrong state
## latched forever. Re-asserting here removes the permanence
## instead of hunting the trigger.
func _refresh_puppet_presentation() -> void:
	if _sprite != null and not _sprite.visible:
		_sprite.visible = true
	var lbl := get_node_or_null("Label3D") as Label3D
	if lbl != null:
		if not lbl.visible:
			lbl.visible = true
		var nm := _display_name()
		if lbl.text != nm:
			lbl.text = nm


@rpc("any_peer", "call_local", "unreliable")
func push_snapshot(pos: Vector3, hp_v: float, lvl: int, alive_v: bool, yaw_v: float, eq_ids: Dictionary = {}, rod_out_v: bool = false, max_hp_v: float = 0.0, downed_v: bool = false, pool_frac_v: float = 0.0, atk_spd_v: float = 0.0) -> void:
	if is_multiplayer_authority():
		return
	_remote_pos = pos
	_remote_yaw = yaw_v
	_has_remote = true
	hp = hp_v
	# Issue #167 (gate condition): max_hp rides the snapshot — a
	# leveled puppet's max moves during the run, and a bar drawn
	# against the spawn max reads the wrong fraction. (Mobs need
	# no such ride: their max is fixed at spawn.)
	if max_hp_v > 0.0:
		max_hp = max_hp_v
	# Issue #163 Part 1: downed rides the snapshot too — the
	# continuously-applied truth channel. A replica whose flag
	# went stale (the death path sent no clear) converges within
	# one interval, marker included.
	if downed_v != downed:
		downed = downed_v
		if downed:
			_show_downed_marker()
		else:
			_hide_downed_marker()
	# Issue #172: the revive pool fraction rides the snapshot
	# too — the server seeds it on every copy via
	# sync_revive_pool and the owner's stream carries the
	# latest value onward, so all copies render the same bar.
	_revive_pool_frac = pool_frac_v
	# Issue #184 (section 2): the ATK SPD investment rides the
	# snapshot — the self-healing channel (the event-RPC
	# alternative was rejected on the record); its convergence
	# window errs stricter-only, since a stale mirror reads a
	# SMALLER multiplier and therefore a longer gate.
	net_bonus_atk_spd = atk_spd_v
	level = lvl
	alive = alive_v
	if eq_ids != equipped_ids:
		equipped_ids = eq_ids.duplicate()
		_refresh_held_props()
	if rod_out_v != rod_out:
		rod_out = rod_out_v
		_refresh_held_props()
	_update_health_bar()


## Bounty Board (issue #7): server-triggered completion toast.
@rpc("any_peer", "call_local", "reliable")
func show_bounty_complete(bounty_name: String, cash: int, xp: int) -> void:
	if hud == null:
		return
	hud.show_toast("BOUNTY COMPLETE: %s (+$%d +%d XP)" % [bounty_name, cash, xp])
	AudioManager.sfx("bounty_complete")


@rpc("any_peer", "call_local", "reliable")
func show_achievement_unlock(achievement_ids: Array) -> void:	# Shows achievement unlock toasts.
	if hud == null:
		return
	for ach_id in achievement_ids:
		var progress: Dictionary = SaveManager.get_achievement_progress(str(ach_id))
		if not progress.is_empty():
			hud.show_toast("ACHIEVEMENT: %s — %s" % [progress["name"], progress["desc"]])
			AudioManager.sfx("unlock")


## Jesse 2026-10-11: floating health bar above the player.
## Visible to all players in multiplayer (world-space, billboarded).
## Single Sprite3D with dynamically drawn texture (border + fill).
static var _phb_white_tex: Texture2D = null

func _build_health_bar() -> void:
	var bar := Node3D.new()
	bar.name = "HealthBar"
	# Above the name Label3D (y=2.1).
	bar.position = Vector3(0, 2.5, 0)
	add_child(bar)
	_phb_full_w = 1.4
	_phb_bar_h = 0.22
	_phb_img_w = 200
	_phb_img_h = 22
	_phb_image = Image.create(_phb_img_w, _phb_img_h, false, Image.FORMAT_RGBA8)
	_phb_tex = ImageTexture.create_from_image(_phb_image)
	var spr := Sprite3D.new()
	spr.texture = _phb_tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.no_depth_test = false  # depth-tested (Jesse #195): bars occlude behind walls
	spr.scale = Vector3(_phb_full_w / (_phb_img_w * 0.01), _phb_bar_h / (_phb_img_h * 0.01), 1)
	bar.add_child(spr)
	_phb_fill = spr
	_update_health_bar()


## Redraw the bar texture: dark border + red fill proportional to HP.
func _update_health_bar() -> void:
	if _phb_fill == null or not is_instance_valid(_phb_fill) or _phb_image == null:
		return
	var frac := 0.0
	if max_hp > 0.0:
		frac = clampf(hp / max_hp, 0.0, 1.0)
	var border := 3
	_phb_image.fill(Color(0.05, 0.05, 0.07, 0.92))
	var iw := _phb_img_w - border * 2
	var ih := _phb_img_h - border * 2
	var fill_w := int(iw * frac)
	if fill_w > 0:
		for y in range(ih):
			var t := float(y) / float(maxi(ih - 1, 1))
			var col := Color(0.85, 0.12, 0.10).lerp(Color(0.55, 0.05, 0.05), t)
			for x in range(fill_w):
				_phb_image.set_pixel(border + x, border + y, col)
	_phb_tex.update(_phb_image)
