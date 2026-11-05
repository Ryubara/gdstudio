---
areas: [tests, godot]
---
# The second windowed suite that opened a night hung on its first test

2026-11-05

- **Saw:** Deadnight's `test_night_screen` passed alone in a window and timed out ("Test timed out after 5min") on its
  first test when it ran after `test_night_crosshair` in one session, in either order; headless (CI) both always passed.
  The log stopped after the warm-up's resource loads.
- **Cause:** the same one as a pixel test three days before
  ([lesson](2026-11-02-a-pixel-test-hung-or-read-a-blank-picture-in-a-minimized-window.md)), met again in the game's
  code: GdUnit minimizes the window after every suite, a minimized window draws no frame, and `NightWarmup._shots`
  waits for `RenderingServer.frame_post_draw`, which never came. A print of
  `Engine.get_frames_drawn()` and the window mode before that `await` named it at once (mode 0 in the first suite, mode
  1 and a frame count standing still in the second). The earlier lesson was fixed in one test (`force_draw`), so the next
  suite that waited for a frame met the same thing.
- **Fix:** a suite that needs drawn frames puts the window back in `before()` (`WindowFixture.make_drawable`, which waits
  for two drawn frames and prints an error after five seconds in place of a hang); a headless guard fails a suite that
  opens a night and does not call it. The pair passes in a window in both orders (54 s each), no timeout lengthened.
  Check for next time: a windowed run of two suites in one session, in both orders, before a pull request that adds a
  suite which waits for a drawn frame; and read which `await` hangs (frame count and window mode) before touching a
  timeout.
- **Docs:** [A minimized window draws nothing](../godot/minimized-window.md).
