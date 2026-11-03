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
- **Docs:** this lesson.
