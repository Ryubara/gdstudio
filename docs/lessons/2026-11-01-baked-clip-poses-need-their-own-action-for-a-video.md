---
areas: [tools, blender]
---
# Baked clip poses need their own action for a video

2026-11-01

- **Saw:** keying the dead's pose bones frame by frame for a Discord preview video, after setting each frame's pose
  from a glTF clip, would have left every frame on a fresh action (or on the clip's own action).
- **Cause:** the pose helper plays the clip's action, copies the pose and clears the action; `keyframe_insert`
  with no action makes a new one each call, and putting the clip back replaces the keys.
- **Fix:** make one `Video_<armature>` action, and after each frame's pose (and before any depsgraph update) assign
  it and its slot, then key the bones; assign it once more at the end.
- **Docs:** [Key art](../blender/key-art.md#title-art-and-store-sizes).
