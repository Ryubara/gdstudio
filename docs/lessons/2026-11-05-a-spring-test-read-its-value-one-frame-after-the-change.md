---
areas: [tests, godot-ui]
---
# A spring test read the value one frame after the change and failed whenever a frame was short

2026-11-05

- **Saw:** `Expecting to be less than: 1.000000 but was 1.000000` one idle frame after `button_pressed = false`, in a
  headless run with no load, after the same test had been fixed for the window (#1202). It passed in CI and in a 60 Hz
  window.
- **Cause:** `UISpring.step` integrates one step for each whole 1/240 s it has been given, so a frame shorter than
  4.17 ms moves nothing. The control had set the target on that frame (a probe printed target 0.0, value 1.0, a frame
  delta of 0.2 ms to 20 ms in one run); the test asserted a movement after one frame. The game was right.
- **Fix:** assert what one frame does settle (the target), wait in time for the value to leave its start, assert it is
  strictly between the ends, then settle for the exact end. Check for next time: sweep the suite with
  `--fixed-fps 1000 480 240 60 10` (headless and through `gds godot`); a test that reads a `delta`-driven value after a
  count of frames, even one, fails the sweep at 1000. The same count of 120 frames in three sibling suites failed it
  too (Ryubara/deadnight#1219).
- **Docs:** the game's `docs/research/windowed-vs-headless-tests.md`, "One frame is not a length of time either".
