---
areas: [tests, gameplay]
---
# A merge with one trivial conflict left a test of the other pull request failing

2026-11-03

- **Saw:** merging main (the bot flare rule, #675) into the bot orders branch (#676) conflicted in one file, `bot_team.gd`
  (two new fields side by side), and the text merge was clean everywhere else. `test_bot_flare` then failed its control
  night ("the person is not raised" was raised).
- **Cause:** #675's tests were written when a bot with nobody to follow still followed; #676 makes the default order
  Roam, so the flare night's bot no longer came to the body the way the test assumed. No line conflicted: the two changes
  met in a behaviour, not in a file.
- **Fix:** the flare night gives the Follow order, as the other suites written before orders do (`give_order`,
  `stand_still`).
- **Check for next time:** after `gds merge-main` on a branch that changes a default of the bot brain, run the suites of
  every bot change that landed meanwhile (`git log origin/main` since the branch point), not only the conflicting file's.
