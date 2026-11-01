# Lessons

Problems we hit and how we solved them, newest first. One entry each: what you saw, why it happened, the fix, and
where it is documented. Before solving something, search this page: it may have happened before.

## 2026-11-01: killing Godot by name stopped other agents' runs

- **Saw:** a benchmark loop looked stuck, with a dozen `Godot_v4.7.2-stable_win64` processes running; killing them all
  with `taskkill /IM` also ended other agents' runs on the same machine (their spikes had to be restarted).
- **Cause:** every agent on the workspace shares the machine and the one pinned Godot executable, so the process
  name does not say whose process it is. The "stray" processes were other agents' runs, not leaks of mine.
- **Fix:** stop only processes you started: keep the PID of each background command, or filter by the command line
  (`Get-CimInstance Win32_Process` with the project path), never by image name. Expect timings on a shared machine
  to be noisy: repeat a run and report the spread.
- **Docs:** [Zombie crowds](godot/crowds.md#numbers).

## 2026-11-01: a benchmark printed numbers from a run full of script errors

- **Saw:** two rows of a frame-time table were absurd (23 to 39 ms for 10 zombies, against 2 ms for the rest) and the
  log held thousands of `SCRIPT ERROR` lines beside the normal result lines.
- **Cause:** a misspelled property (`visible_range_end` for `visibility_range_end`) on an untyped path is a runtime
  error, not a parse error: the zombie's setup stopped halfway and the run went on, then printed its result.
- **Fix:** the runner logs every `ERROR` line next to the results and the log is read for them before any number is
  trusted; the property name was corrected and the whole matrix rerun.
- **Docs:** [Zombie crowds](godot/crowds.md#gotchas-found-while-building-it).

## 2026-11-01: a hidden slider grabber drew a magenta square

- **Saw:** a themed HSlider showed a magenta and black square where the grabber was meant to be invisible.
- **Cause:** the invisible grabber was a PlaceholderTexture2D, which draws its checker pattern in game.
- **Fix:** a transparent ImageTexture of the same size.
- **Docs:** [UI controls](godot/ui-controls.md).

## 2026-11-01: the screen stretched after a UI scale round trip

- **Saw:** after 125% and back to 100%, a column was 1425 px tall and off centre.
- **Cause:** autowrap Labels report a tall minimum size while a container sizes them; a CenterContainer kept it.
- **Fix:** no autowrap in rows (trim with an ellipsis), and a round-trip test.
- **Docs:** [UI controls](godot/ui-controls.md).

## 2026-11-01: GdUnit4 refuses to run headless

- **Saw:** "Headless mode is not supported", exit code 103.
- **Cause:** GdUnit4 blocks headless runs unless told otherwise.
- **Fix:** pass `--ignoreHeadlessMode`; the port 0 remote-debug error line is harmless. A failing suite stops at its
  first failure: fix and rerun to see the rest.
- **Docs:** each game's `AGENTS.md` (Build and test).

## 2026-11-01: a Movie Maker frame shows the state one step late

- **Saw:** the frame numbered N already showed a change made at step N.
- **Cause:** frame N is written after that step's script code ran.
- **Fix:** read frame N-1 to see the state before a change; frames are always at the project viewport size.
- **Docs:** [Capture](capture.md).

## 2026-11-01: Movie Maker ignores `--resolution`

- **Saw:** `--write-movie` with `--resolution 1280x720` (or 960x540) still wrote 1920x1080 frames.
- **Cause:** the movie is the project's viewport size; the window resolution request does not change it (Godot 4.7.2).
- **Fix:** scale afterwards, which `gds capture sheet` and `gds capture clip` do.
- **Docs:** [Capture](capture.md).

## 2026-11-01: hooks judged text as commands

- **Saw:** the hooks refused harmless commands: a Python heredoc line starting `blender = ...`, and a `grep -E "a|godot"`.
- **Cause:** the guard split shell lines on `|` inside quotes and read heredoc bodies as commands.
- **Fix:** split only outside quotes; drop heredoc and here-string bodies before judging.
- **Docs:** Hooks (`docs/hooks.md`).

## 2026-11-01: new agent definitions invisible to a running session

- **Saw:** `.claude/agents/*.md` written mid-session; starting one failed with "agent type not found".
- **Cause:** Claude Code loads project agents when a session starts.
- **Fix:** restart with `claude --resume <session id>` (the conversation is kept).
- **Docs:** Agents (`docs/agents.md`).

## 2026-11-01: Blender's download site refuses scripts

- **Saw:** downloads from download.blender.org returned a browser-check page, not the file.
- **Cause:** the site sits behind a bot check.
- **Fix:** the official mirrors (same checksum file), pinned in `tools.toml`.
- **Docs:** [Workspace](workspace.md#tools).

## 2026-11-01: Godot rewrites project.godot

- **Saw:** a hand-written comment in `project.godot` vanished after the first import.
- **Cause:** Godot owns that file and rewrites it in its own format.
- **Fix:** never hand-comment it; local-only settings go in an untracked `override.cfg`.
- **Docs:** [Workspace](workspace.md).
