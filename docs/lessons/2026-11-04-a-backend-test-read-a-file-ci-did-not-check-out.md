---
areas: [backend, ci, tests]
---
# A backend test read the game's GDScript and the backend job did not check it out

2026-11-04

- **Saw:** Deadnight's #1097 (the profile slot) was green on the machine (124 tests) and red in CI: the `backend`
  job failed on `ENOENT ... game/gameplay/progression/level_curve.gd`, the test that holds the backend's copy of the
  level curve equal to the game's.
- **Cause:** the test reads files outside `spikes/backend`, and the `backend` job checks out `spikes/backend` only
  (`sparse-checkout`). A worktree has the whole game, so the local run could not show it. The job is also started by
  `ci_scope.py` only when the backend changed, so a change to the curve alone would not have run the parity test.
- **Fix:** the job checks out `game/gameplay/progression` too, and `ci_scope.py` starts the `backend` job when those
  scripts change (with a self-test line). Check for next time: a test that opens a path outside its own package names
  that path in the job's checkout and in the job's scope rule, in the same pull request, and the pull request's first
  push is watched to green before the report says done.
- **Docs:** [Lessons](index.md): no page covers it yet; this file is the record.
