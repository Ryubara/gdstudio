---
areas: [godot, tests]
---
# A before and after capture differed on 70 % of a frame because the renderer chose other lights

2026-11-03

- **Saw:** Meshes merged into per-cell meshes drew the same picture except one view where 70 % of the pixels differed
  (mean 0.04, the ceiling lit differently), though every material and
  transform matched.
- **Cause:** With every lamp on, the lot has more lights reaching a mesh than the Compatibility renderer draws
  (`max_lights_per_object`, 8), and which it keeps follows the mesh's box and order. A merged mesh has a different
  box, so it keeps other lights. Not a bug in the merge: the picture was never defined with every circuit on.
- **Fix:** Compare under the lights a night starts with (only the starting circuits on), split a cell until no more lights
  reach it than the map's own cap less the room a fight needs (`MeshBatch` takes the lights and a budget), and pack
  pieces that stand in one place (a floor and the ceiling over it) into cells by what they add to the reach, since
  splitting by position cannot separate them. A test holds every built mesh to the budget.
- **Docs:** Deadnight `docs/research/phone-frames.md` (the batching section), kit `docs/godot/compat-lighting.md`.
