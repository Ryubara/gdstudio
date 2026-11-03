---
areas: [web, godot]
---
# A warm-up frame that drew two new shaders linked 15 programs at once

2026-11-02

- **Saw:** Deadnight pull request 648 (hit blood) failed the `web` check: `a frame of the loading screen linked 15 GL
  programs (at most 12)`. Locally the same smoke printed 15 at 5.8 s after Play, in the warm-up's effects replay.
- **Cause:** one chunk of the replay drew the damage numbers, the new splash shader and the new mark shader together.
  A shader's first draw builds four programs at the default specialisation and then the one it is drawn with
  ([first-use hitches](../godot/first-use-hitches.md)), so two new shaders and a label in one frame is the burst.
- **Fix:** each new shader gets frames of its own (the splash alone before the events, the events with the numbers,
  the mark, the blast burst), held still with `set_process(false)`. The busiest loading frame dropped from 15 to 12,
  which main already had. The smoke now prints its three busiest loading frames (`busiest_frames`) so the next one is
  found by reading the result, not by guessing.
- **Check for next time:** a new effect with a new shader goes into the warm-up in its own chunk, and the web smoke
  (`tools/web_smoke/smoke.py` through `gds quiet`) is run locally before the push; read `loading.busiest_frames`.
- **Docs:** [First-use hitches](../godot/first-use-hitches.md).
