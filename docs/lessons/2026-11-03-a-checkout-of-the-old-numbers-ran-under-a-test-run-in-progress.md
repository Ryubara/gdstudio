---
areas: [general, tests]
---
# Putting the old numbers back for a before capture ran under a test run in progress

2026-11-03

- **Saw:** a "before" capture needed the old weapon files, so they were checked out (and the patch re-applied
  after) in the worktree while a full `tests/night` run was going in the background from the same worktree.
- **Cause:** one worktree, two readers: the test process loads the weapon definitions when a suite starts, so a
  suite that began during the swap could read the old numbers and its result is not the branch's.
- **Fix:** nothing was committed from it; the run was repeated. Take the before capture from a separate detached
  checkout of `origin/main` (or of the commit before the change), never by swapping files under a run, and start
  long test runs only after the captures that need the old files.
- **Docs:** this lesson.
