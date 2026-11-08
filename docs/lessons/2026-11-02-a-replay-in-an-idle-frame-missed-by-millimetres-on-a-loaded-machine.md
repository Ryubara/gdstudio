---
areas: [godot, tests]
---
# A replay in an idle frame missed by a few millimetres once in six runs

2026-11-02

- **Saw:** a test that recorded a crouch-and-jump run and replayed it from the start state ended 0.2 to 6 mm from the
  recording (limit 1 mm), in about one full run of six, and never alone.
- **Cause:** `move_and_slide` steps an idle frame by its wall-time delta, so `PlayerSimulation` rescales the velocity
  to the tick it wants; the rescaled step is not exact against a beam's contact margin, and the delta changes with
  the load. A recording made in one physics callback and a replay in an idle frame are two different deltas.
- **Fix:** a test that is not about idle frames records and replays in physics callbacks (delta exactly one tick);
  the idle-frame case lives in one suite that runs it on purpose (`test_player_reconcile`).
- **Docs:** [Test speed](../engines/godot/test-speed.md).
