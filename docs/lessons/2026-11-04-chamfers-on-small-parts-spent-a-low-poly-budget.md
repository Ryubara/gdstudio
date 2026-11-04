---
areas: [blender]
---
# Chamfers on small parts spent a low-poly budget, and a pitched skid went under the ground

2026-11-04

- **Saw:** the first build of the helicopter (Deadnight #1057, 1,500 tris) stopped at `1768 tris over the budget`.
  With that fixed it stopped at `the skids' bottom is at -0.0106`.
- **Cause:** the builder's `box` chamfers by default, and a chamfered box costs 44 tris against 12 for a plain one, so
  the rails, tubes and hoist cost more than the hull they hang from: the whole lofted hull is about 370. The tip of the
  skid is a box pitched about its centre, and its lower corner drops by half its length times the sine of the pitch
  plus half its thickness times the cosine.
- **Fix:** chamfer only what is big and seen; parts under about 0.2 m on an asset seen from afar are plain boxes
  (1,768 to 1,288 tris). Lift a pitched part by that sum. Both faults
  were cheap because the build itself fails on the budget and on the lowest vertex: keep those two checks in any build
  script, before the export.
- **Docs:** Deadnight `tools/blender/build_helicopter.py` and the chamfer rule in `docs/design/style.md#bevels`.
