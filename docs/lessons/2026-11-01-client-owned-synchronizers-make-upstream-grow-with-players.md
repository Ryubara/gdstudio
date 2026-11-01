# Per-client upstream grew with the player count on Godot's high-level multiplayer

2026-11-01

- **Saw:** 2.2, 4.6 and 8.6 KB/s upstream per client for 2, 4 and 8 players, same game.
- **Cause:** a `MultiplayerSynchronizer` owned by a client sends its state once per other peer (the server only
  relays), so upstream is O(players) per client and O(players squared) for the server. It is client authority, not
  the API: with server-owned synchronizers and input-only RPCs, upstream stayed 0.78 KB/s at 2, 4 and 8.
- **Fix:** own player state on the server, send inputs by RPC, reconcile on the client.
- **Docs:** Deadnight `docs/research/networking-comparison.md`.
