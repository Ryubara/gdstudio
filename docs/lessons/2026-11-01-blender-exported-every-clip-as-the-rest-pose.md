---
areas: [blender, web]
---
# Blender exported every clip as the rest pose

2026-11-01

- **Saw:** the cleaned zombie's glTF had 16 clips of 150 channels each, none of them moving; Godot imported 4 tracks.
- **Cause:** the clean-up set `armature.data.pose_position = "REST"` before the export; the exporter samples clips
  through the pose, so it sampled the rest pose.
- **Fix:** leave `pose_position` at `POSE` and zero the pose bones instead.
- **Docs:** [Rig sharing (Blender)](../blender/rig-sharing.md#what-broke).
