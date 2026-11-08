---
areas: [net, tests]
---
# A frozen night kept a revive hold alive, because only the running tick stops it

2026-11-04

- **Saw:** after the end-of-night freeze (Deadnight #973) two revive tests failed on the pull request and nowhere else:
  a reviver who goes down stopped nothing, no `revive_stopped "down"`, the channel still read `is_reviving`.
- **Cause:** the reviver going down is the last player going down, so it is the game over. The freeze returns from
  `step` before the per-player `_act`, and `_act` is the only place a downed player's hold is stopped. Anything that
  ends "on the next tick" ends never once a phase stops ticking, and the frozen frame (the one the end board shows)
  went on carrying a revive in progress.
- **Fix:** the first frozen tick ends every hold with `down` and clears the channel's time (`ReviveChannel.end_all`);
  the test also reads the frozen frame (nobody reviving). Not a test change: the game over must still come when
  everyone is down. When a phase freezes the simulation, list what each tick used to end by itself and end it once at
  the freeze.
- **Docs:** [Multiplayer](../engines/godot/multiplayer.md#small-things-that-cost-time).
