---
areas: [tests, godot]
---
# A grid point on a wall's face counted as room for a body

2026-11-04

- **Saw:** with the second map's real overlaps fixed, Deadnight's spacing sweep (`test_use_zone_spacing.gd`) still
  failed on one pair: the side room's ammo locker and the hall's stair link, "2 points, e.g. (4.5, 1.0, 0.0)". The point
  is on the stair, exactly on the face of the wall between the hall and the side room (z 0.0); the locker is behind
  that wall (#994).
- **Cause:** the sweep keeps a grid point only when eight 0.4 m rays from it hit no wall ("room for a body"), and the
  sight test from it to the locker found no wall either: both rays started on the wall's face. The walls are CSG with
  collision, a concave trimesh of one-sided triangles: a ray that starts on a face does not hit that face,
  `hit_from_inside` does not change it (it is for convex shapes), and a point query inside the wall finds nothing. The
  0.25 m grid lands on whole-metre wall lines, so the same thing can happen on any map.
- **Fix:** each spoke starts 5 cm behind the point (`FACE`), so from a point on a face the ray crosses the face. Teeth:
  the new sweep on main's old scene still lists every real pair (eleven), with only the face pair gone.
- **Check for next time:** a probe that asks "is there room here" with rays starts the rays behind the point or uses a
  convex shape query; when a sweep reports a pair whose example point sits on a wall line, look at the geometry before
  moving anything.
