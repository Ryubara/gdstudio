---
areas: [process, gameplay]
---
# The same system was built in two branches at once, and one had to be rebuilt after the other merged

2026-11-02

- **Saw:** the revive branch (#486) and the bots-revive pull request (#511) each built a revive channel (hold, reach,
  prompt, events). When #511 merged, the merge of main into the revive branch conflicted in eight files and the
  branch's own hold, `revive_hold` and `revive_release` actions and numbers had to be thrown away.
- **Cause:** the revive branch was started from the design alone; nobody looked at open pull requests and recently
  started issues that touch the same subsystem (`NightServer`, `GameRules`, `PlayerHealth`) before building its core.
- **Fix:** before building a core piece of a system, `gh pr list` and search open and in-progress issues for the
  subsystem's words (here "revive"); if another branch builds it, build only the part that sits on top (the bleed-out
  clock, dead players, counts) against its interface, or wait for it to merge. Merge main early and often on a long
  branch so the overlap shows while it is small.
- **Docs:** [Starting work](../starting-work.md).
