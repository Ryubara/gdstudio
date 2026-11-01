# A NaN position made a blast hit in full

2026-11-01

- **Saw:** a grenade cooked with a NaN hand position blew up for full damage on a zombie next to the player.
- **Cause:** `maxf(NaN - radius, 0.0)` answers 0.0 in Godot 4.7, so a NaN distance became the blast centre; every
  comparison with NaN is false, so `if distance >= radius` guards fall through too.
- **Fix:** refuse non-finite input where it enters (`Vector3.is_finite()`), and make pure functions that take a distance
  answer "no effect" for `not is_finite(distance)` before any `maxf`/`minf`.
- **Docs:** [Multiplayer](../godot/multiplayer.md); Deadnight `docs/research/grenades.md`.
