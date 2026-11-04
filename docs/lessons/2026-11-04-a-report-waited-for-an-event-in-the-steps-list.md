---
areas: [net, tests]
---
# A round report waited for `round_ended` in a step's list and the round that ended outside the step paid nothing

2026-11-04

- **Saw:** Deadnight #1059's first online test killed the last zombie of a round with a rules action between two
  ticks: the round ended, the clients heard nothing wrong, and the host never made the report to the backend (no post
  after 45 s).
- **Cause:** `NightHost` looked for `round_ended` and `game_over` in the events `server.step` returned. An event made
  by `apply`, or by a call into the rules outside the step, goes to the outbox the host has already taken, so it is
  not in the list.
- **Fix:** the award notes what is owed when the rules signal it (`XpAward.take_due`), and the host asks after each
  step. Anything a host must do because a rules event happened is hooked at the rules signal, never read back from a
  step's list.
- **Docs:** [Multiplayer](../godot/multiplayer.md), the section on acting on a rules event where the rules say it.
