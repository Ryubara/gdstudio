---
areas: [blender, gameplay]
---
# A rebuilt glb differed from the committed one with no change to the model

2026-11-01

- **Saw:** rebuilding Deadnight's weapons with the unchanged script gave files whose bytes differed from the committed
  ones, and two runs of the same script differed from each other.
- **Cause:** Blender's glTF export does not keep the triangle order from run to run. The vertices, normals and UVs are
  identical, and so is the set of triangles.
- **Fix:** compare a rebuilt file by its nodes, mesh count, vertex buffers and sorted triangle set, not by its bytes.
  Commit only the files the change is meant to touch.
- **Docs:** [Weapons](../blender/weapons.md#building-by-script).
