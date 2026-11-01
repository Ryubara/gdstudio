# Meshes parented to a cleaned armature land at the feet

2026-11-01

- **Saw:** hats and glasses built in world space and parented to the cleaned Quaternius armature sat on the floor,
  turned 90 degrees.
- **Cause:** the clean-up applies only the armature's scale; it keeps the glTF import's 90 degree X rotation, and a new
  child with no parent inverse is transformed by it.
- **Fix:** set `child.matrix_parent_inverse = arm.matrix_world.inverted()` when parenting.
- **Docs:** [Character variants from one rig](../blender/variants.md#modular-parts).
