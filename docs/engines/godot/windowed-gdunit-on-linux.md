# Windowed GdUnit on a Linux runner

A `--headless` run has no window, so the checks that need one never run in CI: the pixels a suite reads, the layout of a
real window size, the screens a game shows only to a player (an intro, a loading screen). A game that wants those under
a schedule can run its GdUnit suites in a window on a stock GitHub runner. Measured for Deadnight (Godot 4.7.2,
GdUnit4 6.2.2, `ubuntu-24.04`, 2026-11-05, Deadnight issue 1196); the game's own numbers are in its
`docs/research/windowed-ui-ci.md`.

## What it takes

```text
sudo apt-get install -y --no-install-recommends xvfb libgl1-mesa-dri libglx-mesa0 libegl1 \
  libxcursor1 libxinerama1 libxi6 libxrandr2 libxkbcommon0 libfontconfig1 libasound2t64      # about 10 s
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1920x1080x24" godot --path game --audio-driver Dummy \
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/ui/<suite>.gd -c
```

- Godot starts the Compatibility renderer on Mesa's software rasteriser and says so:
  `OpenGL API 4.5 (Core Profile) Mesa 25.2.8-0ubuntu0.24.04.4 - Compatibility - Using Device: Mesa - llvmpipe`.
- Do not pass `--headless` or `--ignoreHeadlessMode`: the first makes the display dummy, the second is for the
  dummy. The audio driver is `Dummy`, as for every agent run.
- The import is a plain `--headless --import` (13 s on the runner); the windowed run needs the same imported project.
- A pixel-reading suite that skips headless (`DisplayServer.get_name() == "headless"`) runs here, and reads real pixels.

## One process a suite, each with a timeout

Run each suite in its own Godot, in its own process group, and kill the group on a timeout (`xvfb-run` starts the X
server; killing only Godot leaves it). A suite that hangs then costs its timeout and nothing after it, the log is per
suite, and the windowed hang of a private Windows desktop (see [No focus](no-focus.md#what-to-know)) cannot take a
whole folder with it. That hang did **not** appear on the runner: the pair that hung on a private Windows desktop (a UI
suite that pushes mouse events, then the night crosshair suite, in one process) finished in 57 s under `xvfb-run`. The
cause found since is that GdUnit minimizes the window after every suite and a minimized window draws nothing
([A minimized window draws nothing](minimized-window.md)); the pair did not hang under xvfb, so the minimize had
no effect there (not looked into), and one process a suite meets only the first suite's window anyway.

GdUnit prints `Overall Summary: N test cases | E errors | F failures | L flaky | S skipped | O orphans |` last; read the
counts from it rather than the exit code (100 for failures, 101 for warnings, another for a crash), and treat a run
with no summary as a crash and a suite that should read pixels but skipped them as "did not run".

## What a software renderer can and cannot judge

llvmpipe draws every pixel on the CPU, so:

- Suites that read pixels, measure layout or step a scene by hand give the same answers as on a GPU window (Deadnight:
  107 of the 113 UI suites both runs had agree with a real Windows window, the pixel suites included).
- Suites that draw a great deal in real time are slow (a suite that takes 17 s on a GPU took 3 min 12 s for its first test)
  and can time out; suites that count frames or read a value inside a timed fade can fail because fewer frames were
  drawn. They pass headless and on a GPU. List them as "not judged by this renderer" instead of failing the schedule
  on them.
- The reverse also holds: two suites failed in a real window (always, three runs of three) and passed on the runner,
  because a value read after N frames depends on how long a frame takes. A virtual display is a window, but not every
  window.

## What a virtual display cannot do, and what a slow frame shows

Measured on the runner (Deadnight issue 1348, 2026-11-06, run 42228307964):

- **No window manager, no minimize.** `xvfb-run` starts only the X server. Setting `WINDOW_MODE_MINIMIZED` is a request
  to a window manager, so nothing happens: `window_get_mode()` stays
  `WINDOW_MODE_WINDOWED` and the window keeps drawing (30 frames drawn in 30 watched). A test of what a minimized window
  does cannot hold there (put it in the game's list of suites the runner cannot judge), and the GdUnit minimize after
  every suite is a no-op, which is another reason the hang did not appear. Moving or focusing a window is the same.
- **Windows bigger than the screen open as asked.** Windows of 1688 x 780 up to 2880 x 1620 opened at that size on a
  1920 x 1080 screen (`window_get_size`, the viewport's size), so a test of a canvas bigger than the monitor works.
- **A clock that runs in `_process` runs in the renderer's real time.** llvmpipe takes 0.1 to 1 s for a frame of a
  large window, so a test that lets N frames pass and then reads a card that holds for seconds, or the phase of a chase
  of bulbs, reads it at a time that depends on the machine. Step such a thing by hand (switch its `_process` off in the
  test), or hold it still (reduced motion), and write a case that runs the same check at `Engine.max_fps = 5`: it fails
  in any run, headless too. Do not use `Engine.time_scale` to make frames long: GdUnit's own timeout runs on it (a
  scale of 1000 turned its 5 minutes into 259 ms).
- **A result that differs between runs is a time, not a luck.** Run the suite on the runner a few times with the run
  made slower (saving the pictures is enough) and keep what each run saw: a suite that failed in one reading, then in
  another, and passed in a third had a bulb row sliding in and out of the area read.

## Sources

- [Xvfb and `xvfb-run`](https://www.x.org/releases/X11R7.6/doc/man/man1/Xvfb.1.xhtml); Mesa's
  [llvmpipe](https://docs.mesa3d.org/drivers/llvmpipe.html) (`LIBGL_ALWAYS_SOFTWARE`).
- [Windowed Godot without taking the focus](no-focus.md) for the same run on a developer's Windows machine.
