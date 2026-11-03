---
areas: [gameplay, tests]
---
# A "the gate must fail" test with 20 nights stopped failing after a weapon change

2026-11-03

- **Saw:** `test_the_same_climb_is_a_wall_when_the_re_cut_and_the_tonic_do_nothing` failed in CI on the double-barrel
  pull request (Deadnight #684): the inert-upgrade batch had no misses, so the gate "passed" a game it should fail.
- **Cause:** the test ran 20 nights a cell and sat on the edge of the ranges (on `main` it missed by one round and one
  point of stampede deaths). A weapon change moved the 20 seeded nights just inside. With 60 nights the same inert
  game still missed two ranges; the 20 had only ever been a lucky margin.
- **Fix:** 40 nights (two ranges missed, a stampede killing 46%), with the reason in the test's comment.
- **Check next time:** after a weapon, price or round change, run `tests/rules/test_balance_targets.gd` as well as
  the weapons folder; a test that expects a failure should have a margin of several misses, not one.
