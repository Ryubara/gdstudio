---
areas: [tests, godot-ui]
---
# Two UI tests read a time-driven value after a count of frames and failed only in a window

2026-11-05

- **Saw:** a pulse's swing (`0.085`, wanted over `0.2`) and a check box spring's value (`0.96`, wanted `0.99` to `1.2`)
  failed under `gds godot` on a real GPU, three runs in three, and passed headless and on a Linux runner's virtual
  display, with 0 skipped.
- **Cause:** the game was right (the pulse is a function of the HUD's clock; `UISpring` steps a fixed 1/240 s and is
  equal at any frame rate). The tests waited a number of frames (60 and 90), and a window with no frame cap runs a frame
  in about 4 ms, so 60 frames were a quarter of the pulse's turn and 90 were a third of a second for the spring.
- **Fix:** read after the thing has run its course, in time and not in frames: sum `get_process_delta_time()` over one
  full period for the pulse, wait for `UISpring.is_settled()` (with a cap in seconds) for the spring, and assert the
  exact end value. Check for next time: a GdUnit test that waits `N` frames for something driven by `delta` is a
  frame-time test; ask whether the value at `N` frames is the same at 30, 60 and 240 a second, and when a game number
  depends on the rate, a test steps it at those rates by hand.
- **Docs:** the game's `docs/research/windowed-vs-headless-tests.md`.
