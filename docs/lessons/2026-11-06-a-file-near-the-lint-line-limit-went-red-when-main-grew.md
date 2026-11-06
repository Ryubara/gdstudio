---
areas: [gameplay, tests]
---
# A script 18 lines under the lint line limit went red when main added 32 lines to it

2026-11-06

- **Saw:** Deadnight #1359 passed gdformat and gdlint on its branch (`zombie_sim.gd`, 982 of 1000 lines) and was red
  in CI on `gdlint-late`: `Max allowed file lines num (1000) exceeded` at line 1014, so `build-ok` failed too.
- **Cause:** CI lints the merged head (the branch with main merged in). #1361 landed on main after my last merge and added
  32 lines to the same file. The commit and push hooks only see the branch, so no local run could show it. The slip was
  mine: I put about 50 lines of new rules into a script that already stood near 935 lines, so any growth on main
  would break it.
- **Fix:** the route-keeping rules moved into their own class (`ZombieRouteKeep`, 96 lines); `zombie_sim.gd` is 930 after
  merging main. Digests and the booth and dodge tests unchanged.
- **Check next time:** before adding more than a few lines to a script within about 100 lines of the limit (`wc -l`),
  put the new code in a new class first; and run `gds merge-main` and then gdlint on the changed files before the
  final push, so the count is the merged head's.
- **Docs:** Deadnight `docs/research/ci-jobs.md`, "gdlint on the merged head (#1238)".
