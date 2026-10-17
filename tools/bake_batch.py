#!/usr/bin/env python3
"""Batch-bake a library of pregenerated level variants (issue #151).

Plans (theme, seed) jobs and invokes the Godot bake tool
(tools/bake_levels.gd) ONCE PER JOB IN A FRESH PROCESS — the wrapper
never bakes anything itself; process isolation is the proven path and
keeps batch state from leaking between bakes. Each job's output is
captured to a log file next to the outputs.

Usage:
    python3 tools/bake_batch.py --themes village,dungeon --seeds 1,777 [options]
    python3 tools/bake_batch.py --all-themes --seed-range 2-11 [options]
    python3 tools/bake_batch.py --all-themes --count 10 --start-seed 100 [options]
    python3 tools/bake_batch.py --themes warlord --seeds 777 --cycles 1-3 --players 1-4 [options]

Options:
    --themes a,b,c        Themes to bake (comma-separated). Theme ids:
                          village, dungeon, depths, supermarket,
                          warlord, misty_docks.
    --all-themes          All six shipped pregen themes.
    --seeds 1,777,424242  Explicit seed list.
    --seed-range A-B      Inclusive seed range.
    --count N             N consecutive seeds from --start-seed.
    --start-seed S        First seed for --count (default 1).
                          Seed sources combine; the plan dedups and
                          runs seeds ascending, themes in given order.
    --cycles 1,3 / 1-3    Cycles to bake (issue #153 D1): a comma
                          list whose items may be ranges; deduped,
                          ascending. Default: cycle 1 only. Cycle-1
                          names are EXACTLY as before; cycle >= 2 adds
                          a _c<N> suffix to file and manifest key.
    --players 1,2 / 1-4   Player counts (same list/range syntax).
                          Applies to WARLORD jobs only — every other
                          theme always bakes at player_count 1.
                          Default: 1. Warlord player count 1 carries
                          NO suffix at any cycle; count >= 2 appends
                          _p<P> AFTER any cycle suffix
                          (theme_warlord_seed_777_c2_p3.tscn).
    --include-pinned      Also bake a theme's pinned seed at cycle 1,
                          player count 1 (default: that one job is
                          SKIPPED — it would duplicate the shipped
                          scene scenes/levels/pregen/theme_<id>.tscn).
                          Pinned seeds at cycle >= 2, and warlord
                          pinned seeds at player count >= 2, BAKE.
    --force               Re-bake outputs that already exist (default:
                          skip-if-exists per output).
    --verify              After each bake, run the bake tool's own
                          --verify hash check (DEFAULT ON).
    --no-verify           Skip the per-job verify.
    --dry-run             Print the full plan (jobs, outputs, skips
                          with reasons) and run nothing.
    --out-dir DIR         Where variant scenes land (default:
                          scenes/levels/pregen/variants in the repo).
    --manifest PATH       The variants manifest the bake tool updates
                          (default: <out-dir>/variants_manifest.json).
                          The shipped bake_manifest.json is NEVER
                          written by this wrapper.
    --godot PATH          Godot binary. Falls back to the GODOT_BIN
                          environment variable. One of the two is
                          required.

Outputs:
    <out-dir>/theme_<id>_seed_<seed>[_c<N>][_p<P>].tscn   one scene per job
    <out-dir>/variants_manifest.json             entries keyed
                                                  <theme>_<seed>[_c<N>][_p<P>],
                                                  with cycle + player_count
    <out-dir>/logs/<key>.bake.log                per-job bake output
    <out-dir>/logs/<key>.verify.log              per-job verify output

Examples:
    VM:
        GODOT_BIN=~/workspace/bin/Godot_v4.7.2-stable_linux.x86_64 \\
            python3 tools/bake_batch.py --all-themes --seed-range 2-11
    Windows (Jesse's PC, Steam Godot):
        py tools\\bake_batch.py --godot "D:\\SteamLibrary\\steamapps\\common\\Godot Engine\\godot.windows.opt.tools.64.exe" --themes village,dungeon --seeds 777,424242 --dry-run

Job success is judged by the bake tool's [BAKE] lines and the output
file's presence — the tool's process exit code can be teardown-flaky
after a successful bake (its own header warns of this). A failed job
is recorded and the batch CONTINUES; the wrapper's exit code is
nonzero iff any job failed.

SCOPE NOTE: the variants are a saved LIBRARY. The runtime still
selects the one pinned scene per theme — wiring variants into
cycle-1 rotation is the separate, Jesse-gated K-variants follow-up.
Cycle >= 2 bakes and warlord player-count >= 2 bakes are likewise
LIBRARY-ONLY: the runtime consumes exactly the cycle-1 1-player
pinned scene. This tool does not change what the game loads.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ALL_THEMES = ["village", "dungeon", "depths", "supermarket", "warlord", "misty_docks"]
REPO = Path(__file__).resolve().parent.parent
PREGEN_DIR = REPO / "scenes" / "levels" / "pregen"
SHIPPED_MANIFEST = PREGEN_DIR / "bake_manifest.json"
BAKE_SUCCESS_RE = re.compile(
    r"\[BAKE\] theme=(?P<theme>\S+) seed=(?P<seed>\d+) cycle=(?P<cycle>\d+) "
    r"players=(?P<players>\d+) hash=(?P<hash>\S+) "
    r"mode=(?P<mode>\S+) bytes=(?P<bytes>\d+)"
)


def collect_number_list(spec: str, flag: str) -> list:
    """Parse a --cycles/--players spec: comma list whose items are
    single numbers or inclusive A-B ranges. Deduped, ascending."""
    values = set()
    for tok in spec.split(","):
        tok = tok.strip()
        if not tok:
            continue
        m = re.fullmatch(r"(\d+)\s*-\s*(\d+)", tok)
        if m:
            lo, hi = int(m.group(1)), int(m.group(2))
            if hi < lo:
                raise ValueError("%s range end before start: %r" % (flag, tok))
            values.update(range(lo, hi + 1))
        elif tok.isdigit():
            values.add(int(tok))
        else:
            raise ValueError("%s items must be numbers or A-B ranges (got %r)" % (flag, tok))
    return sorted(values)


def godot_path_arg(path: Path) -> str:
    """The path form the bake tool wants: res:// for in-repo paths,
    the absolute OS path otherwise."""
    try:
        return "res://" + path.resolve().relative_to(REPO).as_posix()
    except ValueError:
        return str(path)


def collect_seeds(args) -> list:
    seeds = set()
    if args.seeds:
        for tok in args.seeds.split(","):
            tok = tok.strip()
            if tok:
                seeds.add(int(tok))
    if args.seed_range:
        m = re.fullmatch(r"\s*(\d+)\s*-\s*(\d+)\s*", args.seed_range)
        if not m:
            raise ValueError("--seed-range must look like A-B (got %r)" % args.seed_range)
        lo, hi = int(m.group(1)), int(m.group(2))
        if hi < lo:
            raise ValueError("--seed-range end before start: %r" % args.seed_range)
        seeds.update(range(lo, hi + 1))
    if args.count is not None:
        if args.count < 1:
            raise ValueError("--count must be >= 1")
        seeds.update(range(args.start_seed, args.start_seed + args.count))
    return sorted(seeds)


def pinned_seeds() -> dict:
    try:
        data = json.loads(SHIPPED_MANIFEST.read_text(encoding="utf-8"))
        return {tid: int(entry["seed"]) for tid, entry in data.get("scenes", {}).items()}
    except Exception:
        return {}


def run_job(godot: str, repo: Path, extra: list, log_path: Path) -> str:
    cmd = [godot, "--headless", "--path", str(repo),
           "res://tools/bake_levels.tscn", "--"] + extra
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    text = proc.stdout.decode("utf-8", errors="replace")
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(text, encoding="utf-8")
    return text


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        prog="bake_batch.py",
        description="Batch-bake pregenerated level variants via tools/bake_levels.gd.")
    ap.add_argument("--themes", help="comma-separated theme ids")
    ap.add_argument("--all-themes", action="store_true", help="all six shipped themes")
    ap.add_argument("--seeds", help="comma-separated explicit seeds")
    ap.add_argument("--seed-range", help="inclusive seed range A-B")
    ap.add_argument("--count", type=int, help="N consecutive seeds from --start-seed")
    ap.add_argument("--start-seed", type=int, default=1, help="first seed for --count")
    ap.add_argument("--cycles", help="cycles to bake: comma list and/or A-B ranges (default: 1)")
    ap.add_argument("--players", help="warlord player counts: comma list and/or A-B ranges (default: 1)")
    ap.add_argument("--include-pinned", action="store_true",
                    help="also bake pinned seeds at cycle 1 / 1 player (default: skip that one job)")
    ap.add_argument("--force", action="store_true",
                    help="re-bake outputs that already exist")
    ap.add_argument("--verify", dest="verify", action="store_true", default=True,
                    help="run the tool's --verify after each bake (default)")
    ap.add_argument("--no-verify", dest="verify", action="store_false",
                    help="skip the per-job verify")
    ap.add_argument("--dry-run", action="store_true",
                    help="print the plan and run nothing")
    ap.add_argument("--out-dir", help="variant output directory")
    ap.add_argument("--manifest", help="variants manifest path")
    ap.add_argument("--godot", help="Godot binary (or set GODOT_BIN)")
    args = ap.parse_args(argv)

    godot = args.godot or os.environ.get("GODOT_BIN")
    if not godot:
        print("ERROR: no Godot binary given. Pass --godot <path> or set GODOT_BIN.",
              file=sys.stderr)
        print("  VM example:      ~/workspace/bin/Godot_v4.7.2-stable_linux.x86_64",
              file=sys.stderr)
        print("  Windows example: D:\\SteamLibrary\\steamapps\\common\\Godot Engine\\godot.windows.opt.tools.64.exe",
              file=sys.stderr)
        return 2
    godot = os.path.expanduser(godot)

    if args.all_themes:
        themes = list(ALL_THEMES)
    elif args.themes:
        themes = [t.strip() for t in args.themes.split(",") if t.strip()]
    else:
        print("ERROR: give --themes a,b,c or --all-themes.", file=sys.stderr)
        return 2
    try:
        seeds = collect_seeds(args)
    except ValueError as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 2
    if not seeds:
        print("ERROR: no seeds — give --seeds, --seed-range, or --count.", file=sys.stderr)
        return 2

    out_dir = Path(args.out_dir).resolve() if args.out_dir else PREGEN_DIR / "variants"
    manifest = Path(args.manifest).resolve() if args.manifest else out_dir / "variants_manifest.json"
    logs_dir = out_dir / "logs"
    pinned = pinned_seeds()

    try:
        cycles = collect_number_list(args.cycles, "--cycles") if args.cycles else [1]
        players_list = collect_number_list(args.players, "--players") if args.players else [1]
    except ValueError as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 2
    if not cycles or min(cycles) < 1:
        print("ERROR: --cycles values must be >= 1.", file=sys.stderr)
        return 2
    if not players_list or min(players_list) < 1:
        print("ERROR: --players values must be >= 1.", file=sys.stderr)
        return 2

    # --- Plan (deterministic: themes as given, then seeds, cycles,
    # player counts ascending). The player-count dimension exists
    # only on warlord jobs; every other theme bakes at count 1.
    # Naming: cycle 1 and count 1 carry no suffix (the #151 names);
    # cycle >= 2 appends _c<N>; warlord count >= 2 appends _p<P>
    # after any cycle suffix. The pinned-seed skip protects exactly
    # (pinned seed, cycle 1, count 1). ---
    plan = []
    for theme in themes:
        for seed in seeds:
            for cycle in cycles:
                job_players = players_list if theme == "warlord" else [1]
                for players in job_players:
                    suffix = ""
                    if cycle >= 2:
                        suffix += "_c%d" % cycle
                    if players >= 2:
                        suffix += "_p%d" % players
                    key = "%s_%d%s" % (theme, seed, suffix)
                    out_file = out_dir / ("theme_%s_seed_%d%s.tscn" % (theme, seed, suffix))
                    skip = ""
                    if (pinned.get(theme) == seed and cycle == 1 and players == 1
                            and not args.include_pinned):
                        skip = ("pinned seed at cycle 1 (duplicates the shipped "
                                "theme_%s.tscn)" % theme)
                    elif out_file.exists() and not args.force:
                        skip = "output exists (use --force to re-bake)"
                    plan.append({"theme": theme, "seed": seed, "cycle": cycle,
                                 "players": players, "key": key,
                                 "out": out_file, "skip": skip})

    print("Batch bake plan: %d job(s), %d to run, %d skipped"
          % (len(plan), sum(1 for j in plan if not j["skip"]),
             sum(1 for j in plan if j["skip"])))
    for j in plan:
        if j["skip"]:
            print("  SKIP %s -> %s (%s)" % (j["key"], j["out"], j["skip"]))
        else:
            print("  BAKE %s -> %s" % (j["key"], j["out"]))
    if args.dry_run:
        print("Dry run: nothing baked.")
        return 0

    out_dir.mkdir(parents=True, exist_ok=True)
    manifest_arg = godot_path_arg(manifest)
    results = []
    for j in plan:
        if j["skip"]:
            results.append((j, "skipped", j["skip"], "", 0))
            continue
        base_args = ["--theme", j["theme"], "--seed", str(j["seed"]),
                     "--cycle", str(j["cycle"]), "--players", str(j["players"]),
                     "--out", godot_path_arg(j["out"]),
                     "--manifest", manifest_arg,
                     "--manifest-key", j["key"]]
        print("Baking %s ..." % j["key"], flush=True)
        text = run_job(godot, REPO, base_args, logs_dir / (j["key"] + ".bake.log"))
        m = BAKE_SUCCESS_RE.search(text)
        if "[BAKE] FAILED" in text or m is None or not j["out"].exists():
            results.append((j, "FAILED", "bake failed (see %s.bake.log)" % j["key"], "", 0))
            print("  FAILED %s" % j["key"], flush=True)
            continue
        content_hash, nbytes = m.group("hash"), int(m.group("bytes"))
        if args.verify:
            vtext = run_job(godot, REPO, base_args + ["--verify"],
                            logs_dir / (j["key"] + ".verify.log"))
            if "[BAKE] VERIFY PASS" not in vtext or "[BAKE] FAILED" in vtext:
                results.append((j, "FAILED", "verify failed (see %s.verify.log)" % j["key"],
                                content_hash, nbytes))
                print("  FAILED %s (verify)" % j["key"], flush=True)
                continue
        results.append((j, "done", "", content_hash, nbytes))
        print("  done %s hash=%s bytes=%d%s"
              % (j["key"], content_hash, nbytes, " (verified)" if args.verify else ""),
              flush=True)

    done = [r for r in results if r[1] == "done"]
    skipped = [r for r in results if r[1] == "skipped"]
    failed = [r for r in results if r[1] == "FAILED"]
    print("\nSummary: %d done, %d skipped, %d failed" % (len(done), len(skipped), len(failed)))
    for j, status, note, content_hash, nbytes in results:
        if status == "done":
            print("  done    %s hash=%s bytes=%d" % (j["key"], content_hash, nbytes))
        elif status == "skipped":
            print("  skipped %s (%s)" % (j["key"], note))
        else:
            print("  FAILED  %s (%s)" % (j["key"], note))
    print("Total variant bytes: %d" % sum(r[4] for r in done))
    print("Manifest: %s" % manifest)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
