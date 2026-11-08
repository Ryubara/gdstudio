---
areas: [blender]
---
# Helmet and shoulder pads floating after applying scale

2026-11-01

- **Saw:** the cleaned Soldier rendered with a bare head; his helmet and pads floated far above him.
- **Cause:** `transform_apply(scale=True)` on the armature does not keep meshes parented to a bone in place.
- **Fix:** record their world matrices at rest pose before the apply and set them back after.
- **Docs:** [Rig sharing (Blender)](../tools/blender/rig-sharing.md#what-broke).
