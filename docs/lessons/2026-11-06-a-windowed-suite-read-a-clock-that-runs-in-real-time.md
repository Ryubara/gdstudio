---
areas: [tests, godot-ui, ci]
---
# A windowed suite read a card and a chase of bulbs by a clock that runs in real time

2026-11-06

- **Saw:** the first scheduled windowed run of Deadnight (issue 1348) failed `test_hud_challenge` ("the card is not
  shown", once "leaves the canvas" at x -19.6) on the canvases of 2340 units and up, and `test_level_ink` (the digits'
  centre 5 to 11 px off the icon's) on the phone readings of the lobby, both passing headless and on a GPU window. The
  first guess, a window clamped to the 1920 x 1080 screen, was wrong (a probe on the runner opened 2880 x 1620).
- **Cause:** both read something with a clock of its own. The challenge card's `_process` added each frame's real length
  to its hold, and the test let 40 frames pass; a frame of a large window is 0.1 to 1 s on llvmpipe, so the card had
  faded and slid away. The lobby panel's marquee chase (`UIPanel`, a step every 0.15 s) moved between the three pictures
  of the reading, a bulb lit in one and not in the next counted as digit ink, and whether it fell in the digits' area
  depended on the frame times (failed in one reading, then another, passed in a third). A first regression case with
  `Engine.time_scale = 1000` failed for the wrong reason: GdUnit's own timeout runs on that scale ("timed out after
  5 min" in 259 ms).
- **Fix:** step the card by hand (its `_process` off in the test) and hold the chase still with reduced motion, and a
  case for each that fails without it in any run: `Engine.max_fps = 5` for the card (a frame of 0.2 s, headless too),
  and "no marquee panel is processing" for the lobby. A flaky windowed result is a time: make the run slower (saving the
  pictures did it) and keep what each run saw.
- **Docs:** the kit's [Windowed GdUnit on a Linux runner](../godot/windowed-gdunit-on-linux.md) and Deadnight's
  `docs/research/windowed-vs-headless-tests.md`.
