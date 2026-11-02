---
areas: [ci, process]
---
# A pull request ran CI with its branch's old time limit

2026-11-02

- **Saw:** after Deadnight #501 raised the `godot` job's `timeout-minutes` from 20 to 30 on main, fresh runs of #507
  and #525 (closed and reopened after #501 merged) were still cancelled with "The job has exceeded the maximum
  execution time of 20m0s", though their `refs/pull/N/merge` commits had 30.
- **Cause:** the runs took the job limit from the pull request branch's own `ci.yml`, which predated #501; a rerun or a
  close and reopen does not change the branch.
- **Fix:** merge main into each branch whose head lacks the workflow change (`git merge-base --is-ancestor <change>
  <head>`) and push once; that is a reason to push, like a conflict.
- **Docs:** [Agents: the loop](../agents.md#the-loop).
