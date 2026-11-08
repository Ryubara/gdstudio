---
areas: [blender, tests, godot]
---
# A grip measure counted the far level of detail's hand

2026-11-03

- **Saw:** the lever rifle's right middle fingertip floated 6.9 mm off the weapon (the limit is 5 mm) in every pose,
  yet the grip tests passed (Deadnight #716).
- **Cause:** the measure took every skinned mesh with `is_visible_in_tree()`, and the far level of detail is hidden
  by its visibility range (`visibility_range_begin`), not by `visible`, so it counted too; a part's distance is its
  nearest vertex, and the decimated hand's longer fingertip touched. The solver loads the raw model, where no range is
  set yet, so it solved the finger on the far hand as well.
- **Fix:** measure the meshes drawn up close only (Deadnight `HandContact.is_near`: no `visibility_range_begin` and
  no `__far` name) with a test that the measured meshes hold no far mesh; re-curl only the rifle's fingers with the
  solver's `--fingers` (the hold, and the sprint carry built from it, unchanged).
- **Docs:** [Weapons, hand grips](../tools/blender/weapons.md).
