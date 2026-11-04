---
areas: [godot, blender, tests]
---
# Every soldier held the whole wardrobe, hidden

2026-11-04

- **Saw:** Deadnight's #1086 added 13 wearable pieces and the late-round budget failed: `mesh_instances` 2,728 of 2,600.
  Sixteen meshes of mouths had already taken main from 2,402 to 2,534, for no visible change in a night.
- **Cause:** one `.glb` holds every part and dressing only hid what a look did not wear. A hidden `MeshInstance3D` is
  still a node and a counted instance, and the tree walk enters SubViewports, so four bodies and four HUD portraits made
  each mesh in the file cost eight. A wardrobe that grows by a third would break any limit.
- **Fix:** free what the look does not wear when dressing (136 meshes to 11-15 a soldier; 2,718 to 1,734 on one run) and
  take a part back from a fresh copy on a look change, about 2 ms. Do not park the nodes off the tree: they count as
  orphans. Clear `owner` before moving a node out of its scene, or `add_child` warns. Before a catalogue grows, multiply
  by how many copies are alive, and test a count that does not depend on the catalogue's size.
- **Docs:** [Deadnight #1086](https://github.com/Ryubara/deadnight/pull/1086), its `docs/research/soldier-parts.md`.
