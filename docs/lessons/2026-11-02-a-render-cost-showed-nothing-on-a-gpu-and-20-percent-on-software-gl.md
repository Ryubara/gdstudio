---
areas: [godot, web, tests]
---
# A render cost showed nothing with a GPU and 20 % on the software renderer

2026-11-02

- **Saw:** an outline of 3 zombies (51 extra draw calls) changed the frame time of a 40-zombie crowd from 2.66 ms to
  2.62 ms in Chrome with a GPU, and from 199 ms to 239 ms in Chromium on SwiftShader.
- **Cause:** a GPU hides draw calls and extra passes behind its own parallelism; the software renderer pays every
  vertex and pixel on the CPU, which is closer to what a weak phone or an integrated chip does with a skinned mesh
  drawn 17 times.
- **Fix:** measure a rendering change in both (`tools/web_smoke/outline_cost.py --gl gpu` and `--gl software`),
  interleave the cells so a slow minute hits every row, and report both; a cost that is zero on the developer's GPU is
  not a measurement of the web build. Draw calls (`RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME`) are the number to read
  first, and an overlay that is `null` while nothing is marked costs nothing.
- **Docs:** [Outline through walls](../engines/godot/outline-through-walls.md#pitfalls).
