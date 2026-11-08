---
areas: [blender]
---
# A rebuild of the main Soldier file picked up every later clip

2026-11-04

- **Saw:** rebuilding Deadnight's `soldier.glb` after changing a clip wrote 67 clips and a spec of 67 where the file
  ships 35 (#939): the strike, sprint, dual, revive, grenade and aim-move clips came along.
- **Cause:** the same as [the parts file's](2026-11-02-a-parts-rebuild-picked-up-clips-that-ship-in-their-own-files.md):
  `build_soldier.py` without `--clips` exports every action `soldier_clips.py` makes, and the module had grown since
  the file was built. The parts builder had been given a frozen list then; the main build had not.
- **Fix:** `--clips main` builds the file's own set (every kit clip and `MAIN_CLIPS`); the 35 names matched the
  committed file. Before rebuilding any file a clip module feeds, compare its clip list with the committed one.
- **Docs:** [Clips that keep the arms out](../tools/blender/variants.md#clips-that-keep-the-arms-out).
