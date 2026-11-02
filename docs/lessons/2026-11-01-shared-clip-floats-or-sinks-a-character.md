---
areas: [tools, blender]
---
# Shared clip floats or sinks a character

2026-11-01

- **Saw:** the zombie's Walk put the Soldier's feet through the floor; the Soldier's Run lifted the zombie.
- **Cause:** bone position tracks are absolute and carry the source's rest offsets (`Body` 0.32 m apart).
- **Fix:** rebase position keys per character at play time (`value - source rest + own rest`) in
  `_post_process_key_value`; the library stays one resource.
- **Docs:** [Rig sharing (Godot)](../godot/rig-sharing.md#what-breaks).
