---
areas: [godot, godot-ui]
---
# A texture loaded inside `_draw` came out as white squares

2026-11-04

- **Saw:** a contact sheet of 55 icons drew 55 white squares from the 128 px atlas, with no error, while the 64 px
  atlas drew well through the same helper.
- **Cause:** the helper did `return load(path)`. `_draw` records commands with the texture's RID and keeps no
  reference, and the resource cache holds weakly, so the texture was freed when `_draw` returned and the commands drew
  a blank. The 64 px atlas only lived because a cached `AtlasTexture` happened to hold it.
- **Fix:** whatever hands out a texture for drawing holds it (Deadnight `LevelIcons._atlases`, cleared by `release()`
  at the end of a test run). The test takes the instance id, lets a frame pass, and asserts `is_instance_id_valid`.
  Look at the capture: a white square raises nothing, and the suite passed.
- **Docs:** [Canvas draw calls](../godot/canvas-draw-calls.md#icons-from-one-atlas).
