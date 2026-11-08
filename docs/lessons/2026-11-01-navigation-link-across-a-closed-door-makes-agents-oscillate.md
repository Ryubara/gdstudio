---
areas: [process, gameplay]
---
# A NavigationLink across a door slab left agents walking back and forth on it

2026-11-01

- **Saw:** zombies reached the link at an opened door and then shuffled a few centimetres to and fro for as long as the
  run lasted, though the link was enabled and paths crossed it.
- **Cause:** a mesh baked with the slab has an empty band round it (slab plus agent radius each side, 1.3 m). An agent
  in the band is off the mesh, so each repath snaps it back to the near edge and the path restarts at the link.
- **Fix:** do not bridge a baked wall with a link for agents that repath often: rebake when the door opens
  (`bake_from_source_geometry_data_async`, about a second for a 124 x 116 m lot) and swap the mesh in, or do not repath
  while an agent is on a link.
- **Docs:** [Zombie crowds](../engines/godot/crowds.md); Deadnight `docs/research/zombies.md` (Doors).
