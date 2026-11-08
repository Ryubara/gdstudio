---
areas: [godot, tests]
---
# A tick-rate test read the old physics delta after two physics frames, under load only

2026-11-03

- **Saw:** a test that set `Engine.physics_ticks_per_second` and awaited two `physics_frame` before hand-stepping the
  body failed in 4 of 8 runs with four other Godot suites running, never on a quiet machine: the delta it read was
  the old one (`0.0333` where `0.0167` was set), then the distances were off by a factor of the rates.
- **Cause:** the engine reads the tick rate once per main-loop iteration; a loaded machine runs several physics steps in
  one iteration, all with the old step, so two `physics_frame` can both be inside the iteration that set the rate. It
  was not an idle frame (the steps were already in physics callbacks), so the idle-frame lesson did not apply.
- **Fix:** after setting the rate, await `physics_frame` until `get_physics_process_delta_time()` equals `1 / hz`
  (bounded at 60 frames), then assert it and measure as before. Never count frames to mean "the new rate is in".
- **Docs:** [Test speed](../engines/godot/test-speed.md).
