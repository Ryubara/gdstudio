---
areas: [gameplay, tests]
---
# A tree trunk set "above a jump" was a step from a car roof over the perimeter fence

2026-11-03

- **Saw:** the first run of Deadnight's whole-map sweep test (#848) stood the real body on a car's hood, then its roof
  (1.64 m), then the top of a small tree's trunk collider (2.39 m), and in a fourth hop past the 3.0 m north fence onto
  the floor outside the map. The map review (#833) had swept the same map and the reach tests passed.
- **Cause:** the generator made every tree solid "only at its trunk, up to 2.4 m, above a jump, so nobody climbs a
  tree". That holds from the floor; a car roof 4.6 m away is a sprint-jump from the trunk's top, and a 0.3 m-wide
  collider was never thought of as a wall. The review's sweep started on the floor near walls, on a coarser grid, and
  never landed on the roof that leads to it; the reach tests listed boxes, and the trunk is a cylinder.
- **Fix:** trunks run to 4.0 m (every tree model is over 4 m), 2.29 m over the tallest prop a player stands on; a
  test checks every trunk's top against the tallest top within 6 m plus the reach plus 0.5 m, and the sweep test, which
  starts on every prop top within the reach near a barrier, replays the old chain.
- **Check for next time:** any "not standable" height in a generator (a wall, a post, a trunk, a sign) is judged
  against the tallest standable top within a hop (about 5 m at a sprint) plus the measured reach, never against the
  jump from the floor; a sweep's starts are the props, not only the floor.
- **Docs:** [Map review, collision hygiene](../godot/map-review.md#7-collision-hygiene-out-of-bounds-and-skipped-doors),
  [Level design, P13](../research/level-design.md#p13-the-real-bodys-reach-not-the-jump-height).
