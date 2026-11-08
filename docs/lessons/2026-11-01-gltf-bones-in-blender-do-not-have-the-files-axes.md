---
areas: [blender, godot]
---
# A weapon held with Godot's hold numbers sat wrong on a glTF bone in Blender

2026-11-01

- **Saw:** placing a weapon on the imported soldier's hand bone with the game's `HOLD_GUN` transform put it at the
  wrong angle in the key-art render (Deadnight #438).
- **Cause:** Blender's glTF importer gives bones Blender axes, not the file's node axes, so a transform made for the
  file's bone in Godot does not apply to Blender's bone as is.
- **Fix:** compute the rest correction from the `.glb`'s own node tree,
  `C = bone.matrix_local^-1 @ (M_gl @ node_rest)`, and place the weapon at
  `arm.matrix_world @ pose_bone.matrix @ C @ HOLD @ M_gl^-1`.
- **Docs:** [Key art](../tools/blender/key-art.md).
