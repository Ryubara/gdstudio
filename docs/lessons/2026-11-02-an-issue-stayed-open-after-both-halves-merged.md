---
areas: [process, ci]
---
# An issue stayed open after both halves merged, so it looked like unstarted work

2026-11-02

- **Saw:** Deadnight #258 (the prize crane) was assigned as new work; its rules (#271) and its visuals (#274) had
  already merged.
- **Cause:** neither PR carried `Fixes #258`, since each did part, and nobody closed the issue after the last part.
- **Fix:** the agent audited `main` first and filled only the gaps (#398).
- **Check:** before starting an issue, search merged PRs for its number
  (`gh pr list --state merged --search "#N"`); the PR that finishes the last part of a split issue carries
  `Fixes #N`, and the coordinator closes issues whose parts have all merged.
- **Docs:** none; a coordinator rule.
