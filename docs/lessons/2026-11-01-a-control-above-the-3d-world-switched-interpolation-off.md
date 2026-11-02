# A fix proved in a test room never reached the game: a Control above the 3D world switched interpolation off

2026-11-01

- **Saw:** the maintainer played the live web build after the physics-interpolation fix (Deadnight #352) and the
  soldier still juddered from the side; the fix had passed every test and a desktop measurement.
- **Cause:** `physics_interpolation_mode` is inherited down the tree and a `Control` is not interpolated. The night
  hangs under a `NightScreen` (a Control), so everything below it was drawn at the last tick; the tests ran a room
  under a plain `Node`.
- **Fix:** the 3D world's root sets its own mode to ON (`Night._init`), which overrides the inherited OFF; a test and a
  browser flag check it in the tree the game builds, and a browser probe measures the soldier's screen position per
  frame (Deadnight #385): unevenness 9.06 px before, 0.26 px after.
- **Docs:** [Physics interpolation](../godot/physics-interpolation.md).
