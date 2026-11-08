---
areas: [blender]
---
# An imported character kept its import pose and facing

2026-11-02

- **Saw:** in a scale render (Deadnight #623) a zombie stood 3 m tall, because it was scaled to 1.63 m while lying
  in its Crawl clip. The Soldier faced the camera whatever `rotation_euler.z` the script set.
- **Cause:** Blender 5 plays an action only through a slot: `animation_data.action = idle` alone leaves the
  imported clip (the file's first, Crawl) playing. glTF import also puts each root in `QUATERNION` rotation mode, where
  `rotation_euler` is ignored.
- **Fix:** set `animation_data.action_slot = action.slots[0]` with the action and `frame_set` its first frame before
  measuring. Turn and move an imported root through `matrix_world` (or set `rotation_mode = "XYZ"` first). Then look
  at the render.
- **Docs:** [Modular kits](../tools/blender/modular-kits.md#staging-game-characters-for-scale).
