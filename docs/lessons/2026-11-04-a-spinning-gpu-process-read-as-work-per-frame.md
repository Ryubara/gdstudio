---
areas: [web, ci, tests]
---
# A software renderer's CPU seconds were read as the work of a frame

2026-11-04

- **Saw:** the idle menu in SwiftShader used 205 ms of GPU-process CPU per frame, so I wrote down "205 CPU-ms over the
  runner's cores explains CI's 100 ms frames". Pinned to 2 cores the same page took 30 ms a frame and 217 ms of CPU.
- **Cause:** SwiftShader's worker threads spin while they wait, so the CPU seconds (`SystemInfo.getProcessInfo`) do not
  measure work and do not scale with cores. Two builds with equal CPU seconds ask the same of the CPU; that is all it shows.
- **Fix:** count the WebGL calls per frame (they do not move with the machine) and compare builds in turns; test a slower
  machine by pinning the run to fewer cores, not by dividing CPU seconds. The artifact path and the stats key were also
  guessed (`smoke/result.json`, `mean_ms`) and caught by reading one artifact before collecting 150.
- **Docs:** [web export](../engines/godot/web-export.md) (row "A frame time on a software renderer, compared").
