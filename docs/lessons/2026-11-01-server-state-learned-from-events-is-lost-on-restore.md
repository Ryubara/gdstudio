# A server made mid-game ignored every zombie already alive

2026-11-01

- **Saw:** a grenade server created after zombies had spawned, or after a snapshot restore, blasted 1 m from a live
  zombie and hit nothing; cooks and grenades in flight were gone after a restore.
- **Cause:** the server mirrored the zombie list from spawn events it had seen, and its own state was in no snapshot.
- **Fix:** ask the owner of a fact (`GameRules.has_zombie`) instead of mirroring it from events, and give the state a
  server alone owns `to_dict`/`from_dict`/bytes with its own version, restored after the rules.
- **Docs:** [Multiplayer](../godot/multiplayer.md); Deadnight `docs/research/grenades.md`.
