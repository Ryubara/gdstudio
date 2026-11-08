---
areas: [tests, godot]
---
# A replay test recorded with the engine's physics delta and replayed with a constant

2026-11-02

- **Saw:** Deadnight's `test_a_replay_crouches_and_stands_the_same` failed in two full runs of `tests/player` and
  `tests/art` (the replayed position 5.6 mm from the recording, limit 1 mm) and passed alone every time. It did not
  fail in 5 more full `tests/player` runs, 3 at once, or 12 runs alone, so the failure could not be reproduced on demand.
- **Cause (probable: found by reading and shown by injecting the difference, never seen in a real run):** the
  two halves did not run the same call. The recording went
  through `Player.tick`, which steps by `get_physics_process_delta_time()` (the engine's physics step times the time
  scale); the replay called `PlayerSimulation.simulate` with the constant `TICK`. They are one number only while
  nothing has changed the tick rate or the time scale, and a suite that ran before could do that (another suite
  changes `Engine.physics_ticks_per_second`, and the delta the player reads follows a step or two later). With the tick
  rate set to 90 before the recording, the old test fails and the same test with both halves on `TICK` passes.
- **Fix:** both halves call one helper, `_simulate`, which is `PlayerSimulation.simulate(..., TICK)`: the simulation
  rescales the engine's step to `TICK` the same way for both. The recording no longer runs the player's camera,
  animation or engine delta, none of which the test is about.
- **Check for next time:** a record-and-replay test steps both halves through the same function with the same
  arguments, taken from constants and not from the engine (`get_physics_process_delta_time`, `Engine.time_scale`,
  the wall clock); then inject the difference you suspect (here the tick rate) into a copy of the old test and see it
  fail.
- **Docs:** [Test speed](../engines/godot/test-speed.md).
