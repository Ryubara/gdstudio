# An IK modifier at influence zero still held the arms

2026-11-01

- **Saw:** in a running game the Soldier's repair clip and its hammer never showed: the arms stayed in the gun pose,
  while every headless test read the clip's arm (and the hammer) where they should be.
- **Cause:** Deadnight's `WeaponHandsIK` (a `SkeletonModifier3D` that sets the arm bones in `_process_modification`)
  was blended out with `influence = 0`, which still left its pose in the drawn skeleton (Godot 4.7.2). Tests that read
  `get_bone_global_pose` outside a rendered frame see the pose before the modifiers.
- **Fix:** switch the modifier off (`active = false`) whenever its blend is 0; prove arm clips with a capture of a
  running scene, not only with bone reads.
- **Docs:** [Weapons in the Toon Shooter style](../blender/weapons.md#axes-origin-and-the-hold).
