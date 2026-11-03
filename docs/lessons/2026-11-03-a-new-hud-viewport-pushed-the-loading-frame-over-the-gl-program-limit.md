---
areas: [web, godot-ui, tests]
---
# A new HUD viewport made one loading frame link 16 GL programs and failed the web smoke

2026-11-03

- **Saw:** the `web` check of Deadnight #713 failed: `a frame of the loading screen linked 16 GL programs (at most 12)`.
  The godot shards and every unit test were green; only the browser run counts programs per frame.
- **Cause:** the weapon silhouettes (#682) are `SubViewport`s with a flat unshaded material. The warm-up pauses every
  viewport of its own (`_pause_viewports`) and resumed them all in one call, so the HUD portrait's Soldier programs and
  the silhouettes' own met in one frame.
- **Fix:** resume the paused viewports one per frame (`NightWarmup._resume_viewports`). Locally, a web export and
  `smoke.py` under `gds quiet` went from 16 to 12 programs in the busiest frame (the limit is 12).
- **Docs:** Deadnight `docs/research/first-use-hitches.md` (the guard). A HUD part that draws in a viewport of its own
  needs `smoke.py` run before the pull request, not only the unit tests.
