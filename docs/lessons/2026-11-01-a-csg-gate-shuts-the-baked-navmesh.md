# The dead had no path through a gap closed with CSG boards

2026-11-01

- **Saw:** zombies spawned outside a fence gap, closed by boards made of `CSGBox3D` with collision, found no path in.
- **Cause:** a navigation bake that reads the CSG boxes with collision (the greybox baker does) counts every one as a
  wall, so a gate drawn as CSG shuts the gap in the mesh, whatever the game later does with it.
- **Fix:** make anything that opens and closes at run time (boards, anything a rule removes) a `StaticBody3D` with a
  box shape, which the CSG baker never reads, and hold the zombies at it in the simulation, not with physics.
- **Docs:** deadnight's `docs/research/zombies.md`, "The fence's boards".
