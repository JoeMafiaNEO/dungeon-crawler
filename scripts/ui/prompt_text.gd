class_name PromptText
extends RefCounted
## PromptText (issue #152, #144 Phase 2A-2): the ONE resolver that
## renders prompt strings for the current input source.
##
## Prompt strings across the game carry ACTION TOKENS — "{interact}",
## "{attack}", "{close}" — and every surface renders them through
## here: resolve() swaps each token for the label of that action on
## the CURRENT source (InputSource): the keyboard/mouse name, or the
## PAD Xbox-style text label. No call site ever branches on the
## device itself; when the source flips, the same template renders
## the other family.
##
## LABELS is the text rendering of the Phase 1 binding record
## (project.godot's InputMap, pinned literally by the suite's
## vocabulary sections): interact E/X, attack mouse/RT, cycle Q on
## LB/RB, pause Esc/Menu, and so on. A few entries are DISPLAY
## tokens rather than single actions — {move} (the WASD family /
## left stick), {look}, {choose} (the pick verb of a sentence) and
## the close-key composites {close_keys} / {close_keys_tight}: a
## popup's truthful close keys are "E / Esc" on keyboard but only
## "B" on pad (2A-1 routes pad closes through ui_cancel alone), so
## the pair is one resolver-level token instead of a lying template.
##
## GLYPHS are caption-form overrides for button-slot captions (the
## mouse legend): the same actions whose sentence form is a word
## ("Click", "G") caption as the physical control ("LMB", "MMB").
##
## Q6 holds here too: there are deliberately NO tokens for
## ability_1..7 / signature_ability — direct-select stays
## keyboard-only and no prompt can render it for a pad.

const LABELS := {
	"interact": {"kb": "E", "pad": "X"},
	"attack": {"kb": "Click", "pad": "RT"},
	"attack_phrase": {"kb": "Left click", "pad": "RT"},
	"alt_attack": {"kb": "Right Click", "pad": "LT"},
	"jump": {"kb": "Space", "pad": "A"},
	"dash": {"kb": "Shift", "pad": "LS Click"},
	"ability": {"kb": "T", "pad": "Y"},
	"cycle_ability": {"kb": "Q", "pad": "LB/RB"},
	"start_wave": {"kb": "R", "pad": "D-Pad Up"},
	"potion": {"kb": "H", "pad": "D-Pad Down"},
	"inventory": {"kb": "I", "pad": "View"},
	"pause": {"kb": "Esc", "pad": "Menu"},
	"ping": {"kb": "G", "pad": "RS Click"},
	"toggle_rod": {"kb": "V", "pad": "D-Pad Left"},
	"build_menu": {"kb": "B", "pad": "D-Pad Right"},
	"close": {"kb": "Esc", "pad": "B"},
	"move": {"kb": "WASD", "pad": "Left Stick"},
	"look": {"kb": "mouse", "pad": "right stick"},
	"choose": {"kb": "Click", "pad": "Select"},
	"close_keys": {"kb": "E / Esc", "pad": "B"},
	"close_keys_tight": {"kb": "E/Esc", "pad": "B"},
}

const GLYPHS := {
	"attack": {"kb": "LMB", "pad": "RT"},
	"alt_attack": {"kb": "RMB", "pad": "LT"},
	"ping": {"kb": "MMB", "pad": "RS Click"},
}


## `source` is an InputSource.Source value; -1 (the default) reads
## the live source from the InputSource autoload.
static func _pad(source: int) -> bool:
	if source >= 0:
		return source == 1
	return InputSource.is_pad()


# --- Issue #190: the Steam tier ---
## Above the native tables sits a Steam tier, consulted ONLY
## when the source is PAD, the SteamInputAdapter is active,
## and the action resolves in the adapter's vocabulary. The
## tier's label is Steam's own string for the origin the
## player actually bound, on the controller they actually
## hold. Fail-closed at every step (#150 doctrine, per
## action): no adapter / inactive / origin 0 (unbound) /
## empty string -> the native label below, never a blank.
## PromptText reads the ADAPTER's accessors only — the
## adapter is the one place game code touches Steam Input.

