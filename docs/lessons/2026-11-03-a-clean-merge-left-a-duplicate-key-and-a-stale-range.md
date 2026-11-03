---
areas: [gameplay, tests]
---
# A clean git merge left a duplicate dictionary key, and a pull request carried a stale gate range

2026-11-03

- **Saw:** after `gds merge-main` on the dual pistols pull request (Deadnight #814), the one reported conflict was
  resolved, yet the test run printed `Key "dual_pistols" was already used in this dictionary`: main had added the pair's
  real shot sound, and my branch's placeholder entry (a different hunk) merged in silently beside it. Earlier, CI had
  failed on the old strong-solo range of 12 to 18 because I had run the gate only at the weight I had tuned.
- **Cause:** git merges hunks, not meaning: two additions to one `const` dictionary in different places are both kept.
  A test run before a fresh `--import` also reports unrelated parse errors for classes main added.
- **Fix:** took main's sound mapping, deleted my placeholder, renamed the pair's reload motion events to the names main's
  mapping uses, and re-ran `test_balance_targets.gd` and the dual-pistol suites after a `--headless --import`.
- **Check next time:** after every merge of main, run `git diff origin/main -- <file>` for each file the branch shares
  with a merged pull request and delete the branch's own placeholders; run `--import` once, then the suites that touch
  those files, before the push; run the balance gate again when the maintainer changes a range.
- **Also:** a table on a research page is a claim; test it before you copy it (the models page gave the pair a
  `size_factor` of 1.5, and the size rule in `test_weapon_hold.gd` held only at 1.75).
