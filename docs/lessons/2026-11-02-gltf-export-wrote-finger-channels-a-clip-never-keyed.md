---
areas: [blender, web]
---
# Blender's glTF export wrote finger channels a clip never keyed

2026-11-02

- **Saw:** clips authored to leave the fingers to a runtime grip modifier still carried 22 finger bones
  (66 channels) in the .glb, and Godot kept 14 finger tracks after import.
- **Cause:** with NLA-track export and forced sampling, the exporter writes a channel for every bone of every clip,
  sampled at whatever the pose bone holds; Godot's immutable-track removal does not drop them all.
- **Fix:** after the export, remove the unkeyed bones' channels (and unused samplers) from the .glb JSON chunk;
  test the imported clip has no such track (Deadnight `tools/blender/build_soldier.py`, `strip_channels`).
- **Docs:** [Rig sharing (Blender)](../blender/rig-sharing.md).
