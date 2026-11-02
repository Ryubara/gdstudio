---
areas: [net, godot]
---
# Godot clients could only measure latency in 33 ms steps

2026-11-01

- **Saw:** local round trips of 34 ms, and "stalls" of 100 to 235 ms against localhost as often as against the hosted
  server, so the clients could not tell a link stall from a frame hiccup.
- **Cause:** `WebSocketPeer` is polled on the 30 Hz physics tick, so every arrival is rounded to a tick and a late frame
  looks like a late packet.
- **Fix:** add a tiny external probe (Python `websockets`) that joins as a silent player, pings every 50 ms and
  timestamps every snapshot with `perf_counter`. Quote the probe for the network and the clients for what the game
  feels, with a local server as the baseline.
- **Docs:** [Multiplayer](../godot/multiplayer.md); Deadnight `docs/research/multiplayer.md` (Measured on Railway).
