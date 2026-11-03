---
areas: [web, godot, tests]
---
# A 25 % cut in draw calls did not move a CPU-throttled web frame

2026-11-03

- **Saw:** Folding a lot's still props and boxes into per-cell meshes cut draw calls 628 to 488 (3D view 441 to 302)
  and objects 1 098 to 946, and the CPU x4 median frame stayed where it was (46.8 ms before, 48.2 ms after, 10 minutes,
  shuffled 20 s blocks in one page). Earlier, hiding the whole lot (draw calls 834 to 240) moved the median 93 to 62 ms,
  so the cost is real but a quarter of the calls is not a quarter of it.
- **Cause:** The batch was built from the issue's premise (draw calls are what a phone's processor pays for) before
  checking what share of the frame they are. Script and physics time (`process_ms` 47, `physics_ms` 21 at x4) is most
  of the frame; render CPU is 9 to 10 ms of it. A batch also draws whole cells, so triangles rose (118 000 to 131 000).
- **Fix:** Measure the lever before building it: an ablation that removes the thing outright bounds the best case, and
  the frame split (`process_ms`, `physics_ms`, `render_cpu_ms`) says where the rest is. Two probe traps cost reruns: a
  fixed order of blocks falls on the night's wave beat the same way each round (the arms then saw different crowds, so
  `phone_frames.py --arms` shuffles each round and reports `alive` per arm), and Chrome's CPU throttle applied during the
  page load leaves no minutes to measure (it is set after the load now). `gds quiet` stops a command at 900 s, so a probe
  longer than that must be split.
- **Docs:** Deadnight `docs/research/phone-frames.md` (the batching section), `docs/godot/web-phone-frames.md`.
