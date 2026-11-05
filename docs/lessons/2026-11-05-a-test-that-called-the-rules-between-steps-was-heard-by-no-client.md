---
areas: [net, tests]
---
# A test that called the rules between two steps was heard by the server and by no client

2026-11-05

- **Saw:** Deadnight #1074's first online test killed the dead with `RulesFixture.kill(rules, ...)` on a real game
  server with real clients. The server's challenge tracker counted every kill, but the clients' witness (a count made
  from what a client heard) saw no `round_started`, `zombie_removed` or `round_ended`: `rounds_started` and `kills` on
  the client state stayed 0 while the server was in round 2.
- **Cause:** `NightServer.step` starts a fresh outbox each tick; an `apply` made between two steps emits to the rules'
  listeners (the tallies hear it) and appends to the outbox of the step before, which was already sent.
- **Fix:** the test's own action goes through one helper, `events = rules.apply(action); room._collect(events)`
  (`NightHost._collect`), and the test waits until the client has heard the event it compares against.
  Check for next time: an online test that compares a server number with what a client heard must send the events it
  makes itself, or the client's side is empty and the comparison passes or fails for nothing.
- **Docs:** [Multiplayer](../godot/multiplayer.md#events-reach-a-client-only-through-its-command-loop).
