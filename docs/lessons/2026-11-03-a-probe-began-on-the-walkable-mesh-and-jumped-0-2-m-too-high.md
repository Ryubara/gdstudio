---
areas: [tests, godot]
---
# A movement probe began each hop on the walkable mesh, 0.2 m above the floor, and climbed what a player cannot

2026-11-03

- **Saw:** a sweep of the real player body from every ground cell reported a player on top of a 2.4 m playground frame
  and on the start-room counter; replayed from the real floor, the frame could not be climbed (Deadnight #833).
- **Cause:** a navigation mesh floats above the floor by its cell height and agent offset (0.2 m here); the body was
  placed at the mesh's height with `on_floor` set, so it jumped from 0.2 m up. Also, a mesh baked with the doors closed
  still holds the closed rooms' floors as islands: ground that "is on the mesh" was counted as reached without
  asking whether the start can walk there.
- **Fix:** start every hop at the solid floor found by a ray (`_floor_under`), and call ground reached only when a path
  query from the start ends on it; replay any claimed chain hop by hop from the real floor before it is filed.
- **Docs:** [Map review, collision hygiene](../engines/godot/map-review.md#7-collision-hygiene-out-of-bounds-and-skipped-doors).
