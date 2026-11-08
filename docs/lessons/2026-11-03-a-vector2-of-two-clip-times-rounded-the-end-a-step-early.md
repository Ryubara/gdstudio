---
areas: [godot, tests]
---
# A `Vector2` of two clip times rounded the end up a step early

2026-11-03

- **Saw:** after moving Deadnight's perk drink into its own class (#912), the clip's last event (`done`) fired, but the
  drink did not end on that step: the test read `is_drinking()` true just after `done`, with the layer's time printed as
  2.500000000 against a length of 2.5.
- **Cause:** the layer returned the step's (from, to) as a `Vector2`, whose components are 32-bit floats. The time
  (a 64-bit GDScript `float`, summed from 1/60 steps) was 2.4999999999999996; stored in the `Vector2` it rounded to 2.5,
  so the event check (`at <= to`) fired `done`, while the end check on the 64-bit time (`time >= length`) did not.
- **Fix:** keep times in `float`s: the step returns where the clip was before and the caller reads the new time from
  the layer. Any value compared against another must not pass through a `Vector2`, `Vector3`, `Color` or a packed
  float array on the way (all 32-bit in a standard build).
- **Docs:** [Animation trees](../engines/godot/animation-tree.md#stepping-a-tree-by-hand-in-tests).
