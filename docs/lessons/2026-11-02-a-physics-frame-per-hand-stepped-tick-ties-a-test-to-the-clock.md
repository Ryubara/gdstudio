---
areas: [godot, tests]
---
# A test that steps by hand but waits a physics frame per tick runs at wall-clock speed

2026-11-02

- **Saw:** Deadnight's CI `godot` job was cancelled at its 20-minute limit with no failed test; one new suite took 38 s.
- **Cause:** its `_ticks` stepped the camera and animation by hand but did `await get_tree().physics_frame` before
  each tick, so 2,200 ticks ran at 60 a second of real time; the suite on `main` was already at 16 to 20 minutes.
- **Fix:** turn off the player's `_physics_process`, call its `tick(sample_command())` and the hand steps back to back,
  and wait one `process_frame` per measurement (the skeleton modifiers keep no clock): 1.7 s, same poses and limits.
- **Docs:** [Godot testing](../engines/godot/index.md#testing-and-capture); Deadnight #524 (the job's time budget).
