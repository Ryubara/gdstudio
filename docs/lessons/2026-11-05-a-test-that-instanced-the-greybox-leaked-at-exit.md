---
areas: [tests, godot]
---
# A unit test that instanced the lot's scene left `leaked at exit` after every test passed

2026-11-05

- **Saw:** Deadnight #1172's data suite read the size of the concession's floor from `drive_in_greybox.tscn`
  (`instantiate()`, read the boxes, `free()`): 11 cases passed and the log ended with `2 RID allocations of type
  'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit` and a list of `Resource still in use` lines (GdUnit4's own
  scripts). CI fails on that line with every test green.
- **Cause:** not isolated; the scene is the lot (CSG, materials, scripts) and a unit test needs one number from it.
- **Fix:** read the scene file's text (`FileAccess.get_file_as_string`, a `RegEx` over the node's `transform` and
  `size`) and compute from that: same assertion, a clean exit. Check for next time: a test that compares a data line
  with a scene reads the `.tscn` text, and every new suite is run alone with its whole log grepped for
  `leaked at exit|still in use`.
- **Docs:** [Test exit leaks](../godot/test-exit-leaks.md#a-test-that-only-needs-a-number-from-a-scene).
