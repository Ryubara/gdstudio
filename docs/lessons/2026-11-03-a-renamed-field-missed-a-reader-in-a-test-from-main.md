---
areas: [tests, gameplay]
---
# A field I replaced was still read by a test that landed on main meanwhile

2026-11-03

- **Saw:** CI failed one test, `Invalid access to property or key 'weapons' on a base object of type 'Resource
  (UpgradeTuning)'`, after a branch replaced `UpgradeTuning.weapons` with per-weapon profiles; my local runs were green.
- **Cause:** the reader was a test (and two capture scripts) added by a pull request merged after I last grepped; a
  `grep` for the old field ran before the merge of main, not after.
- **Fix:** after every `gds merge-main`, grep the whole project (tests and captures included) for the removed field
  and run the suites that touch its type; give the old reader a helper that answers the same question
  (`UpgradeTuning.catalogue_weapon_ids()`).
- **Again:** two more readers (`test_night_recut_layer.gd`, `test_recut_layer.gd`) came from a sibling pull request
  that merged within minutes of mine, so no grep on my branch could see them and main went red. Whoever removes or
  renames a field greps `origin/main` again right before turning auto-merge on, and after the merge greps main itself.
- **Again (a removal, 2026-11-05):** Deadnight #1233 removed two actions and their events; its body said none of the four
  names was left, and `godot (4)` failed on `test_hidden_moments.gd`, a test (and a comment) that #1190 had put on
  main after the grep. The grep was of the commit before `gds merge-main`, not of the merged tree. Check for next
  time: the grep named in a pull request body is the one run after the last merge of main, over the whole of `game/`
  and `docs/`, and the body says "after the merge of main" so a reader can tell.
- **Docs:** this lesson.
