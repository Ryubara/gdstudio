---
areas: [gameplay, tests]
---
# A list of stats that need a crowd went stale when another pull request added stats

2026-11-05

- **Saw:** Deadnight #1168 (poster sets) passed its own tests, and after merging main (#1174 added 19 challenges and
  the stats `nights:together`, `rounds:whole_crew`, `boards:shared`) a set could list a stat only a crowd can move: the
  set check knew only `revives`. Its test also pinned "21 feats", a number the merge changed.
- **Cause:** "needs a crowd" was a second list (`PosterSets.TOGETHER_STATS`) kept in the consumer, away from the stat
  list another pull request extends, and nothing failed when a stat was added to one and not the other.
- **Fix:** the classification lives beside the stats (`ChallengeStats.CROWD`), the check reads it, and a test names the
  four and plays a one-person night that moves none of them. Check for next time: when a rule says "never X", keep the
  list of X next to the thing others add to, and walk the stats a merge brought in against every such rule; do not pin
  a count that another pull request is allowed to change.
- **Docs:** Deadnight `docs/research/calling-cards.md#poster-sets-1073`.
