---
areas: [net, godot, tests]
---
# A room with bots was blamed on its frame, and the cost was a question asked twice for every body

2026-11-05

- **Saw:** a room with one bot cost 1.28 times a room without (p95), and the issue read it as "the host builds the
  frame on every step". Taking the frame off the bots' steps looked like the fix, and would have changed what the bots
  hear.
- **Cause:** nobody had timed the pieces. Probes in the frame and in the bots (`PerfProbe`, 0.01 ms each when off)
  showed `NightServer.use_target` (the card each body shows) was 1.9 ms of the 3.0 ms frame at 15 bodies, and that
  `_act` asks the same question for every body on every tick too (2.4 ms): 30 asks a step, nearly all answering `{}`
  for a body in the open, each walking every door, breach, spot and post (arrays and node reads each time).
- **Fix:** a flat bound first (`UseSites`: every point an offer can come from, with its reach); a body farther than all
  of them is offered nothing, so the answer is `{}` without the walk. It is exact, so the bots decide the same: a test
  compares both answers on a grid over both maps (and fails when a reach is halved), and the bench prints one hash of
  every command every bot sent, equal with the bound on and off (`--sites=0|1`, same build, same container).
  Server step with 7 bots: 14.6 to 10.6 ms mean locally; 3 rooms with a bot each 15.5 to 12.1 ms on Railway.
- **Check for next time:** put a probe on each piece before choosing which one to cut; a cost that grows with bodies
  and a question that is asked once per body per tick is the first thing to count. A fix that must not change
  behaviour carries a hash of the behaviour, run with the fix on and off in one process.
- **Docs:** [crowd budget, bots in a room](https://github.com/Ryubara/deadnight/blob/main/docs/research/crowd-budget.md).
