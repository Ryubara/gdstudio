---
areas: [camera, blender]
---
# A camera in ZXY Euler order spun off its subject

2026-11-01

- **Saw:** a key-art camera aimed from a subject's wanted screen position (a yaw and a pitch) rolled and pointed away
  from it (Deadnight #438).
- **Cause:** in `ZXY` order the pitch is applied outside the yaw, so the yaw turns about a tilted axis.
- **Fix:** set `rotation_mode = "XYZ"` (yaw outermost, then pitch) before writing the angles.
- **Docs:** [Key art](../tools/blender/key-art.md).
