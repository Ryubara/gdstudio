---
areas: [gameplay, general]
---
# A "baseline" soak was started after the change and measured the new code

2026-11-03

- **Saw:** the logs labelled `base` for seeds 4 and 5 showed all three links bought and no glut, identical to the
  `new` runs, while seeds 1 to 3 (started before the edit) showed the bug. A baseline that passes where the bug was
  reported is the sign.
- **Cause:** the seeds 4 and 5 baseline was launched in the background after the worktree already held the change, and
  a script label is not a checkout.
- **Fix:** the two logs were deleted and the report states a baseline for seeds 1 to 3 only. Measure a baseline before the
  first edit, or from a separate detached checkout of `origin/main`, and name the commit in the log file.
- **Docs:** none beyond this lesson.
