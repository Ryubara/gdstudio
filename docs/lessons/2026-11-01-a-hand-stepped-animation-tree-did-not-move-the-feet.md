---
areas: [blender, godot]
---
# A hand-stepped AnimationTree did not move the feet

2026-11-01

- **Saw:** a GdUnit test stepped the player's tree with `advance()` and read `get_bone_global_pose()` of the feet: they
  never moved.
- **Cause:** two things. The body state machine was still at `Start`: its only way into locomotion was the player's
  first landing, and physics was off. And the skeleton refreshes global poses on a deferred update that stepping by
  hand never reaches.
- **Fix:** `playback.start(locomotion)` in the test, and compose the bone's position from its local pose
  (`get_bone_pose_position/rotation`) and its parent's global pose.
- **Docs:** [Rig sharing (Godot)](../engines/godot/rig-sharing.md#found-later).
