---
areas: [tools]
---
# A commit the hook refused looked done behind a grep

2026-11-04

- **Saw:** `git commit ... | grep -E "Failed|rror:"` printed one gdlint line and returned; everything stayed staged and
  `git log` still showed the commit before. The lint was `_work_the_boards has more than 6 return statements`, in a
  function the change never touched.
- **Cause:** pre-commit lints whole files, so a one-word comment edit in `zombie_sim.gd` pulled in a fault that main had
  fixed since the branch began, and the pipe's exit code was `grep`'s, not the commit's.
- **Fix:** run `git log --oneline -1` after a filtered commit, or do not filter it. For a lint in a line you did not
  write, take main first (`gds merge-main`) before changing the code.
- **Docs:** [Hooks](../hooks.md).
