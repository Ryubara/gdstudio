---
areas: [process]
---
# An agent that ended its turn on a next step stalled for hours

2026-11-02

- **Saw:** two task agents (deadnight #226 bots, #410 two-weapon carry) sat idle for 2 and 3 hours with no pull
  request. `ListAgents` still showed both as `running`; no file in their worktrees or scratch folders had changed for
  an hour. Their last words were "Now the gap mode run and look at frames of both." and "Now the autopilot."
- **Cause:** each ended its turn with a sentence announcing the next step instead of a tool call. A background agent
  whose turn ends is finished until someone messages it, so the announced step never ran. The coordinator only watched
  pull request states, which do not change while an agent is stuck before its pull request.
- **Fix:** the engineer and artist definitions now say: never end a turn by announcing the next step; do it in the same
  turn, or start a background command that notifies you. The coordinator, on each PR-monitor expiry, checks the newest
  file time in each running agent's worktree and scratch folder; an hour with no change means a stall. A stalled agent
  with a large context is retired and a fresh one started from its `STATUS.md` (waking it re-writes its whole cache).
- **Docs:** [Agents](../agents.md).
