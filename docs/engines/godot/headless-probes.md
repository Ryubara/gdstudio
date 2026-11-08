# Probes and tools in headless Godot

A probe is a throwaway run that builds part of a game and prints what it saw (a navigation path, a night's first
minutes). How it is started decides what it can build.

- **`godot --headless --path <game> -s probe.gd`** (a `SceneTree` script) runs before the project's autoloads exist:
  any script in the chain that names one (`UIRouter`, `Audio`, a settings singleton) fails to compile, the error is
  `Identifier not found: <Autoload>` and the build dies inside `_init`. Fine for a navigation mesh or a scene that has
  no autoload in it; useless for a night. The other way round: a class that `-s`
  tools load (a game's player, its animation, holds and grips) must not name an autoload; find the service by its node
  (`get_tree().root.get_node_or_null(^"Audio")`) and `call` it.
- **A `SceneTree` script's root is not in the tree in `_init` or `_initialize`.** `global_position` then reads the
  origin, and the only trace is `!is_inside_tree()` in the log, so a check that passes when nothing is hit passes from
  the wrong place. Add with `get_root().add_child.call_deferred(node)`, `await process_frame` twice, fail if
  `not node.is_inside_tree()`, and give the check a control that must hit.
- **A scene** (`godot --headless --path <game> res://tests/captures/probe.tscn -- --arg=value`) has them. Read the
  arguments with `OS.get_cmdline_user_args()`, print one line of JSON at the end, end with `get_tree().quit()`, and
  write the output to a file (`> log 2>&1`), then read the file: a pipe into `tail` shows nothing until the run ends.
- **Every run gets a `timeout`**, and the first seconds of its log are searched for `SCRIPT ERROR`: a script that fails
  to compile, or fails in `_init` before `quit()`, never ends.
- **A fresh worktree has no test addon and no import cache.** Copy the GdUnit4 addon from the main checkout (it is
  git-excluded there for every worktree; [lesson](../../lessons/2026-11-01-a-worktree-has-no-gdunit4-folder.md)) and run
  `--import` once before the first run; the first `--import` of a worktree takes about a minute.
- **Write the probe with the file tool, not a heredoc**: a shell heredoc with quotes in it failed to parse in the
  agent's shell ([lesson](../../lessons/2026-11-01-large-bash-heredocs-failed-to-parse.md)).

## Runs that never end {#runs-that-never-end}

<!-- new section: the page was one list of bullets with no section for entries; this holds the hang family -->

- **Approach:** Give every headless tool run a short `timeout`, write its log to a file and read the first seconds for
  `SCRIPT ERROR` (or run `godot --headless --check-only -s <script>` first), put `quit()` where an error cannot skip
  it, start the work after `await process_frame`, check `FileAccess.open` for null (`push_error`, `quit(1)`), pass an
  absolute `--out` (a relative one resolves inside the project), and exit 1 when nothing was measured. **Watch out
  for:** a `-s` SceneTree script that fails to parse, or errors in `_init` or `_initialize` before `quit()`, never
  quits: the engine keeps an empty main loop (30 minutes idle; nine runs left at full CPU after `store_string` on a
  null file; six silent minutes through a pipe into `tail`). **Seen:** Deadnight #415, #460, 2026-11-01; Deadnight,
  2026-11-02 (a report script with a parse error in a class it used).

## A parse error is reported on its users {#parse-errors}

<!-- new section: nothing on the page told a probe's author where the real parse error shows -->

- **Approach:** On `Could not parse global class "X"` or `Failed to compile depended scripts`, run `godot --headless
  --path game --check-only --script res://path/to/the_script.gd` on the script the error names before reading the
  files it points at, and grep a class for a name before adding a function or a variable to it. **Watch out for:**
  Godot reports the real error only when that script is loaded on its own: its users get the generic `Cannot infer the
  type of "fight" variable` and nothing names the file that is wrong (a new method `_order` had the name of an
  existing member variable). **Seen:** Deadnight #641, 2026-11-03 (fix: the method got another name).
