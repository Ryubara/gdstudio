# New pull requests opened while older ones stalled

2026-11-02

- **Saw:** the maintainer: "I see we're opening new PRs but we still have older PRs taht aren't getting knocked out"
  (Deadnight #402, #432, #449, #455); later, "What's going on with this? It's been 4 hours" (#402).
- **Cause:** the coordinator reported new PRs (#465, kit #91) while five older ones sat DIRTY or failing. The old ones
  were being worked on (local merges under test) but nothing showed it: from GitHub a PR in work looks abandoned. #402
  failed CI three times as `main` moved under it (each re-merge restarted about 40 minutes of CI), then failed only a
  known flake, and its owner had been told never to rerun.
- **Fix:** the queue view is the PR list, not the agents' notes: report from the oldest PR down (state, owner, what it
  waits on, when it pushes), open no new PR while an older one has no live owner, and rerun a known flake at once
  (`gh run rerun <id> --failed`) with an issue for the flake (#487).
- **Docs:** [What the maintainer caught](../research/maintainer-corrections.md).
