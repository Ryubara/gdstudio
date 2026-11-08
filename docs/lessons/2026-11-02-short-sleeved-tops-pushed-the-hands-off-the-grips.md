---
areas: [blender, tests]
---
# Short-sleeved tops pushed the hands off every weapon grip

2026-11-02

- **Saw:** checking the hand grips on the female Soldier (Deadnight #678), every contact of every weapon was 15-20 mm
  off for the Carhop look. I first blamed my test (it changed the look on a menu soldier mid-test), because a male
  preset failed the same way; the Greaser passed.
- **Cause:** what the passing and failing presets differed in was the top, not the body or the test: the build pushes
  every `skin` face of the short-sleeved tops 25 mm inward so a bare arm hugs the limb, and the hands are `skin` too.
  The grip tests (#507) only ever dressed the default look (a jacket), so no test held a weapon in a shirt, a rolled
  sleeve or a tank top.
- **Fix:** no push or cuff pull moves a vertex whose main bone is a finger's, the way the grip test picks a hand's
  vertices (`HAND_BONES`, `hand_vertices` in Deadnight `tools/blender/build_soldier_parts.py`; sparing only the hand's
  faces still moved its border vertices). `test_menu_grips.gd` holds every weapon in every top, for him and her (it
  failed first on exactly the three short-sleeved tops, 47 contacts each). When a failure moves with the preset, diff
  the presets part by part before suspecting the test.
- **Docs:** [Character variants](../tools/blender/variants.md#a-second-body-on-the-same-parts).
