---
areas: [godot-ui, godot]
---
# A HUD part read `global_transform` of a model before it was in the tree

2026-11-03

- **Saw:** `ERROR: Condition "!is_inside_tree()" is true. Returning: Transform3D()` from `get_global_transform`, and a
  silhouette sized from an identity transform (wrong bounds, no crash).
- **Cause:** `HudPart.bind` runs `refresh` at once; a part bound before it was added to the tree (a capture, a test, a
  HUD built by code) built its `SubViewport` and weapon model, whose `MeshInstance3D`s are not "inside the tree" yet.
- **Fix:** do not use `global_transform` for geometry computed at build time: multiply the `transform`s up the parent chain
  to the frame wanted (`WeaponSilhouettes._relative`), which works in or out of the tree. In general a part's `refresh`
  must not need the tree.
- **Docs:** Deadnight `docs/research/hud.md` ("Weapon slots").
