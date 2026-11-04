---
areas: [ci, process]
---
# A delayed rerun of an old commit cancelled the run on the commit that replaced it

2026-11-04

- **Saw:** Deadnight #1127's `godot (4)` failed while its run was going, and `gh run rerun` is refused until a run
  ends, so the coordinator left a background loop to rerun it. Before that run ended, a merge of main was pushed to the
  branch. The loop fired anyway and restarted the run on the old commit, and CI's one run per branch rule cancelled 15
  jobs of the new one. The pull request showed a wall of red for a commit that had not failed.
- **Cause:** the loop was tied to a run id, not to the pull request's head. A push makes an old run's result worthless,
  but nothing stops a rerun of it, and a rerun takes the branch's concurrency slot like any new run.
- **Fix:** cancel the old run, wait for the new run to stop, then `gh run rerun --failed` on it. A delayed rerun checks
  that the run's `head_sha` is still the pull request's head and does nothing if it is not. After a push, stop any such
  loop for that branch.
- **Docs:** Deadnight #1127.
