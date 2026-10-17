#!/usr/bin/env python3
"""Graphical wrapper for the pregenerated-level batch baker (issue #153 D2).

A thin tkinter front end over tools/bake_batch.py: the GUI NEVER
bakes anything itself and NEVER imports the batch module — every run
is a subprocess of the CLI, so there is exactly one code path whether
levels are baked from a shell or from this window.

Python standard library only (tkinter). Runs on Jesse's Windows
Python 3.14 and anywhere else Python + tkinter exist. Launches from
any working directory: the project root defaults to this script's
parent's parent (tools/ -> repo root), and choosing a different
project path runs THAT project's tools/bake_batch.py.

Controls map 1:1 onto the CLI:
    Godot path / project path (+ Browse)   --godot / which checkout
    theme checkboxes (+ All)               --themes / --all-themes
    seed radio: Count+start | List | Range --count/--start-seed |
                                           --seeds | --seed-range
    Cycles field (CLI syntax, blank = 1)   --cycles
    Players field (warlord jobs only)      --players
    Dry-run / Force / Include pinned       --dry-run / --force /
                                           --include-pinned
The players field is enabled only while Warlord is selected, and the
command builder only emits --players for warlord selections — the
CLI applies it to warlord jobs alone (every other theme always bakes
at player_count 1).

Runs stream into the log pane on a worker thread (the UI never
blocks; widgets are touched only on the UI thread via a queue +
after() poll). Stop kills the WHOLE process tree — taskkill /T /F on
Windows, a process-group kill on POSIX — because killing only the
batch would orphan a baking Godot child. With the bake tool's atomic
outputs, a stopped run leaves no partial target .tscn, and the
interrupted job counts as neither done nor skipped.

Validation is inline: a missing Godot binary, project directory, or
batch script shows an error in the window and launches nothing. No
settings are persisted — the prefills are constants.

SCOPE NOTE: baked variants are a saved LIBRARY. The runtime still
selects the one pinned cycle-1, 1-player scene per theme; cycle >= 2
and warlord player-count >= 2 bakes are library-only.
"""

import os
import queue
import signal
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog

ALL_THEMES = ["village", "dungeon", "depths", "supermarket", "warlord", "misty_docks"]
DEFAULT_GODOT_PATH = r"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_PROJECT_ROOT = str(SCRIPT_DIR.parent)


def batch_path_for(project_path: str) -> str:
    """The batch CLI that belongs to a project checkout."""
    return os.path.join(project_path, "tools", "bake_batch.py")


def build_command(state: dict) -> list:
    """Pure: form state -> argv for the batch subprocess.

    state keys: godot_path, project_path, themes (iterable of ids),
    seed_mode ("count"|"list"|"range"), seed_count, seed_start,
    seed_list, seed_range, cycles, players, include_pinned, force,
    dry_run. Deterministic: themes are emitted in ALL_THEMES order,
    and all six selected collapses to --all-themes.
    """
    argv = [sys.executable, batch_path_for(state["project_path"]),
            "--godot", state["godot_path"]]
    themes = [t for t in ALL_THEMES if t in state["themes"]]
    if len(themes) == len(ALL_THEMES):
        argv.append("--all-themes")
    elif themes:
        argv += ["--themes", ",".join(themes)]
    mode = state["seed_mode"]
    if mode == "count":
        argv += ["--count", str(int(state["seed_count"])),
                 "--start-seed", str(int(state["seed_start"]))]
    elif mode == "list":
        argv += ["--seeds", str(state["seed_list"]).strip()]
    elif mode == "range":
        argv += ["--seed-range", str(state["seed_range"]).strip()]
    cycles = str(state["cycles"]).strip()
    if cycles:
        argv += ["--cycles", cycles]
    # (B): the players dimension exists only on warlord jobs. The
    # builder enforces it even if the field somehow holds a value
    # for a warlord-less selection.
    if "warlord" in themes:
        players = str(state["players"]).strip()
        if players:
            argv += ["--players", players]
    if state["include_pinned"]:
        argv.append("--include-pinned")
    if state["force"]:
        argv.append("--force")
    if state["dry_run"]:
        argv.append("--dry-run")
    return argv


