---
areas: [godot, tests]
---
# A bone attachment stood still under a hand-stepped animation

2026-11-01

- **Saw:** a test stepping a player's `AnimationTree` by hand (manual callback mode, `advance(delta)`) read a
  `BoneAttachment3D`'s `global_position` through a whole clip and got the same point every tick.
- **Cause:** the attachment copies its bone when the skeleton is updated in a processed frame; stepping the tree by hand
  in one frame moves the bones but not the attachment.
- **Fix:** read the bone itself, `skeleton.global_transform * skeleton.get_bone_global_pose(bone)`, times the
  attachment child's own transform.
- **Docs:** [Weapons in the Toon Shooter style](../blender/weapons.md#axes-origin-and-the-hold).
