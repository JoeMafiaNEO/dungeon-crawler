# hintergald — DLC ideas

## Jesse's lead direction (2026-10-07): Mob Packs + Visual Pack
Two DLC lines, both content-first:
- **Mob Packs** — one pack per visual theme, sold/played as bundles.
  4 mobs per pack: a mix of melee, ranged, disruptor, and brute so the AI
  Director can build real compositions. All SNES-style sprites, all wired
  through the existing mob framework (set_allowed_mobs, danger tiers).
  - Sunken Crypt → **Drowned Pack**: Mire Eel (telegraphed line dash),
    Crypt Crab (frontal shield, flank to kill), Siren (slowing song),
    Angler Brute (lunge from the dark)
  - Ember Foundry → **Forge Pack**: Cinder Imp (fast, explodes on death),
    Bellows Hound (charge leaves fire trail), Slag Spitter (ranged lava
    globs), Forge Golem (armor phases, slam AoE)
  - Frostbite Peaks → **Blizzard Pack**: Frost Wolf (pack flanker), Ice
    Wisp (drifting slow aura), Avalanche Rook (dive-bomb), Glacier Troll
    (regenerates unless burned — mage fire matters)
  - Night Bazaar → **Alley Pack**: Cutpurse (steals gold on hit), Masked
    Duelist (parries frontal attacks), Lantern Wisp (blinding pop),
    Firework Monkey (AoE firework tosses)
  - Thornwood → **Wild Pack**: Thorn Lasher (root snare), Stag Charger
    (line charge), Canopy Stalker (drops from above), Spore Mother
    (spawns sporelings, priority target)
  - Clockwork Spire → **Machine Pack**: Gear Rat (swarmer), Winder
    Soldier (shield-wall marcher), Vent Turret (stationary, area denial),
    Chrono Warden (slow telegraphed heavies on a tick rhythm)
  - Void Rift → **Cosmic Pack**: Riftling (short teleports), Null Hound
    (ability-disrupt howl), Star Eater (gravity pull), Eventide Horror
    (mini-boss, phase shifts)
  Status: APPROVED by Jesse (2026-10-07) — all seven packs, bundled with their themes.

- **Visual Pack** — unique new visual themes (not reskins of existing
  zones). Each theme = tileset + weather + lighting + atmosphere, built with
  the same theme system the game already uses. Candidate themes:
  - Sunken Crypt: flooded halls, bioluminescent glow, drifting motes
  - Ember Foundry: forge floors, molten channels, heat shimmer, ember fall
  - Frostbite Peaks: blizzard, aurora sky, crunching snow tileset
  - Night Bazaar: lantern-lit market streets, paper lanterns swaying, warm pools of light
  - Thornwood: overgrown forest dungeon, fireflies, god rays through canopy
  - Clockwork Spire: brass and gearwork, steam vents, rhythmic machine pulse lighting
  - Void Rift: cosmic dark, floating debris, starfield voids between platforms
  Status: APPROVED by Jesse (2026-10-07) — all seven themes.

## 1. "Unfinished Business" (the held trio)
Issues #12 (Player Trading), #13 (Endless Delve), #14 (Workshop Mod Support)
were specced and deliberately held for a future update. They are the most
DLC-ready material in the building: designs exist, none of it touches the
shipped alpha systems. Trading = annex P2P window, server-validated.
Endless Delve = no-station marathon with a 10-minute danger ramp and its own
leaderboard. Workshop = sandboxed themes/mobs/items.

## 2. Fifth class
Mage / Warrior / Rogue / Architect cover nuker, tank, skirmisher, builder.
Open lanes: a pet/summon class (raise fallen mobs), a song/aura support
(Bard), or an alchemist (thrown concoctions, area denial). A new class is
the highest-lift, highest-sizzle DLC anchor — new kit, new affinity family,
new Collection tab.

## 3. New depths (theme pack)
Three new dungeon themes with full mob rosters, loot tables, and music —
e.g. Sunken Crypt, Ember Foundry, Frostbite Peaks. Themes are the game's
cheapest content lever: set_allowed_mobs() + a .tres + art/audio, and the
AI Director does the rest.

## 4. Apex Ascendant (endgame push)
Cycle 12+ content: new apex bosses, new relics for the vault, new
Collection trophies. Builds directly on the shipped apex system (#5) and
gives the endless loop a second horizon.

## 5. Architect's Gambit
Architect-focused expansion: new structures for the kit, and the deferred
Foundation affinity family. The Architect playerbase is small but devoted —
this is a love letter DLC.

## 6. Seasons pass (Warlord Seasons++)
Issue #10 ships 8-minute rotations (Gold Rush/Plague/Mercenary Raid). A DLC
season pack = new rotation modifiers + season-exclusive relics + leaderboard
resets. Recurring-friendly: a template for ongoing drops.
