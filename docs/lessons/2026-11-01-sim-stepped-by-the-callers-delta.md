# A "fixed step" simulation was fixed only by convention

2026-11-01

- **Saw:** a simulation deterministic at 1/30 s put zombies inside solid boxes for 52 zombie-ticks when stepped at 1/60
  s; nothing stopped a caller passing its frame delta.
- **Cause:** `tick(delta)` used the caller's delta, while the tuning assumed 1/30 s.
- **Fix:** keep a pending time and run whole fixed steps, ignore a delta that is not a positive number, cap catch-up
  after a stall. Test determinism by hashing every tick on a real navmesh and slicing the same time into 2 and 4 deltas.
- **Docs:** [Zombie crowds](../godot/crowds.md); Deadnight `docs/research/zombies.md`.
