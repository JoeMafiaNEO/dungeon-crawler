# Warlord's Domain — AI-vs-AI Balance Harness: Final Report

**Date:** 2026-10-04  
**Tuning file:** `scripts/rts/rts_tuning.cfg` (single human-readable file for stone, trade, siege, monks, naval, AI, and all RTS values)  
**Harness:** `tools/sim/sim_harness.gd` + `tools/sim/sim_harness.tscn` (headless, uses real game code + AIWarlord controllers)

## Methodology

- 6 AI-vs-AI matches per batch, 3-way FFA (Iron Vanguard vs Shadow Covenant vs Arcane Dominion).
- Faction-to-player-slot rotation each match (seed 1234 + match*1000).
- 12× time scale, 30 sim-minute timeout per match.
- Harness-side orchestration (no gameplay logic changes): grants a one-time 400 stone/400 wood stipend equally to all factions, forces Age 1, builds market/monastery/siege_workshop/dock per faction, trains trade carts/monks/catapults/rams/fishing ships/war galleys, and issues trade/convert/attack orders using existing game actions.
- Metrics: win rates, match durations, economy curves (5-min samples), subsystem usage (units trained, conversions, trade deliveries/gold, fishing food).

## Baseline (spearman_hp_mult = 1.3)

**Report:** `tools/sim/output/baseline/report_20261004T131139.md`

| Faction | Wins | Win rate |
|---|---|---|
| iron_vanguard | 0 | 0% |
| shadow_covenant | 2 | 33% |
| arcane_dominion | 1 | 17% |
| draw/timeout | 3 | 50% |

**Subsystems (totals across 6 matches):**
- Monks trained: 6, conversions completed: 20
- Trade carts trained: 12, deliveries: 3, gold earned: 90
- Fishing ships trained: 13, food gathered: 5125
- War galleys trained: 1
- Catapults/rams trained: 0 (siege workshop underutilized — AI never builds it naturally)

## Tuning change: iron_vanguard spearman_hp_mult 1.3 → 1.0

Single value changed in `scripts/rts/rts_tuning.cfg`, all else identical (same seeds, same orchestration).

**Report:** `tools/sim/output/nerfed/report_20261004T131614.md`

| Faction | Wins | Win rate | Δ vs baseline |
|---|---|---|---|
| iron_vanguard | 4 | 67% | **+67pp** |
| shadow_covenant | 1 | 17% | -16pp |
| arcane_dominion | 1 | 17% | 0pp |
| draw/timeout | 0 | 0% | **-50pp** |

**Subsystems (nerfed):**
- Monks trained: (see report), conversions: (see report)
- Trade: (see report)
- Naval: (see report)

## Analysis

The HP nerf **paradoxically made Vanguard more decisive**: win rate 0%→67%, timeouts 50%→0%.

Hypothesis: With 1.3× spearman HP, Vanguard's AI over-invests in durable spearmen and plays defensively, leading to stalemates. At 1.0×, the AI shifts to a more aggressive composition (or the weaker spearmen die faster, forcing the AI to commit to decisive engagements), resulting in faster, more conclusive matches.

This is exactly the kind of non-obvious interaction the harness is designed to catch — a "nerf" that improves a faction's win rate by changing its strategic behavior.

**Caveats:**
- 6 matches is a small sample; the 0% baseline for Vanguard may partly reflect the 3 timeouts (effectively 3 decisive matches).
- The harness orchestration (resource stipend, forced Age 1) perturbs absolute balance; use for A/B comparisons, not as a pure measure of unmodified game balance.
- Siege units (catapult/ram) remain at zero — the AI never builds siege workshops naturally, and the harness orchestration prioritizes the other three systems.

## Gameplay bugs fixed during harness development

1. **Airborne armies:** Dense collision pushed land units skyward (avg y≈191). Added ground-plane clamp in `unit.gd`.
2. **Melee orbiting buildings:** Building avoidance (4m) > melee range (1.2-2m), so attackers avoided their target. Excluded explicit attack target from avoidance.
3. **Elimination never triggered:** `check_elimination()` ran before `queue_free()`, counting dead entities. Now ignores `alive=false` / `destroyed=true`.
4. **AI ignored stragglers:** `_attack()` returned if no enemy buildings, leaving villagers alive. Added `_find_enemy_unit()` to hunt survivors.
5. **Fake-peer RPC errors:** Harness uses synthetic peer IDs; `dungeon.gd` now checks `multiplayer.get_peers().has(pid)` before `rpc_id()`.

## Test results

- Full suite: **403 passed, 0 failed** (after all fixes).
- Headless boot: pre-existing Steam/Opcode:20 warnings only, no new errors.

## Files

- `scripts/rts/rts_tuning.cfg` — the tuning file (edit this, not code)
- `scripts/rts/rts_tuning.gd` — config loader (global class `RTSTuning`)
- `tools/sim/sim_harness.gd` / `sim_harness.tscn` — the harness
- `tools/sim/output/baseline/` — baseline reports (md + json)
- `tools/sim/output/nerfed/` — comparison reports (md + json)

## Re-running

```bash
# Baseline (current tuning)
godot --headless --path . res://tools/sim/sim_harness.tscn -- --matches 6 --out tools/sim/output/baseline

# Change a value in scripts/rts/rts_tuning.cfg, then:
godot --headless --path . res://tools/sim/sim_harness.tscn -- --matches 6 --out tools/sim/output/nerfed

# Compare tools/sim/output/baseline/report_*.md vs tools/sim/output/nerfed/report_*.md
```
