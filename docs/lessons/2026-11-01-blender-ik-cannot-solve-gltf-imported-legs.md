---
areas: [blender, godot]
---
# Blender's IK constraint could not solve glTF-imported legs

2026-11-01

- **Saw:** an IK constraint on `LowerLeg` (chain 2, the kit's pole target) put the legs 100 to 270 degrees away from
  the kit Run's own legs, whatever the pole angle.
- **Cause:** glTF stores no bone tails; the importer gives every bone an arbitrary length (0.518 on the zombie), so the
  solver works with the wrong thigh and shin.
- **Fix:** a two-bone solve in script, with the thigh and the ankle (the `Foot` bone's head in the lower leg's frame)
  measured from a kit clip.
- **Docs:** [Gaits from kit clips](../blender/gaits.md).
