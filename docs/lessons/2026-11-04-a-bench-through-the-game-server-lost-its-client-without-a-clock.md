---
areas: [net, tests]
---
# A bench run through the `GameServer` lost its client in seconds: the server had no game clock

2026-11-04

- **Saw:** Deadnight #1059's horde bench (`--fixed-fps 60`, a ticketed autopilot client on a `GameServer`) lost its only
  client about ten seconds in: the room was freed under the loop (`previously freed` errors) and the run never ended.
- **Cause:** the page on running faster than real time names `NightHost.clock` and `WebSocketLink.clock`, but a
  `GameServer` forwarded no clock to its rooms and timed its hellos and refusals by the machine's, so the connection
  rules saw hundreds of commands a wall-clock second and hung up on the peer.
- **Fix:** `GameServer.clock` (the game's frames over the tick rate), passed to every room it opens, and `link.clock`
  on the client; the bench then ran its minutes. Set all three whenever a run goes faster than real time.
- **Docs:** [Multiplayer](../godot/multiplayer.md#a-room-over-a-real-socket-faster-than-real-time-deadnight-230).
