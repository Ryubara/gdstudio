---
areas: [tests, godot]
---
# A 30-minute soak's memory growth was the soak's own rows

2026-11-03

- **Saw:** `MEMORY_STATIC` rose 181 to 274 MB over a 30-minute night, about 1 MB a minute even in a round with one zombie
  and flat object, node and resource counts (Deadnight #906).
- **Cause:** the harness: a per-frame row `[ms, round, dead]` for 108 000 frames and a sampler row a second kept in the
  game's own process. Meanwhile the skeleton count grew 24 to 65 and stopped, which is a pool filling
  (12 parked bodies a look), not a leak.
- **Fix:** a run option that keeps no per-frame rows (`frames=0`), small sampler rows, and a leak read as nodes, objects
  and resources **at the same number of dead**, round by round, after the pools are full.
- **Docs:** [Performance budgets](../engines/godot/performance-budgets.md#a-leak-is-read-as-a-count-at-the-same-crowd-round-after-round).
