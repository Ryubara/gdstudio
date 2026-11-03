---
areas: [tests, godot]
---
# A sweep test started the body inside a wall, a trap a lesson already named

2026-11-03

- **Saw:** Deadnight's second-map sweep test (#848) reported three ways out of the building, every one a hop from a
  floor cell at z 14.75, inside the hall's 0.3 m south wall: the body started in the wall and the solver pushed it out
  the far side.
- **Cause:** the start check was "a capsule query returns nothing". A CSG box collides by its faces, one-sided, so a
  capsule (and a ray, even with `hit_from_inside`) whose middle is inside a thin wall meets no face and the query says
  the cell is clear. The [camera sweep lesson](2026-11-01-camera-sweep-started-inside-a-wall.md) said exactly this two
  days earlier; I searched the lessons for "sweep" and "reach", not for the query I was about to trust.
- **Fix:** the sweep keeps the bounds of every collidable CSG box (in 4 m squares) and refuses a start whose capsule
  overlaps one at body height, besides the query. The three reports went, and nothing a body can reach was lost.
- **Check for next time:** before trusting a physics query in a probe or a test, search the lessons for the call
  (`intersect_shape`, `intersect_ray`, `cast_motion`) and the shape (CSG, concave); a "clear" cell is proved by
  bounds, not by a query that cannot see from inside.
- **Docs:** [Map review, collision hygiene](../godot/map-review.md#7-collision-hygiene-out-of-bounds-and-skipped-doors).
