---
areas: [tests, godot]
---
# A clip kept playing while the probes waited, so one pose gave several numbers

2026-11-04

- **Saw:** Deadnight #1143. `test_the_swing_skirt_holds_the_legs_in_and_keeps_the_hands_out` gave `10 Run leg` 0.144,
  0.142 and under the limit (0.142 = recorded 0.137 + 0.005) on the same art, and failed two of three pull requests
  that touched no character file. Measured alone, in one process, the same pose gave 0.1348, 0.1348, 0.1377.
- **Cause:** `ClipFit.pose` did `play` and `seek(t, true)` and left the clip playing. `BodyFit.read_pose` stores the
  surface at once, but `prepare_sets` awaits two physics frames, and the player went on with the real time of those
  frames (the longer the machine was loaded, the further). `BodyFit.bone_point` reads the live skeleton, so the legs'
  lines came from a later pose than the wall: a knee moved up to 6 cm between the two. Not the suites before it: the
  order only changed how long a frame took.
- **Fix:** `ClipFit.pose` ends with `_player.pause()`: a sampled pose stays where it was sampled. Eight repeats in two
  processes gave 0.1348 each, below the recorded 0.137, so no value changed.
- **Check for next time:** a test that reads a pose, awaits, and reads the pose again holds the clip first (pause, or
  `speed_scale` 0); repeat a measure that awaits a few times in one process before you pick a limit for it.
- **Docs:** Deadnight `docs/research/soldier-parts.md`, "Fit".
