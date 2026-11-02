---
areas: [net, tools]
---
# The client never saw the kill: events from the server's own tick were dropped

2026-11-01

- **Saw:** points rose, but the target stayed standing and no burst showed after a lobbed shot.
- **Cause:** only the answers to a client's request were sent back; a projectile bursting, a reload finishing or a round
  ending happen inside the server's tick, and nobody forwarded those events.
- **Fix:** send every event list the server produces, for a request or for a tick, to the clients; test a path with no
  request in it (a reload that finishes on its own).
- **Docs:** [Multiplayer](../godot/multiplayer.md); Deadnight `docs/research/weapon-firing.md`.
