# A MultiplayerSynchronizer with ON_CHANGE properties never emits `synchronized`

2026-11-01

- **Saw:** values replicated (the property changed on the client) but a handler connected to
  `MultiplayerSynchronizer.synchronized` never ran, so prediction and reconciliation never started.
- **Cause:** properties in `REPLICATION_MODE_ON_CHANGE` arrive as a *delta* sync, which emits `delta_synchronized`;
  `synchronized` is only emitted for full syncs (`ALWAYS`, and the spawn state).
- **Fix:** connect both signals. A spawn packet can also carry a stale value, so take the first real update as the
  starting point instead of the spawn value.
- **Docs:** Deadnight `docs/research/networking-comparison.md`; belongs on a kit page `docs/godot/multiplayer.md`.