def validate_state(state: dict) -> str:
    """Pure: returns "" when the state may launch, else the inline
    error to show. Launches nothing itself."""
    if not state["godot_path"] or not os.path.isfile(state["godot_path"]):
        return "Godot path does not exist: %s" % (state["godot_path"] or "(empty)")
    project = state["project_path"]
    if not project or not os.path.isdir(project):
        return "Project path does not exist: %s" % (project or "(empty)")
    if not os.path.isfile(batch_path_for(project)):
        return "No tools/bake_batch.py under the project path: %s" % project
    themes = [t for t in ALL_THEMES if t in state["themes"]]
    if not themes:
        return "Select at least one theme."
    if state["seed_mode"] == "count":
        try:
            if int(state["seed_count"]) < 1 or int(state["seed_start"]) < 0:
                return "Seed count must be >= 1 and start seed >= 0."
        except (TypeError, ValueError):
            return "Seed count and start seed must be numbers."
    elif state["seed_mode"] == "list":
        if not str(state["seed_list"]).strip():
            return "Seed list is empty."
    elif state["seed_mode"] == "range":
        if not str(state["seed_range"]).strip():
            return "Seed range is empty (expected A-B)."
    return ""


class BakeGui(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("HinterGald — Pregenerated Level Baker")
        self.minsize(760, 560)
        self._queue: "queue.Queue" = queue.Queue()
        self._proc = None
        self._stopped = False
        self._last_summary = ""
        self._build_widgets()
        self._sync_theme_widgets()
        self._sync_seed_widgets()
        self.after(100, self._poll_queue)

    # --- widget construction -------------------------------------
    def _build_widgets(self) -> None:
        pad = {"padx": 6, "pady": 3}
        top = tk.Frame(self)
        top.pack(fill="x", **pad)

        tk.Label(top, text="Godot:").grid(row=0, column=0, sticky="e")
        self.godot_var = tk.StringVar(value=DEFAULT_GODOT_PATH)
        tk.Entry(top, textvariable=self.godot_var, width=72).grid(row=0, column=1, sticky="we")
        tk.Button(top, text="Browse…", command=self._browse_godot).grid(row=0, column=2)

        tk.Label(top, text="Project:").grid(row=1, column=0, sticky="e")
        self.project_var = tk.StringVar(value=DEFAULT_PROJECT_ROOT)
        tk.Entry(top, textvariable=self.project_var, width=72).grid(row=1, column=1, sticky="we")
        tk.Button(top, text="Browse…", command=self._browse_project).grid(row=1, column=2)
        top.columnconfigure(1, weight=1)

        themes_frame = tk.LabelFrame(self, text="Themes")
        themes_frame.pack(fill="x", **pad)
        self.theme_vars = {t: tk.BooleanVar(value=(t == "village")) for t in ALL_THEMES}
        self.all_var = tk.BooleanVar(value=False)
        tk.Checkbutton(themes_frame, text="All", variable=self.all_var,
                       command=self._on_all_toggled).pack(side="left", padx=4)
        for t in ALL_THEMES:
            tk.Checkbutton(themes_frame, text=t, variable=self.theme_vars[t],
                           command=self._sync_theme_widgets).pack(side="left", padx=2)

        seeds = tk.LabelFrame(self, text="Seeds")
        seeds.pack(fill="x", **pad)
        self.seed_mode_var = tk.StringVar(value="count")
        tk.Radiobutton(seeds, text="Count", variable=self.seed_mode_var, value="count",
                       command=self._sync_seed_widgets).grid(row=0, column=0, sticky="w")
        self.seed_count_var = tk.StringVar(value="10")
        self.seed_start_var = tk.StringVar(value="100")
        self.seed_count_entry = tk.Entry(seeds, textvariable=self.seed_count_var, width=6)
        self.seed_count_entry.grid(row=0, column=1)
        tk.Label(seeds, text="starting at").grid(row=0, column=2)
        self.seed_start_entry = tk.Entry(seeds, textvariable=self.seed_start_var, width=8)
        self.seed_start_entry.grid(row=0, column=3)
        tk.Radiobutton(seeds, text="List", variable=self.seed_mode_var, value="list",
                       command=self._sync_seed_widgets).grid(row=0, column=4, sticky="w")
        self.seed_list_var = tk.StringVar(value="1,777,424242")
        self.seed_list_entry = tk.Entry(seeds, textvariable=self.seed_list_var, width=22)
        self.seed_list_entry.grid(row=0, column=5)
        tk.Radiobutton(seeds, text="Range", variable=self.seed_mode_var, value="range",
                       command=self._sync_seed_widgets).grid(row=0, column=6, sticky="w")
        self.seed_range_var = tk.StringVar(value="2-11")
        self.seed_range_entry = tk.Entry(seeds, textvariable=self.seed_range_var, width=10)
        self.seed_range_entry.grid(row=0, column=7)

        dims = tk.Frame(self)
        dims.pack(fill="x", **pad)
        tk.Label(dims, text="Cycles (e.g. 1,3 or 1-3; blank = 1):").pack(side="left")
        self.cycles_var = tk.StringVar(value="")
        tk.Entry(dims, textvariable=self.cycles_var, width=12).pack(side="left", padx=4)
        tk.Label(dims, text="Players (warlord only):").pack(side="left", padx=(14, 0))
        self.players_var = tk.StringVar(value="1")
        self.players_entry = tk.Entry(dims, textvariable=self.players_var, width=12)
        self.players_entry.pack(side="left", padx=4)

        toggles = tk.Frame(self)
        toggles.pack(fill="x", **pad)
        self.dry_run_var = tk.BooleanVar(value=False)
        self.force_var = tk.BooleanVar(value=False)
        self.include_pinned_var = tk.BooleanVar(value=False)
        tk.Checkbutton(toggles, text="Dry-run", variable=self.dry_run_var).pack(side="left", padx=4)
        tk.Checkbutton(toggles, text="Force re-bake", variable=self.force_var).pack(side="left", padx=4)
        tk.Checkbutton(toggles, text="Include pinned", variable=self.include_pinned_var).pack(side="left", padx=4)
        tk.Label(toggles, text="Variants are a library — the game still loads the pinned cycle-1 scenes.",
                 fg="#666666").pack(side="left", padx=12)

        actions = tk.Frame(self)
        actions.pack(fill="x", **pad)
        self.run_button = tk.Button(actions, text="Run", width=10, command=self._on_run)
        self.run_button.pack(side="left", padx=4)
        self.stop_button = tk.Button(actions, text="Stop", width=10,
                                     command=self._on_stop, state="disabled")
        self.stop_button.pack(side="left", padx=4)
        self.error_label = tk.Label(actions, text="", fg="#b00020")
        self.error_label.pack(side="left", padx=10)

        log_frame = tk.Frame(self)
        log_frame.pack(fill="both", expand=True, **pad)
        self.log_text = tk.Text(log_frame, wrap="word", height=18)
        self.log_text.pack(side="left", fill="both", expand=True)
        scroll = tk.Scrollbar(log_frame, command=self.log_text.yview)
        scroll.pack(side="right", fill="y")
        self.log_text.configure(yscrollcommand=scroll.set)

        self.summary_var = tk.StringVar(value="Idle.")
        tk.Label(self, textvariable=self.summary_var, anchor="w",
                 font=("TkDefaultFont", 10, "bold")).pack(fill="x", **pad)

    # --- widget state sync ---------------------------------------
    def _on_all_toggled(self) -> None:
        for var in self.theme_vars.values():
            var.set(self.all_var.get())
        self._sync_theme_widgets()

    def _sync_theme_widgets(self) -> None:
        selected = [t for t in ALL_THEMES if self.theme_vars[t].get()]
        if len(selected) != len(ALL_THEMES):
            self.all_var.set(False)
        else:
            self.all_var.set(True)
        # (B): the players field lives on warlord rows only.
        state = "normal" if self.theme_vars["warlord"].get() else "disabled"
        if hasattr(self, "players_entry"):
            self.players_entry.configure(state=state)

    def _sync_seed_widgets(self) -> None:
        mode = self.seed_mode_var.get()
        for entry, active in ((self.seed_count_entry, mode == "count"),
                              (self.seed_start_entry, mode == "count"),
                              (self.seed_list_entry, mode == "list"),
                              (self.seed_range_entry, mode == "range")):
            entry.configure(state="normal" if active else "disabled")

    def _browse_godot(self) -> None:
        path = filedialog.askopenfilename(
            title="Godot executable",
            filetypes=[("Godot executable", "*.exe"), ("All files", "*.*")])
        if path:
            self.godot_var.set(path)

    def _browse_project(self) -> None:
        path = filedialog.askdirectory(title="Project root (contains tools/bake_batch.py)")
        if path:
            self.project_var.set(path)

    # --- run control ----------------------------------------------
    def get_state(self) -> dict:
        return {
            "godot_path": self.godot_var.get().strip(),
            "project_path": self.project_var.get().strip(),
            "themes": [t for t in ALL_THEMES if self.theme_vars[t].get()],
            "seed_mode": self.seed_mode_var.get(),
            "seed_count": self.seed_count_var.get(),
            "seed_start": self.seed_start_var.get(),
            "seed_list": self.seed_list_var.get(),
            "seed_range": self.seed_range_var.get(),
            "cycles": self.cycles_var.get(),
            "players": self.players_var.get(),
            "include_pinned": self.include_pinned_var.get(),
            "force": self.force_var.get(),
            "dry_run": self.dry_run_var.get(),
        }

    def _on_run(self) -> None:
        state = self.get_state()
        error = validate_state(state)
        if error:
            self.error_label.configure(text=error)
            return
        self.error_label.configure(text="")
        argv = build_command(state)
        self._stopped = False
        self._last_summary = ""
        self.log_text.insert("end", "$ %s\n" % " ".join(argv))
        self.log_text.see("end")
        self.summary_var.set("Running…")
        self.run_button.configure(state="disabled")
        self.stop_button.configure(state="normal")
        threading.Thread(target=self._worker, args=(argv,), daemon=True).start()

    def _worker(self, argv: list) -> None:
        try:
            self._proc = subprocess.Popen(
                argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, errors="replace", bufsize=1,
                start_new_session=(os.name != "nt"))
            for line in self._proc.stdout:
                self._queue.put(("line", line))
            rc = self._proc.wait()
        except Exception as exc:  # launch failure surfaces in the log
            self._queue.put(("line", "GUI: failed to launch: %s\n" % exc))
            rc = -1
        self._queue.put(("done", rc))

    def _on_stop(self) -> None:
        proc = self._proc
        if proc is None or proc.poll() is not None:
            return
        self._stopped = True
        try:
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                               capture_output=True)
            else:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except Exception as exc:
            self._queue.put(("line", "GUI: stop failed: %s\n" % exc))

    def _poll_queue(self) -> None:
        try:
            while True:
                kind, payload = self._queue.get_nowait()
                if kind == "line":
                    self.log_text.insert("end", payload)
                    self.log_text.see("end")
                    stripped = payload.strip()
                    if stripped.startswith("Summary:") or stripped.startswith("Batch bake plan:"):
                        self._last_summary = stripped
                elif kind == "done":
                    self._proc = None
                    self.run_button.configure(state="normal")
                    self.stop_button.configure(state="disabled")
                    if self._stopped:
                        self.summary_var.set(
                            "Stopped — the interrupted job counts as neither done nor skipped.")
                    elif self._last_summary:
                        self.summary_var.set(self._last_summary)
                    else:
                        self.summary_var.set("Finished (exit code %s)." % payload)
        except queue.Empty:
            pass
        self.after(100, self._poll_queue)


def main() -> None:
    BakeGui().mainloop()


if __name__ == "__main__":
    main()
