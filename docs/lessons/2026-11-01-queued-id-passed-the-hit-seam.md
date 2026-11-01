# A hit on a queued zombie killed it and paid the shooter

2026-11-01

- **Saw:** `take_hit` on an id still waiting for room under the crowd cap returned a kill and added points, for a zombie
  that was not in the world.
- **Cause:** the rules know every requested zombie, the simulation only the admitted ones, and the seam between them
  trusted the rules alone.
- **Fix:** when two owners hold different views of one id, the seam that joins them checks both (here: the simulation
  holds the id) before acting.
- **Docs:** Deadnight `docs/research/zombies.md`.
