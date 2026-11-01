# `Engine.time_scale` gave a headless bot a coarser fixed step

2026-11-01

- **Saw:** a headless autopilot at `Engine.time_scale = 10` started round 1 after 1 s of ticks instead of 12 s.
- **Cause:** `time_scale` scales the delta each `_physics_process` gets, so the fixed step is no longer fixed.
- **Fix:** leave `time_scale` at 1 and run several fixed ticks per physics frame, each with the constant step; a
  headless night then plays about 1500 ticks a second and stays the same night.
- **Docs:** [Godot testing](../godot/index.md#testing-and-capture).
