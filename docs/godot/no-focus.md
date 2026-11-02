# Windowed Godot without taking the focus

Agents run windowed Godot all the time (captures, `--write-movie`, autopilot scenes, GdUnit without `--headless`). On
Windows every such window opens in front, takes the keyboard (and sometimes the cursor) from the person working on
the same machine, and stays in the way. **Run every windowed Godot through `gds godot`** (or `gds capture frames`,
which uses it); `--headless` is the other way, for runs that draw nothing.

```text
uv run --project <kit>/python gds godot [--timeout SECONDS] [--] <godot arguments>
uv run --project <kit>/python gds godot --path game --write-movie <out>/shot.png --fixed-fps 10 --quit-after 120
```

It runs the pinned Godot with the arguments you give, prints its output as it arrives, ends with its exit code (124
after `--timeout`, default 900 s, which kills Godot and the program it started). The Claude Code hook refuses a Godot
started straight from a shell without `--headless`, `--version` or `--help` and names this command
([hooks](../hooks.md)). Inside a shell script, call `gds godot` where the script called Godot.

## How it works

`gds godot` creates a second **Windows desktop** (`gds-quiet`, in the same window station) and starts Godot on it
(`STARTUPINFO.lpDesktop`). A window on another desktop can never take the focus of the desktop the person works on: it
is not drawn on their screen, receives none of their keys and is not in their way. Godot does not know: it opens a
normal window, OpenGL renders as always, Movie Maker writes its frames. The code is `python/src/gds_tools/quiet_run.py`
(ctypes only; a job object ends the whole process tree on a timeout; off Windows it starts the program normally).

## The cursor clip crosses desktops

One thing does reach the person's desktop: a game that captures or confines the mouse (`Input.mouse_mode` CAPTURED or
CONFINED) calls Windows `ClipCursor`, and the clip holds the real cursor inside the hidden window's rectangle. The
maintainer felt it as an invisible box the cursor could not leave while a capture's sound played (2026-11-01). So:

- `gds godot` starts the program with **`GDS_QUIET=1`**. A game reads it and never captures or confines the mouse
  (Deadnight: `Player.set_controls_enabled`). Every game made with the kit does this in the one place it captures.
- While the program runs, `gds godot` frees the cursor every 20 ms (`ClipCursor(NULL)`). That is a safety net for a
  game that clips once; a game that re-clips every frame defeats it (`python/tests/test_quiet_run.py` measured 16 of
  20 samples held against a program re-clipping every 5 ms), so the game-side check is the fix.

## What was measured

A spike project (`sandbox/no-focus/`, a window that changes colour every frame) was started while a test window held
the foreground and was typed into (F24 once every 30 ms; `python/tests/focus_holder.py`). Pinned Godot 4.7.2, RTX 5080,
Windows 11.

| Way of starting Godot | Foreground / keyboard | Window on the person's desktop | Frames |
| --- | --- | --- | --- |
| plain start | Godot took the foreground 0.4 to 0.7 s after the start (6 of 6 first runs, again in the test's control); on other runs Windows kept the old window in front but Godot still opened a visible window and believed it had focus | yes | rendered |
| `STARTUPINFO` `SW_SHOWMINNOACTIVE` or `SW_SHOWNOACTIVATE` | no help: the console program (`..._console.exe`) is a wrapper that starts the real one without them; started directly, Godot opens minimized and still takes the focus | yes (minimized) | rendered |
| `--position -3000,-3000` | no help: the window is moved back on screen, focus taken | yes | rendered |
| `override.cfg` with `display/window/size/no_focus=true` | not taken, keys kept | yes (in front, but not active) | rendered |
| `override.cfg` with `display/window/size/mode=1` (minimized) | not taken | taskbar only | processed; not checked with Movie Maker |
| **private desktop (`gds godot`)** | **not taken, all keys arrived (every run)** | **no window at all** | **rendered, 30 of 30 frames changing and not black; a Deadnight capture looked right** |

So the start flags cannot be trusted (Godot activates its own window), and the project settings need a file in every
game and still leave a window over the person's screen; the private desktop needs nothing from the game and removes
the window altogether. It costs nothing measurable: a 60-frame run took 1.2 s either way, and a 3 s Deadnight capture
6.7 s including start-up.

The automated proof is `python/tests/test_quiet_run.py`: with a test window in front and typed into, `run_quiet`
starts the real pinned Godot with Movie Maker and the test asserts that the foreground never belongs to Godot, every
key reached the test window, no Godot window is visible on the person's desktop, and the 30 frames are rendered,
different from each other and not black. Run with the plain start instead (`Failed first`), it fails: Godot took the
foreground at 0.72 s.

## What to know

- **Nothing can type into the window**, so a scene must be driven by script or injected events (`Input.parse_input_event`,
  GdUnit input simulation), as agents already do; `Window.has_focus()` is true inside it.
- **Sound still plays** through the speakers when the scene is not recorded: add `--audio-driver Dummy` to a run that
  needs no audio (Movie Maker writes sound to a file and plays none).
- **Not covered:** the Godot *editor* opened for a person or by the MCP add-on (a person's own window, not an agent's
  run), and GPUs other than the one measured (a driver that refuses OpenGL on a second desktop would fail at start-up
  with a Godot error, not silently).
- **Testing windows**: a test window that does not pump messages (a bare `STATIC` window nobody dispatches for)
  stalls Godot's start by about 25 s; `focus_holder.py` pumps its own.
- Foreground tests are flaky for a reason outside Godot: Windows decides whether a background process may take the
  foreground (`ForegroundLockTimeout`, last input, parent process). That is why the test also checks for windows on
  the person's desktop, which does not depend on that decision.
