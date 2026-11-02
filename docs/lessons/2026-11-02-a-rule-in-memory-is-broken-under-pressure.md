---
areas: [process, tools]
---
# A rule that lives only in an agent's memory is broken under pressure

2026-11-02

- **Saw:** the maintainer: "we should be executing Issues from oldest to newest at all times -- I see you just made the
  outline for gameplay and immediately started progress. It seems this isn't enforced anywhere right?" A brand-new
  request (the outline shader, Deadnight #523) got an agent at once while older issues waited.
- **Cause:** "oldest first" was a rule in the coordinator's memory (a note about landing the pull request queue first).
  A fresh, interesting request is exactly when attention goes to the newest thing, and a memory note does not refuse
  anything. Nothing in the tools did either: `S-in-progress` was a label anyone could set, and an agent could be started
  with any prompt.
- **Fix:** the order is computed by a tool and checked by a hook. `gds issue start` allows only the 5 oldest ready
  issues (`P-critical` first), sets the label, assigns and records the start; the Agent hook refuses a task agent whose
  prompt does not name a started issue (or an open pull request it continues); setting `S-in-progress` or `P-critical`
  by hand is refused. A pull request is in progress by existing, so it needs no label and the issues it closes leave the
  line. When a rule keeps being broken under pressure, do not write it down again: put it in a tool and a hook.
- **Docs:** [Starting work](../starting-work.md), [Hooks: issue order](../hooks.md#issues).
