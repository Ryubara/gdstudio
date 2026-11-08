---
areas: [godot, web]
---
# Pinning a particle system's draw passes printed an engine error in the browser console

2026-11-02

- **Saw:** after the warm-up pinned every `GPUParticles3D` draw pass, the browser probe failed on console errors:
  `Index p_pass = 1 is out of bounds (draw_passes.size() = 1)` at `get_draw_pass_mesh`.
- **Cause:** the code read `draw_pass_1` to `draw_pass_4` unconditionally; a system with one pass errors on the others
  (a headless GdUnit run did not show it, the web build's console did).
- **Fix:** loop `for i in particles.draw_passes` and call `get_draw_pass_mesh(i)`. Treat a console `ERROR` in the
  browser probe as a failure, as the flare probe does.
- **Docs:** [First-use hitches](../engines/godot/first-use-hitches.md#particle-systems-two-programs-of-their-own-and-a-sample-that-expires).
