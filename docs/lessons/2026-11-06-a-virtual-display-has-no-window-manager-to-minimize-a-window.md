---
areas: [tests, ci]
---
# A virtual display has no window manager, so a test that minimizes a window fails there

2026-11-06

- **Saw:** `test_window_fixture` (`test_a_minimized_window_draws_no_frame`) failed in the scheduled windowed run
  of Deadnight (issue 1348): 33 frames drawn where 3 were expected, passing headless and in a real window.
- **Cause:** `xvfb-run` starts only the X server. Minimizing a window is a request to a window manager and nothing
  answers, so on the runner `window_get_mode()` stays `WINDOW_MODE_WINDOWED` after `WINDOW_MODE_MINIMIZED` and the window
  keeps drawing (probe run 42228307964: 30 frames in 30). The test is right about a real window.
- **Fix:** list it as a suite the runner cannot judge, with the measured reason (`xvfb:` in the game's
  `tools/ui_windowed_known.json`, handled like `llvmpipe:`: left out of the whole-folder run, run and shown when asked
  for by name). Measure first, with a probe suite on the runner printing the mode and the frames drawn: a guess
  ("fewer frames, like the others") would have hidden that it is a different limit.
- **Docs:** the kit's [Windowed GdUnit on a Linux runner](../engines/godot/windowed-gdunit-on-linux.md).
