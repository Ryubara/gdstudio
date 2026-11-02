---
areas: [ci, process]
---
# Every push restarted CI, and the merge queue backed up behind the runners

2026-11-02

- **Saw:** 21 open PRs, 20 jobs running (the concurrency limit) and 33 queued; the maintainer: "We have PRs that our
  backing us up.. why aren't these merged over yet?" (Deadnight #447).
- **Cause:** agents were told to merge `main` into open PRs although the ruleset does not require up-to-date
  branches; each push cancelled and restarted that PR's 15-minute game and web run and started about ten workflows.
  A known web flake failed several PRs, and its fix (#431) was not at the front.
- **Fix:** push only what a merge needs (the PR is DIRTY, or `main` broke one of its checks); merge `main` locally for
  tests; watch `gh run list --status queued` and the open-PR count each cycle; when the queue grows, stop new PRs and
  land the oldest; a flake's fix goes first. Deadnight #451 cut the jobs per push.
- **Docs:** [What the maintainer caught](../research/maintainer-corrections.md).
