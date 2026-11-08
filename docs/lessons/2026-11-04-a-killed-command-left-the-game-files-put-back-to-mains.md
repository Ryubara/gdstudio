---
areas: [tests, process]
---
# A killed command left the game files put back to main's

2026-11-04

- **Saw:** in Deadnight #987, after a run that had put the branch's game files back to main's (to see the new test fail
  first) was killed by its timeout, the worktree held main's reload files and the branch's fix was gone from it.
- **Cause:** the revert, the test run and the restore were one command; the kill came between the first and the last,
  so the restore never ran. Nothing was lost only because the diff had been saved as a patch beforehand.
- **Fix:** save the diff to a patch file first (`git diff origin/main -- <paths> > file.patch`), run the revert, the test
  and the restore as separate commands with the test under its own `timeout`, and check `git status` after any killed
  command. A "failed first" run on main's files can be done in a separate worktree of main with the new test copied in,
  which cannot lose the branch.
- **Docs:** [Hooks](../studio/hooks.md), and [a test run killed by an outer timeout](2026-11-04-a-test-run-killed-by-an-outer-timeout-left-an-empty-log.md).
