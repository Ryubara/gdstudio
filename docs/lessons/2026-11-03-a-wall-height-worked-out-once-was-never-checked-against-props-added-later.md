---
areas: [tests, gameplay]
---
# A wall height worked out once was never checked against the props stacked at it later

2026-11-03

- **Saw:** with the last door bought, a player left the lot over the ticket plaza's corner in three hops by movement
  alone: a crate (0.63 m), a small container beside it (1.71 m), then a sprint-jump over the 3.0 m walls onto the floor
  outside, where nothing could reach them (Deadnight #845, found by the map review sweep, #833).
- **Cause:** the 3.0 m walls were derived once ("a car roof 1.65 m plus a jump 1.1 m plus a margin") and written in a
  comment. The plaza was built later (#686) with its junk stacked against the same wall, and nothing re-ran the
  sum: the container's top stood 1.29 m under the wall, and the real body climbs 1.25 m (not the jump's 1.1 m), so a
  run-up and a corner made up the 0.04 m. The jump-reach test only tried car roofs and took 1.1 m as the reach.
- **Fix:** raise the walls to the tallest standable prop beside them plus the measured reach plus 0.5 m (4.2 m), and
  pin it with three tests that run on the shipped scene: a replay of the recorded hops (fails on the old walls), a
  sweep of hops from the plaza's floor with the real body (depth three), and a static margin check. The margin check
  counts only props a body can stand on (top within two climbs); the first version counted the canopy and a marquee
  and failed on a wall that was fine. A moved wall also changes the baked navigation key: re-bake
  (`tools/world/bake_lot_navmeshes.gd`) or `test_lot_navmeshes.gd` fails.
- **Docs:** [Map review: collision hygiene](../engines/godot/map-review.md#7-collision-hygiene-out-of-bounds-and-skipped-doors).
