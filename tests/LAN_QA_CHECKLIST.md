# Issue #70 Phase 2: LAN Multiplayer QA Checklist (Two-Machine)

## Prerequisites
- Two machines on the same LAN (or one machine + VM)
- Both running the same build (commit ef7712f or later)
- Steam NOT required (LAN mode bypasses Steam entirely)

## Test 1: IP Join
1. **Host**: Main Menu → Multiplayer → Host Game → Toggle to **LAN**
   - Verify: Big green "Join IP: 192.168.x.x:7777" is displayed
   - Click "Create Lobby" (or Host button)
   - Verify: Lobby panel shows, you are host
2. **Client**: Main Menu → Multiplayer → Join Game → Toggle to **LAN**
   - Enter the host's IP in the IP field
   - Enter your name (e.g., "TestPlayer")
   - Click "Join LAN Game"
   - Verify: You join the lobby, host sees your name in member list
   - Verify: Your difficulty/loot shows the host's config (handshake worked)

## Test 2: 4-Player Stability
1. Host a LAN game
2. Have 3 clients join (4 players total)
3. Start the dungeon
4. Play through at least 2 waves
5. Verify: No desyncs, no crashes, all players see the same mobs
6. Verify: Damage numbers appear for all players' attacks

## Test 3: Host Kick
1. Host a LAN game, have a client join
2. **Host**: In the lobby, select the client's name in the member list
3. Click "Kick Selected"
4. Verify: Client is disconnected, returns to main menu (or shows disconnect message)
5. Verify: Host's member list updates, client is gone
6. Verify: Host cannot kick themselves (button does nothing if host selected)

## Test 4: Host-Quit Cleanup
1. Host a LAN game, have a client join, start the dungeon
2. **Host**: Pause → Save & Quit (or Quit to Menu)
   - Verify: Host quits immediately (no 3.5s save wait — LAN has no saves)
3. **Client**: Verify you are disconnected gracefully
   - Expected: Return to main menu, or show "Host disconnected" message
   - Verify: No crash, no hang, no Steam API errors in log

## Test 5: No Steam API Calls on LAN Path
1. Run the game with `--verbose` or check the log
2. Host and join a LAN game
3. Verify: No `Steam.` API calls in the log (lobby, persona, Cloud, leaderboards)
4. Verify: No Steam overlay appears

## Test 6: Save-Skips Fire Correctly
1. Host a LAN game, start dungeon, go to station, depart
   - Verify: No save file created in `user://runs/` (LAN has no saves)
2. Pause → Save & Quit
   - Verify: Quits immediately, no save file created

## Known Limitations (Phase 1)
- LAN mode has NO saves (by design — minimal v1)
- Cosmetic names are never verified (anyone can use any name)
- No Steam features on LAN: no invites, no Cloud, no leaderboards, no achievements
- Host kick is LAN-only (Steam uses the Steam overlay for kicking)

## Automated Harness
The `tests/lan_loopback.gd` + `tests/lan_loopback.tscn` provide a two-instance
headless test. Run via `/tmp/lan_orchestrator.py`. Note: ENet UDP is blocked
in the build VM, so this must run on real machines, not headless CI.
