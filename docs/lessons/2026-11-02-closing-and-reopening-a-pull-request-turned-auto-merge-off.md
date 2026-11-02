---
areas: [ci, process]
---
# Closing and reopening a pull request turned its auto-merge off

2026-11-02

- **Saw:** the coordinator closed and reopened Deadnight #507, #514, #519, #520 and #537 to get CI runs under a new
  job time limit (a rerun of a `pull_request` run reuses its old merge commit and workflow). Each came back with
  auto-merge off; they would have sat green and unmerged.
- **Cause:** GitHub disables auto-merge when a pull request is closed, and reopening does not restore it.
- **Fix:** after a close and reopen, run `gh pr merge <N> --auto --squash` again in the same command, except on
  pull requests that are merged by hand; check with `gh pr view <N> --json autoMergeRequest`.
- **Docs:** [Agents: the loop](../agents.md#the-loop).
