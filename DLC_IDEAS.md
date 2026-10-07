# hintergald — DLC ideas

## Jesse's lead direction (2026-10-07): Mob Packs + Visual Pack
Two DLC lines, both content-first:
- **Mob Packs** — new mob families with distinct AI behaviors, sprites, and
  SFX, droppable into existing themes via set_allowed_mobs(). Example packs:
  aquatic (dash eels, shield crabs, charming sirens), undead legion
  (skeleton variants, a necromancer mob that raises the fallen), constructs
  (armor-phase golems). 4–6 mobs per pack keeps art/audio scoped.
- **Visual Pack** — overall visual upgrade layer (scope TBD: new tilesets
  for existing themes? weather/atmosphere effects? lighting passes? cosmetic
  skins?). Cheapest version is atmosphere: rain, embers, fog, day/night
  lighting, new CRT filter options — no sprite rework required.


Brainstorming branch. Nothing here is scoped, specced, or scheduled —
this is the raw idea pool. Picks get the full SPEC/DESIGN/PHASES treatment later.

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
