# Probes and tools in headless Godot

A probe is a throwaway run that builds part of a game and prints what it saw (a navigation path, a night's first
minutes). How it is started decides what it can build.

- **`godot --headless --path <game> -s probe.gd`** (a `SceneTree` script) runs before the project's autoloads exist:
  any script in the chain that names one (`UIRouter`, `Audio`, a settings singleton) fails to compile, the error is
  `Identifier not found: <Autoload>` and the build dies inside `_init`. Fine for a navigation mesh or a scene that has
  no autoload in it; useless for a night
  ([lesson](../lessons/2026-11-03-a-probe-run-with-s-had-no-autoloads.md)).
- **A scene** (`godot --headless --path <game> res://tests/captures/probe.tscn -- --arg=value`) has them. Read the
  arguments with `OS.get_cmdline_user_args()`, print one line of JSON at the end, end with `get_tree().quit()`, and
  write the output to a file (`> log 2>&1`), then read the file: a pipe into `tail` shows nothing until the run ends.
- **Every run gets a `timeout`**, and the first seconds of its log are searched for `SCRIPT ERROR`: a script that fails
  to compile, or fails in `_init` before `quit()`, never ends
  ([lesson](../lessons/2026-11-01-a-script-that-fails-to-parse-hangs-headless-godot.md)).
- **A fresh worktree has no test addon and no import cache.** Copy the GdUnit4 addon from the main checkout (it is
  git-excluded there for every worktree; [lesson](../lessons/2026-11-01-a-worktree-has-no-gdunit4-folder.md)) and run
  `--import` once before the first run; the first `--import` of a worktree takes about a minute.
- **Write the probe with the file tool, not a heredoc**: a shell heredoc with quotes in it failed to parse in the
  agent's shell ([lesson](../lessons/2026-11-01-large-bash-heredocs-failed-to-parse.md)).
