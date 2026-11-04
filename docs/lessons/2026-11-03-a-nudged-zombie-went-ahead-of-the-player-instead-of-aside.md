---
areas: [gameplay]
---
# A nudged zombie went ahead of the player instead of aside

2026-11-03

- **Saw:** the first push rule (hold 0.6 s, then the zombie yields at 1 m/s away from the body) took 3.2 s to get past
  one zombie dead ahead and left a block of twelve unmoved after 20 s (Deadnight #914, `tests/captures/dead_variants`).
- **Cause:** "nudge it out of the way" was built as "push it away from me": the zombie went ahead of the player at the
  yield speed and led them along, and in a block each one pushed the next into a jam.
- **Fix:** the yield goes across the player's way (80 percent sideways, to the side the zombie already leans to, by its
  id when it is dead ahead): 1.6 s for one, 5.9 s for the block of twelve, 1.9 s out of a ring of eight. The numbers of
  every variant come from a scenario table (one, two, a crowd, a ring; run and sprint) before a rule is picked.
- **Docs:** [Crowds: a player's body against a crowd](../godot/crowds.md#a-players-body-against-a-crowd-that-is-not-physics-bodies).
