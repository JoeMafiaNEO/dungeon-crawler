# Dungeon Crawler

A lightweight multiplayer dungeon hack-and-slash built with **Godot 4 + GodotSteam**.
2D billboard sprites on 3D planes, Steam P2P lobbies (no servers), data-driven
classes / items / mobs.

## Play it

1. Install **Godot 4.4+** (standard edition, not .NET).
2. Copy the GodotSteam GDExtension into `addons/godotsteam/`
   (download the prebuilt `gdextension` zip from the
   [GodotSteam releases](https://codeberg.org/godotsteam/godotsteam/releases)).
3. Make sure `steam_appid.txt` contains `480` (Spacewar, for dev) or your own app ID.
4. Open this folder as a project in Godot, then press **Play**.
5. Steam must be running for multiplayer. **Play Solo** works without Steam.

## Controls

- **WASD / arrows** — move (first person)
- **Mouse** — look, **Left click / Space** — attack (mage shoots fireballs)
- **E** — pick up nearby loot
- **I / Tab** — inventory (click an item to equip it)
- **Esc** — pause menu (resume / quit to menu)

## Waves

Each level is 5 waves with a countdown between them. Clearing all 5 showers
bonus loot and starts the next level with tougher mobs (+15% per level).

## Test multiplayer

Run two instances on the same machine: one hosts a lobby, the other joins it
from the lobby list. Each instance needs to be logged into Steam (the second
can use Steam in offline... actually Steam P2P needs both online; simplest is
two Steam accounts, or test over LAN with friends).

## Project layout

- `scripts/autoload/` — SteamManager, NetworkManager (P2P lobbies), ItemDB
- `scripts/player/`, `scripts/mobs/`, `scripts/items/` — gameplay
- `scripts/dungeon/` — arena builder + spawning
- `scripts/ui/` — main menu, HUD
- `scripts/data/` — ClassData / ItemData / MobData / DropEntry resources
- `data/classes|items|mobs/` — the actual `.tres` game data (tune here!)
- `scenes/` — player, mob, pickup, dungeon, menu, HUD
- `assets/sprites|icons/` — placeholder pixel art

## Tuning

Everything gameplay-ish lives in `data/`: add a class by dropping a new
`.tres` in `data/classes`, add loot in `data/items`, add monsters in
`data/mobs` (and register the id in `dungeon.gd`'s `_load_mob_types`).
