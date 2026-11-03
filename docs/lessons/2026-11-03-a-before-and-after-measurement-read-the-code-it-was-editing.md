---
areas: [tests, process]
---
# A before-and-after measurement ran on the code that was being edited under it

2026-11-03

- **Saw:** the "before" runs of the swing measurement (Deadnight #764) gave different numbers for the same seed and
  for the same ray: the lot, where the ray is never asked, differed between the two arms.
- **Cause:** the arms were started in batches while the fix was being written in the same worktree. A run that
  started after the edit got the fixed server as its default, and the "old ray" arm had no switch of its own, so it
  measured the new code.
- **Fix:** the capture sets the ray itself in both arms (`--ray=body` or `--ray=walls`), so the code under test no
  longer decides what is measured; the half-started batch was killed by PID and rerun after the merge with main, and
  the lot's two arms now match exactly, which is the control that shows the arms are the only difference.
- **Docs:** [Test speed and measuring](../godot/test-speed.md). Check: a comparison of two behaviours names both in
  its arguments, and carries a control whose two arms must come out equal.
