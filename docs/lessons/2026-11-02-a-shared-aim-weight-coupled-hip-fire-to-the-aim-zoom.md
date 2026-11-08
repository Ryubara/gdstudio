---
areas: [camera, tests]
---
# A shared aim weight coupled hip fire to the aim zoom

2026-11-02

- **Saw:** in the Discord Activity, aim, shoot, let go of aim: the zoom held a moment longer. The maintainer decided that
  hip fire loses its zoom entirely and the zoom belongs to aiming alone.
  (Deadnight #464.)
- **Cause:** one output, the aim weight, drove the camera, the body and the hands for two inputs (the aim button and
  the trigger), so every hip-fire tweak changed the aim too. The earlier fix (#433) was proved in tests but not in
  the build the maintainer plays: the web deploy lagged the merge and nobody recorded which commit was live.
- **Fix:** the camera reads the aim button only; hip fire turns the body and raises the hands without zoom
  (Deadnight #473). A PR for a reported problem names the live build's commit (Railway deployment
  `meta.cliMessage` is `main <sha7>`) and runs the browser probe (`tools/web_smoke/hip_fire.py`) against the live URL.
- **Check:** one camera input per behaviour the maintainer names; test every release transition. A GdUnit `_ticks()`
  helper that ends in `await process_frame` spans several physics steps under load: bound motion per physics tick.
- **Docs:** [Releasing aim after a shot kept the hip-fire zoom](2026-11-02-aim-release-kept-the-hip-fire-zoom.md),
  [What the maintainer caught](../research/maintainer-corrections.md).
