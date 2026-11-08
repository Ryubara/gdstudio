---
areas: [blender, godot]
---
# A rebuilt character showed its T-pose for one frame

2026-11-01

- **Saw:** every time a preview rebuilt its model (a colour changed), captures caught the new character with arms out
  for a frame, then it dropped into the idle clip.
- **Cause:** a model instanced from a .glb is in its rest pose until the `AnimationPlayer` and the skeleton have run
  once; `play()` and `advance(0.0)` before the first process do not pose it in time for the first render.
- **Fix:** add the new model hidden, keep the old one on screen, and swap on the next `process_frame`.
- **Docs:** [Rig sharing](../engines/godot/rig-sharing.md).
