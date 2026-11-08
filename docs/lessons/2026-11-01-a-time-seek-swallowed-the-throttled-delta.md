---
areas: [blender, godot]
---
# A time seek swallowed the throttled animation delta

2026-11-01

- **Saw:** a zombie's tear clip stood at 0.0 s after `tree.advance(0.5)` that followed a seek to 0, so the yank came late.
- **Cause:** `AnimationNodeTimeSeek` applies its request on the next `advance` and that advance does not move on by its
  delta; a manually advanced tree (the crowd throttle) loses all the time it had saved up.
- **Fix:** call `tree.advance(0.0)` right after setting `seek_request`, then advance the saved time as usual.
- **Docs:** [Rig sharing](../engines/godot/rig-sharing.md#found-later).
