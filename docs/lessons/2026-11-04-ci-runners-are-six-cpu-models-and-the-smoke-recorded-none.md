---
areas: [ci, web]
---
# A rise in slow CI runs was argued from the build while the runners were six different machines

2026-11-04

- **Saw:** the web smoke's idle menu frame (a still stage, 277 WebGL calls every frame in both builds) was 120 ms or more
  on 10 of 58 runs after a menu change against 22 of 704 before it, with the same median. A local before and after could
  not reproduce it, the first answer ("the runner is slower") was a guess, and the artifact said nothing about the
  machine.
- **Cause:** one `ubuntu-24.04` label is a pool of six CPU models (AMD EPYC 7763, 9V45, 9V74; Intel Xeon 6975P-C, 8573C,
  8370C) and four image versions. The same build's 3 s idle window is 60, 73, 80, 98, 98 and 119 ms on them; the slowest,
  the 8370C, sits on the 120 ms line, so a 1 % step in the build (what the menu change cost) moved its windows across
  it (3 of 12 over, then 8 of 12), and the share of runs over the line follows how many 8370Cs the pool gave that hour.
- **Fix:** run the builds in turns **on the same runners**: a throwaway workflow on a push trigger of the issue's branch
  that downloads the `web-build` artifacts of the commit before and after (`gh api repos/<repo>/actions/artifacts/<id>/zip`),
  a matrix of 20 to 24 jobs, `lscpu` in each. The runner is then the control and the change the only variable. The smoke
  now writes `machine` (CPU model, usable CPUs, load average) into `result.json`. To read 1 200 old runs without 40 GB of
  downloads, read only `smoke/result.json` out of each artifact zip with HTTP range requests (70 KB a run: Deadnight
  `tools/web_smoke/smoke_history.py`). A probe built for the A/B must copy the gate's own steps before its window (the
  smoke reads the probe and takes a screenshot first): without them the older build read 150 to 2 600 ms.
- **Docs:** [web export](../engines/godot/web-export.md) (row "Hosted runners are several CPU models").
