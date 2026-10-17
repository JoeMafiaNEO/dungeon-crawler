#!/usr/bin/env python3
"""Unit tests for tools/bake_gui.py's command builder (issue #153 D2).

The builder is a pure function (form state -> argv), so these tests
run headless with no display and no tkinter window — they import the
module and compare build_command() output against LITERAL expected
argvs. Run:  python3 tools/test_bake_gui.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_gui  # noqa: E402

PY = sys.executable
PROJ = "/proj"
BATCH = os.path.join(PROJ, "tools", "bake_batch.py")
GODOT = "/opt/godot/godot"


def state(**overrides):
    base = {
        "godot_path": GODOT,
        "project_path": PROJ,
        "themes": ["village"],
        "seed_mode": "count",
        "seed_count": "10",
        "seed_start": "100",
        "seed_list": "1,777",
        "seed_range": "2-11",
        "cycles": "",
        "players": "1",
        "include_pinned": False,
        "force": False,
        "dry_run": False,
    }
    base.update(overrides)
    return base


class BuildCommandTests(unittest.TestCase):
    def test_minimal_count_mode(self):
        self.assertEqual(
            bake_gui.build_command(state()),
            [PY, BATCH, "--godot", GODOT,
             "--themes", "village",
             "--count", "10", "--start-seed", "100"])

    def test_all_themes_collapses_to_flag(self):
        # All six includes warlord, so the players field applies.
        self.assertEqual(
            bake_gui.build_command(state(themes=list(bake_gui.ALL_THEMES))),
            [PY, BATCH, "--godot", GODOT,
             "--all-themes",
             "--count", "10", "--start-seed", "100",
             "--players", "1"])

    def test_themes_emit_in_canonical_order(self):
        self.assertEqual(
            bake_gui.build_command(state(themes=["warlord", "depths", "village"])),
            [PY, BATCH, "--godot", GODOT,
             "--themes", "village,depths,warlord",
             "--count", "10", "--start-seed", "100",
             "--players", "1"])

    def test_list_mode(self):
        self.assertEqual(
            bake_gui.build_command(state(seed_mode="list")),
            [PY, BATCH, "--godot", GODOT,
             "--themes", "village",
             "--seeds", "1,777"])

    def test_range_mode(self):
        self.assertEqual(
            bake_gui.build_command(state(seed_mode="range")),
            [PY, BATCH, "--godot", GODOT,
             "--themes", "village",
             "--seed-range", "2-11"])

    def test_cycles_passed_through_verbatim(self):
        self.assertEqual(
            bake_gui.build_command(state(cycles="1-3")),
            [PY, BATCH, "--godot", GODOT,
             "--themes", "village",
             "--count", "10", "--start-seed", "100",
             "--cycles", "1-3"])

    def test_players_only_for_warlord(self):
        with_warlord = bake_gui.build_command(
            state(themes=["warlord"], players="1-4", cycles="2"))
        self.assertEqual(
            with_warlord,
            [PY, BATCH, "--godot", GODOT,
             "--themes", "warlord",
             "--count", "10", "--start-seed", "100",
             "--cycles", "2", "--players", "1-4"])
        without = bake_gui.build_command(state(themes=["village"], players="1-4"))
        self.assertNotIn("--players", without)

    def test_toggles_map_in_order(self):
        self.assertEqual(
            bake_gui.build_command(state(include_pinned=True, force=True, dry_run=True)),
            [PY, BATCH, "--godot", GODOT,
             "--themes", "village",
             "--count", "10", "--start-seed", "100",
             "--include-pinned", "--force", "--dry-run"])

    def test_project_path_selects_the_batch(self):
        argv = bake_gui.build_command(state(project_path="/other/checkout"))
        self.assertEqual(argv[1], os.path.join("/other/checkout", "tools", "bake_batch.py"))

    def test_defaults_point_at_this_repo(self):
        self.assertTrue(os.path.isfile(bake_gui.batch_path_for(bake_gui.DEFAULT_PROJECT_ROOT)))
        self.assertEqual(bake_gui.DEFAULT_GODOT_PATH,
                         r"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe")


class ValidateStateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.dirname(os.path.abspath(__file__))

    def test_valid_state_passes(self):
        good = state(godot_path=sys.executable,
                     project_path=os.path.dirname(self.tmp))
        self.assertEqual(bake_gui.validate_state(good), "")

    def test_missing_godot_is_inline_error(self):
        err = bake_gui.validate_state(state(godot_path="/nope/godot"))
        self.assertIn("Godot path does not exist", err)

    def test_missing_project_is_inline_error(self):
        err = bake_gui.validate_state(state(godot_path=sys.executable,
                                            project_path="/nope/project"))
        self.assertIn("Project path does not exist", err)

    def test_project_without_batch_is_inline_error(self):
        err = bake_gui.validate_state(state(godot_path=sys.executable,
                                            project_path="/tmp"))
        self.assertIn("No tools/bake_batch.py", err)

    def test_no_theme_is_inline_error(self):
        err = bake_gui.validate_state(state(godot_path=sys.executable,
                                            project_path=os.path.dirname(self.tmp),
                                            themes=[]))
        self.assertIn("at least one theme", err)


if __name__ == "__main__":
    unittest.main(verbosity=2)
