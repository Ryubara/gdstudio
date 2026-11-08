---
areas: [process, ci]
---
# New pull requests opened while older ones stalled

2026-11-02

- **Saw:** the maintainer pointed out that new PRs kept opening while older ones stayed unmerged (Deadnight #402,
  #432, #449, #455), and later that #402 had sat for four hours.
- **Cause:** the coordinator reported new PRs (#465, kit #91) while five older ones sat DIRTY or failing. The old ones
  were being worked on (local merges under test) but nothing showed it: from GitHub a PR in work looks abandoned. #402
  failed CI three times as `main` moved under it (each re-merge restarted about 40 minutes of CI), then failed only a
  known flake, and its owner had been told never to rerun.
- **Fix:** the queue view is the PR list, not the agents' notes: report from the oldest PR down (state, owner, what it
  waits on, when it pushes), open no new PR while an older one has no live owner, and rerun a known flake at once
  (`gh run rerun <id> --failed`) with an issue for the flake (#487).
- **Docs:** [What the maintainer caught](../studio/maintainer-corrections.md).
