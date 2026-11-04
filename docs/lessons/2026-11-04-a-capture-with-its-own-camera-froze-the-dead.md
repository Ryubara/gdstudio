---
areas: [tests, godot]
---
# A capture with its own camera froze the dead on their first pose

2026-11-04

- **Saw:** Deadnight's window capture (#991) showed a new climb clip as an upright body gliding over the sill. A probe
  printed the right state and a playhead that never moved, and the "before" sheets taken for the pull request were
  frozen the same way; the suites passed, because a test advances the view by hand.
- **Cause:** the crowd's animation throttle poses only the zombies its camera can see. It held the night's camera,
  which looked elsewhere, and the capture drew through a `Camera3D` of its own: nothing was ever advanced.
- **Fix:** a capture that makes its own camera gives it to the throttle (`horde.throttle.camera = camera`); then take
  the "before" sheets again, from a checkout of main with the fixed capture script. Print a playhead twice before
  reading a pose.
- **Docs:** [Crowds](../godot/crowds.md).
