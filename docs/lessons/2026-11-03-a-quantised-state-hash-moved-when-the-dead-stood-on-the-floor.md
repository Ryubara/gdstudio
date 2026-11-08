---
areas: [tests, gameplay]
---
# A change to what the dead stand on failed a replay test, and a new test waited a fixed frame count for the mesh

2026-11-03

- **Saw:** after the dead were given a floor to stand on (Deadnight #681), `test_bot_night` scenario 24 (a replay of a bot
  night gives the same state) failed five runs in six, and the new climb tests failed 2 of 6, then 0 of 16, in some runs
  and passed in others.
- **Cause:** the replay hash put each zombie's place on a quarter-metre grid; a live run and its replay differ by a
  centimetre or two (with or without the change), so the hash only matched when no value sat on a grid edge, and the
  change moved the edges. The climb tests gave the engine 12 physics frames for a bought door's mesh, the edge the
  kit's lesson on a fixed frame wait for a navigation mesh already names; under load a pack walked an old map.
- **Fix:** leave the zombie's place out of the hash (its own docstring already named it as untrustworthy); wait for the
  answer instead of a count (poll until a path ends within a metre of the goal and the bake is not busy). Run a
  determinism or climb test five times before trusting a pass.
- **Docs:** [Navigation in tests](../engines/godot/navigation-in-tests.md); the same rule as
  [a fixed frame wait](2026-11-03-a-fixed-frame-wait-for-a-navigation-mesh-failed-one-run-in-three.md).
