---
areas: [blender, godot]
---
# A navmesh baked from CSG boxes was empty, then 0.5 m too high

2026-11-01

- **Saw:** the standard geometry parser ignores `CSGBox3D`, so baking a greybox gave no polygons; feeding `add_mesh`
  from `CSGShape3D.get_meshes()` warned about reading meshes back from the GPU; wrongly wound triangles gave 0 polygons;
  the surface came out 0.5 m above the box tops.
- **Cause:** CSG nodes are neither meshes nor static bodies to the parser, walkable faces need an upward normal in
  Godot's winding, and the baker lifts the surface by twice the cell height.
- **Fix:** add faces built from each box's size with `NavigationMeshSourceGeometryData3D.add_faces(faces,
  shape.global_transform)`; on a flat floor keep the spawn height instead of the path's.
- **Docs:** [Zombie crowds](../godot/crowds.md); Deadnight `docs/research/zombies.md`.
