---
areas: [net, tests]
---
# A room test asked for the back rooms in its ticket and was given the lot

2026-11-05

- **Saw:** a test built the ticket's settings with `map = "small_indoor"` and the room's `rules.settings.map` read
  `drive_in`; the night counted for the wrong map and nothing said why.
- **Cause:** the map a ticket names is kept only when the host's level opens it (`MapRegistry.fit_host`, "the host's
  level decides"); `TicketMaker.make(..., rules, null)` names no host level, and the back rooms open at level 10.
- **Fix:** pass a host level that opens the map (`TicketMaker.make(secret, server, match, user, name, 60, settings,
  12, seat)`) and assert `room.server.rules.settings.map` before counting anything on it.
- **Docs:** [Multiplayer](../engines/godot/multiplayer.md#a-room-test-that-needs-a-map-or-a-fast-round).
