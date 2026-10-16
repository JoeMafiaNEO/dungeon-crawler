# HinterGald — Steam Input package (issue #150 / #144 Phase 5A)

## Files

- `hintergald_actions.vdf` — the action manifest (Valve "In Game Actions"
  format). One gameplay action set: analog `move` / `look` plus 14 digital
  actions named 1:1 after the game's InputMap verbs. Per Jesse's Q6 ruling,
  `ability_1`–`ability_7` and `signature_ability` are deliberately NOT
  Steam actions — pad ability access is cycle-only, and no user
  configuration can bind a direct-select that does not exist.

## Packaging (read this before cutting a depot)

The manifest must ship as a **real file on disk next to the game build**
(e.g. `<install>/steam_input/hintergald_actions.vdf` in the depot). A
`res://` path inside the `.pck` is NOT a filesystem path Steam can read.
The adapter's dev-override lookup checks, in order:

1. the loose project file (editor / dev runs), and
2. `<exe dir>/steam_input/hintergald_actions.vdf` (the depot layout),

and calls `Steam.setInputActionManifestFilePath()` with the first one
that exists on disk, before `inputInit`. After Jesse publishes the
manifest path in Steamworks (5B below), Steam serves the manifest from
the depot registration and the override is a no-op safety net.

## Default bindings (authoring table for the official configuration)

The official configuration is authored in Steam's controller configurator
against this manifest (5B). Its defaults mirror the Phase 1 native pad map
exactly — same hands, whichever layer serves the pad:

| Input source        | Action         | Input source        | Action       |
|---------------------|----------------|---------------------|--------------|
| Left stick          | move           | Y button            | ability      |
| Right stick         | look           | D-pad up            | start_wave   |
| A button            | jump           | D-pad down          | potion       |
| Right trigger       | attack         | D-pad left          | toggle_rod   |
| Left trigger        | alt_attack     | D-pad right         | build_menu   |
| X button            | interact       | Back / View         | inventory    |
| Left stick click    | dash           | Start / Menu        | pause        |
| LB and RB (both)    | cycle_ability  | Right stick click   | ping         |

## 5B — Jesse-side publication steps (Steamworks, app 3441590)

1. Steamworks → app 3441590 → **Steam Input** settings: set the game to
   use a bundled custom configuration / Steam Input API mode, and point
   the action manifest path at `steam_input/hintergald_actions.vdf`
   (the depot-relative path above). Repeat for the demo app 5431320 if
   the demo should be covered.
2. With the manifest registered, open the game in Steam **Big Picture →
   Manage Game → Configure Controller**: the configurator loads the
   gameplay set from the manifest. Bind the defaults from the table
   above for each controller family (Xbox / PlayStation / Switch Pro /
   Steam Deck), save as the **official configuration** for each, and
   publish.
3. **Push-up observation (publish gate — do not skip):** with the
   game running under Steam and a physical pad, push the left stick
   UP — the character must move FORWARD; push the right stick UP —
   the camera must look UP. If either reads inverted, set
   `STEAM_ANALOG_Y_SIGN` to `-1.0` in
   `scripts/autoload/steam_input_adapter.gd` (one constant, both
   vectors) and re-observe. **Do not publish the official
   configuration until this observation is recorded** — the sign is
   reasoned from the shared HID lineage of Steam's and Godot's axis
   data, not yet observed on live hardware.
4. Live validation then needs a Steam-launched session under the true
   app ID with a physical pad (the VM's second seat cannot validate
   3441590 — it owns no license; app 480 cannot validate either, its
   configuration is Spacewar's).

Until step 1–2 are done, Steam players are unaffected: with no manifest
published, action handles do not resolve, the adapter fails closed, and
the native joypad path serves the pad exactly as it does today.
