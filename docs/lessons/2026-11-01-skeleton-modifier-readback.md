# A skeleton modifier's pose was gone when a test read it

2026-11-01

- **Saw:** an arm IK modifier visibly put both hands on the gun, but a test reading `get_bone_global_pose` after the
  frame found the hands where the clip had them.
- **Cause:** a `SkeletonModifier3D` result is applied for the skeleton's update and then the pose returns to the
  animation's; outside that window the skeleton reports the clip's pose.
- **Fix:** read modified poses in a handler for the skeleton's `skeleton_updated` signal (or from the modifier's own
  `_process_modification`), and test there.
- **Docs:** [Rig sharing](../godot/rig-sharing.md#skeleton-modifiers).
