---
areas: [tests, godot]
---
# A pixel test hung, or read a blank picture, when another suite ran before it in a windowed GdUnit run

2026-11-02

- **Saw:** Deadnight's outline pixel test passed alone, but in a folder run after another suite its first test hung on
  `await RenderingServer.frame_post_draw` (the log ended on `ERROR: BUG: Unreferenced static string to 0:
  _exit_world`); with a plain `process_frame` wait it read a 3 KB all-grey picture and failed its counts.
- **Cause:** a windowed run under `gds godot` is minimized (the no-focus wrapper) and the window was minimized
  (`DisplayServer.window_get_mode() == 1`) once a suite had run: a minimized window draws no frames, so a
  `SubViewport` never updates and `frame_post_draw` never fires.
- **Fix:** draw by hand: after one `process_frame`, call `RenderingServer.force_draw(false)` three times (the first
  builds the shaders) and read the texture; never wait for `frame_post_draw` in a test that may run minimized. Run the
  test alone and in its folder, in both orders.
- **Docs:** [Measuring an effect on the screen](../godot/measuring-effects-on-screen.md) and
  [Outline through walls](../godot/outline-through-walls.md#only-where-it-is-hidden).