static func _adapter() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("SteamInputAdapter")


## attack_phrase is a display form of attack (spec section 1).
static func _vocab_action(action: String) -> String:
	return "attack" if action == "attack_phrase" else action


static func _steam_label(action: String, source: int) -> String:
	if not _pad(source):
		return ""
	var ad := _adapter()
	if ad == null or not bool(ad.get("active")):
		return ""
	var mapped := _vocab_action(action)
	if int(ad.call("binding_origin_for", mapped)) == 0:
		return ""
	return str(ad.call("origin_label_for", mapped))


static func _steam_glyph_path(action: String, source: int) -> String:
	if not _pad(source):
		return ""
	var ad := _adapter()
	if ad == null or not bool(ad.get("active")):
		return ""
	return str(ad.call("glyph_path_for", _vocab_action(action)))


## The native-tier sentence label (the standing tables).
static func _native_label(action: String, source: int) -> String:
	var row: Dictionary = LABELS.get(action, {})
	if row.is_empty():
		return action
	return str(row["pad" if _pad(source) else "kb"])


## The sentence-form label for one action token on a source
## ("E"/"X"). Unknown tokens label as themselves, so a typo'd token
## is visible in the rendered text instead of vanishing.
static func label(action: String, source: int = -1) -> String:
	var s := _steam_label(action, source)
	if s != "":
		return s
	return _native_label(action, source)


## The caption-form label for a button slot ("LMB"/"RT"): the
## Steam tier wins, then glyph overrides, everything else
## falls back to the sentence label.
static func glyph(action: String, source: int = -1) -> String:
	var s := _steam_label(action, source)
	if s != "":
		return s
	var row: Dictionary = GLYPHS.get(action, {})
	if row.is_empty():
		return _native_label(action, source)
	return str(row["pad" if _pad(source) else "kb"])


## Render a token-carrying prompt string for a source. Text without
## tokens passes through unchanged; unknown {tokens} are left
## as written (visible, never silently dropped).
static func resolve(text: String, source: int = -1) -> String:
	var out := text
	for action in LABELS.keys():
		out = out.replace("{" + str(action) + "}", label(str(action), source))
	return out


## Issue #190 (section 4): the segments form of resolution for
## the designated ART surfaces. A template parses into text
## runs and action segments; an action segment carries its
## rendered text (label(), or glyph() when caption is true)
## and — under the Steam tier — the glyph ART path Steam
## serves for the binding. The surface builder renders art
## where it can and falls back to the segment's text (which,
## under the Steam tier, IS Steam's origin string), and from
## there the native label: fail-closed in cascade. Unknown
## {tokens} stay literal text, braces and all.
static func resolve_segments(text: String, source: int = -1, caption: bool = false) -> Array:
	var out: Array = []
	var buf := ""
	var i := 0
	while i < text.length():
		if text[i] == "{":
			var j := text.find("}", i)
			if j > i:
				var name := text.substr(i + 1, j - i - 1)
				if LABELS.has(name):
					if buf != "":
						out.append({"kind": "text", "text": buf})
						buf = ""
					out.append({
						"kind": "action",
						"action": name,
						"text": glyph(name, source) if caption else label(name, source),
						"glyph_path": _steam_glyph_path(name, source),
					})
					i = j + 1
					continue
		buf += text[i]
		i += 1
	if buf != "":
		out.append({"kind": "text", "text": buf})
	return out


## One action's segments (the legend caption slots' form).
static func action_segments(action: String, source: int = -1, caption: bool = true) -> Array:
	if not LABELS.has(action):
		return [{"kind": "text", "text": action}]
	return [{
		"kind": "action",
		"action": action,
		"text": glyph(action, source) if caption else label(action, source),
		"glyph_path": _steam_glyph_path(action, source),
	}]
