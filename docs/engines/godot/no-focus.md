# Windowed Godot without taking the focus

Agents run windowed Godot all the time (captures, `--write-movie`, autopilot scenes, GdUnit without `--headless`). On
Windows every such window opens in front, takes the keyboard (and sometimes the cursor) from the person working on
the same machine, and stays in the way. **Run every windowed Godot through `gds godot`** (or `gds capture frames`,
which uses it); `--headless` is the other way, for runs that draw nothing. Browser probes and any other program that
can take the mouse run through **`gds quiet`**, the same thing for any command ([below](#browser-probes-and-any-other-program-gds-quiet)).

```text
uv run --project <kit>/python gds godot [--timeout SECONDS] [--with-audio] [--] <godot arguments>
uv run --project <kit>/python gds godot --path game --write-movie <out>/shot.png --fixed-fps 10 --quit-after 120
```

It runs the pinned Godot with the arguments you give, prints its output as it arrives, ends with its exit code (124
after `--timeout`, default 900 s, which kills Godot and the program it started). The Claude Code hook refuses a Godot
started straight from a shell without `--headless`, `--version` or `--help` and names this command
([hooks](../../studio/hooks.md)). Inside a shell script, call `gds godot` where the script called Godot.

## Browser probes and any other program: `gds quiet` {#browser-probes-and-any-other-program-gds-quiet}

Godot is not the only program that takes the mouse. A local browser probe (Playwright driving a game's web build,
Deadnight's `tools/web_smoke/*.py`) clicks the canvas, the page takes **pointer lock**, and headless Chrome confines the
person's real cursor to its hidden window at the top left of the screen until the lock ends; Esc ends it. **Run every
local browser probe, and any program that can take the mouse, through `gds quiet`:**

```text
uv run --project <kit>/python gds quiet [--timeout SECONDS] -- <command> [arguments]
uv run --project <kit>/python gds quiet -- uv run --with playwright==1.64.1 python tools/web_smoke/hip_fire.py build/web build/hip-fire --gpu
```

It is `gds godot` for any command: the command and every program it starts (Playwright's driver, the browser and its
helpers inherit the desktop like any child) run on the private desktop, the cursor is freed every 5 ms while it runs,
`GDS_QUIET=1` is set (a probe reads it to mute its browser, [Sound](#sound)), the output streams, the exit code comes
back (124 after `--timeout`, default 900 s, which ends the whole tree). A batch-file program (`npx`, `pnpm`) is found
on PATH and run through `cmd /c`. The hook refuses a probe run without it.

Measured on 2026-11-02 (Playwright 1.64.1, a page that calls `requestPointerLock` on a click, Windows 11, a
5120-pixel-wide desktop):

| Browser and start | Cursor clip while the page held the lock |
| --- | --- |
| Playwright's default headless shell (`chromium_headless_shell`), plain start | none: the clip stayed the whole desktop |
| headless Google Chrome (`channel="chrome"`, the probes' `--gpu` mode), plain start | **`(17, 68, 864, 541)`**, the hidden window's rectangle, held for the whole lock |
| headless Chrome on the private desktop, without the 5 ms guard | the same rectangle, 37 of 663 samples (about 0.5 s): the desktop alone does not stop it |
| **headless Chrome under `gds quiet`** | **0 of 777 samples held**; the lock still took; the browser on `gds-quiet` with no window, not even a hidden one, on the person's desktop |

`python/tests/test_quiet_run.py` holds the last row (`test_a_headless_chrome_pointer_lock_does_not_hold_the_real_cursor`,
skipped where Chrome is not installed; its probe is `python/tests/browser_lock_probe.py`), and that the grandchildren of
a command run on the private desktop. Unlike a game, a browser has no `GDS_QUIET` check, so here the 5 ms guard is
the fix, not the safety net; Chrome does not re-clip every frame the way a capturing game can. The test asserts the
longest time the clip lasted, timed by the probe from inside the lock (under 1 s; 6 ms measured; the whole 2.5 s lock
without the guard), not a share of samples (kit #166).

The test also checks that no window of the program appears on the person's desktop. "The program's windows" are those of
its process tree, found with `python/tests/process_tree.py`: a process is a child only if it was created after its
parent, because a parent id alone is reused and an orphan (Explorer, Windows Terminal, the IME host) names a dead
parent's id that a new program can be given (kit #229, [lesson](../../lessons/2026-11-02-a-process-tree-walked-by-parent-id-took-orphans-for-children.md)).

- **Approach:** Run every local program that can take the mouse, Godot or browser, through `gds quiet` (or `gds godot`).
  **Watch out for:** the quiet-run rule covered Godot only, while Deadnight's Playwright probes ran headless Chrome
  straight from the shell; under pointer lock it clipped the real cursor to its hidden window, measured at `(17, 68,
  864, 541)`, until Esc ended the lock. **Seen:** Deadnight, 2026-11-01 (fix: `gds quiet`; the hook refuses a web probe
  or Playwright run without it, and a test measures the clip under a real headless Chrome pointer lock
  ([lesson](../../lessons/2026-11-02-a-headless-browser-under-pointer-lock-held-the-cursor.md))).

## How it works

`gds godot` creates a second **Windows desktop** (`gds-quiet`, in the same window station) and starts Godot on it
(`STARTUPINFO.lpDesktop`). A window on another desktop can never take the focus of the desktop the person works on: it
is not drawn on their screen, receives none of their keys and is not in their way. Godot does not know: it opens a
normal window, OpenGL renders as always, Movie Maker writes its frames. The code is `python/src/gds_tools/quiet_run.py`
(ctypes only; a job object ends the whole process tree on a timeout; off Windows it starts the program normally).

## The cursor clip crosses desktops {#the-cursor-clip-crosses-desktops}

One thing does reach the person's desktop: a game that captures or confines the mouse (`Input.mouse_mode` CAPTURED or
CONFINED) calls Windows `ClipCursor`, and the clip holds the real cursor inside the hidden window's rectangle. The
maintainer felt it as an invisible box the cursor could not leave while a capture's sound played (2026-11-01). So:

- `gds godot` starts the program with **`GDS_QUIET=1`**. A game reads it and never captures or confines the mouse
  (Deadnight: `Player.set_controls_enabled`). Every game made with the kit does this in the one place it captures.
- While the program runs, `gds godot` frees the cursor every 5 ms (`ClipCursor(NULL)`). That is a safety net for a
  game that clips once; a game that re-clips every frame defeats it (`python/tests/test_quiet_run.py` measured 16 of
  20 samples held against a program re-clipping every 5 ms), so the game-side check is the fix.

- **Approach:** Protect every global input state a launched program can take, not only the focus: the cursor clip, the
  clipboard, global hotkeys; a game skips mouse capture under `GDS_QUIET=1`. **Watch out for:** the no-focus launcher
  was measured for focus and keys only, and a game capturing the mouse calls `ClipCursor`, which crosses desktops and
  held the real cursor inside the hidden window while its sound played. **Seen:** Deadnight, 2026-11-01 (fix: `gds
  godot` sets `GDS_QUIET=1`, and a test clips the cursor from the hidden desktop and asserts the real one stays free
  (gdstudio #77)).

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

## Sound {#sound}

Agents never listen: the audio checks read numbers (bus peaks, `AudioEffectCapture`, the WAV Movie Maker writes), never
the speakers. A windowed Godot on the default driver (`WASAPI` on Windows) plays through the speakers of the person at
the machine, so everything an agent launches is silent:

| Launch | Audio driver | How |
| --- | --- | --- |
| `gds godot -- <arguments>` | `Dummy` | the wrapper puts `--audio-driver Dummy` in front unless the arguments already name a driver; `gds godot --with-audio -- ...` keeps the sound, for a person who asks to hear it |
| `--headless` | `Dummy` | Godot's own `--headless` is `--display-driver headless --audio-driver Dummy` (`--help`; measured: `AudioServer.get_driver_name()` is `Dummy`) |
| Movie Maker (`--write-movie`, `gds capture frames`) | `Dummy` | Movie Maker forces it and writes the mix to the `.wav` (measured under `gds godot`) |
| a browser probe under `gds quiet` | muted | `GDS_QUIET=1` is set; Playwright's headless Chromium starts with `--mute-audio` (read off the process command line, Playwright 1.64.1), and a game's launch helper adds `--mute-audio` (headed Chromium) and Firefox's `media.volume_scale` under `GDS_QUIET` (Deadnight: `smoke.mute_args()`) |

The hook refuses a Godot with another `--audio-driver` and `gds godot --with-audio` from an agent session
([hooks](../../studio/hooks.md)). `--headless` without the flag is allowed, since it is Dummy already.

**The Dummy driver still mixes.** It runs the same mixer thread as a real driver and throws the output away. Measured
on 2026-11-02 (Godot 4.7.2): a 440 Hz tone played on a bus gives `get_bus_peak_volume_left_db` of -4.3 dB (the exact
level of a 20000/32768 sine) and the same 0.61 maximum in an `AudioEffectCapture`, headless and through `gds godot`.
Deadnight's 14 audio suites (123 test cases: bus layout and levels, the audio service, voice budget, gun audio rules,
footsteps, occlusion, zombie voices) pass headless and windowed under Dummy. Its loudness checks read Movie Maker's WAV
(already Dummy) and `AudioEffectRecord` stems. Nothing needed the fallback (a `GDSTUDIO_MUTE` environment variable
muting the Master bus after the tests read it).

Not silenced: a program that starts Godot or a browser from inside `gds quiet -- <script>` (the hook sees only the
script), and the Godot editor opened by a person or by the MCP add-on.

- **Approach:** Silence everything an agent launches by default, and keep the sound only when a person asks to hear it.
  **Watch out for:** anything launched on the shared machine must leave the person's devices alone, sound included, and
  `gds godot` and `gds quiet` hid the window and freed the cursor but left audio on, so captures, autopilots and browser
  probes played through the speakers. **Seen:** gdstudio #102, 2026-11-02 (fix: `gds godot` adds `--audio-driver Dummy`,
  `gds quiet` sets `GDS_QUIET=1` and the probes add `--mute-audio`; the hook refuses a real `--audio-driver` and
  `--with-audio` from a session (gdstudio #102,
  [lesson](../../lessons/2026-11-02-agent-launched-godot-played-through-the-speakers.md))).

## What to know {#what-to-know}

- **Nothing can type into the window**, so a scene must be driven by script or injected events (`Input.parse_input_event`,
  GdUnit input simulation), as agents already do; `Window.has_focus()` is true inside it.
- **No sound**: `gds godot` starts Godot with `--audio-driver Dummy` ([Sound](#sound)).
- **Not covered:** the Godot *editor* opened for a person or by the MCP add-on (a person's own window, not an agent's
  run), a headed browser (`headless=False`: a person watching it is at the machine anyway), and GPUs other than the
  one measured (a driver that refuses OpenGL on a second desktop would fail at start-up
  with a Godot error, not silently).
- **Testing windows**: a test window that does not pump messages (a bare `STATIC` window nobody dispatches for)
  stalls Godot's start by about 25 s; `focus_holder.py` pumps its own.
- Foreground tests are flaky for a reason outside Godot: Windows decides whether a background process may take the
  foreground (`ForegroundLockTimeout`, last input, parent process). That is why the test also checks for windows on
  the person's desktop, which does not depend on that decision.
- **GdUnit through `gds godot` can hang where CI does not.** A windowed run of a suite that pushes pointer events, followed
  by a suite that starts a night, stalled the night's `UIRouter.idle`; the same pair headless, as CI runs it, passed. Run
  suites with `godot --headless ... GdUnitCmdTool.gd ... --ignoreHeadlessMode`, keep `gds godot` for captures, and
  give a long windowed run `gds godot --timeout 3000 --` (the default stops it at 900 s)
  ([lesson](../../lessons/2026-11-04-a-windowed-gdunit-run-hung-the-night-suites-after-a-ui-suite.md)).
- **A suite can fail in a window and pass headless for a switch of the game's own.** Headless has a 64 pixel window and
  no loading screen or arrival show, so a menu shell never goes compact and a night starts with the player in control;
  a window has all three. Before a pull request, run the suites that open a menu shell or a night once through
  `gds godot --timeout 600 -- ... GdUnitCmdTool.gd -a <suite>` (a baseline worktree needs GdUnit4 copied in first), and
  make the headless run answer what the window answers.

- **Approach:** Start every windowed tool run (captures, recordings, autopilots) off the person's desktop with `gds
  godot`, and prove it by keystrokes still reaching the person's window, not only by the mouse staying put. **Watch out
  for:** agents share the maintainer's machine; each windowed Godot became the active window, and ending its mouse
  capture did not stop Windows giving it the keyboard. **Seen:** Deadnight, 2026-11-01 (fix: `gds godot` runs Godot on a
  private desktop and a hook refuses a bare windowed Godot).
- **Approach:** Switch off the driven player's device input in every capture. **Watch out for:** the real mouse of the
  person at the machine turned a capture's camera by up to 65 degrees. **Seen:** Deadnight #364, 2026-11-01 (fix: two
  runs of the same capture script differed).
