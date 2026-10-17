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


## The sentence-form label for one action token on a source
## ("E"/"X"). Unknown tokens label as themselves, so a typo'd token
## is visible in the rendered text instead of vanishing.
static func label(action: String, source: int = -1) -> String:
	var row: Dictionary = LABELS.get(action, {})
	if row.is_empty():
		return action
	return str(row["pad" if _pad(source) else "kb"])


## The caption-form label for a button slot ("LMB"/"RT"): glyph
## overrides win, everything else falls back to the sentence label.
static func glyph(action: String, source: int = -1) -> String:
	var row: Dictionary = GLYPHS.get(action, {})
	if row.is_empty():
		return label(action, source)
	return str(row["pad" if _pad(source) else "kb"])


## Render a token-carrying prompt string for a source. Text without
## tokens passes through unchanged; unknown {tokens} are left
## as written (visible, never silently dropped).
static func resolve(text: String, source: int = -1) -> String:
	var out := text
	for action in LABELS.keys():
		out = out.replace("{" + str(action) + "}", label(str(action), source))
	return out
