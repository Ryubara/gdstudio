---
areas: [tests, input, godot]
---
# A drag-rate test timed real frames and divided each turn by the wrong frame

2026-11-03

- **Saw:** Deadnight's "steady slow drag" touch case (#664) passed on a quiet machine and measured 0.38 to 1.13 against
  a 0.35 bound when other Godot jobs ran, on a clean `main` too. Two agents lost runs to it.
- **Cause:** the test fed the finger by `Time.get_ticks_usec()` and ran on real frames, so a loaded machine gave 7 ms
  frames with a 41 ms hitch and 1 to 2 ms catch-up frames after it. It also read the clock before `await process_frame`
  and the yaw after, so each turn was divided by the length of the frame before it. The game was fine: `LookSmoother`
  scales by the frame's `delta`, and at 240, 180, 144, 90 and 60 Hz the turn rate was the same 0.059 rad/s.
- **Fix:** the test keeps its own clock: it turns the layer's `_process` off, sends each sample with
  `Input.flush_buffered_events()` and calls `_process(length)` by hand with a chosen frame length (a seeded uneven run
  too), then divides each frame's turn by that same frame's length. Same bound, 20 loaded runs pass.
- **Check:** a rate measured per frame is run on lengths the test chooses, and each value is paired with the length of
  the frame that made it; find the cause (the test or the game) by measuring the game on that clock before touching a
  bound.
- **Docs:** [Godot testing](../engines/godot/index.md#testing-and-capture); the earlier
  [smoothness test](2026-11-01-a-smoothness-test-read-the-real-clock.md) is the same family.
