---
areas: [net, godot]
---
# A Godot server bound a port another program already held

2026-11-01

- **Saw:** a client printed "Invalid ID received from server" while the server logged nothing and showed no peers.
- **Cause:** port 9080 was held by another WebSocket server (the Godot editor MCP bridge). Windows let the game server
  bind the same port too, so connections went to the other listener.
- **Fix:** pick another port (the spike uses 8910) and check before choosing: `netstat -ano | grep :<port>`.
- **Docs:** [Multiplayer](../godot/multiplayer.md).
