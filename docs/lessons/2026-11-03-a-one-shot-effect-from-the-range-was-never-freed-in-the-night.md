---
areas: [godot, gameplay, process]
---
# A one-shot effect written for the range was never freed in the night, and nobody had stated its cost

2026-11-03

- **Saw:** the maintainer asked for the places that would clearly lag the game, said performance has to be weighed at
  all times, and suspected objects that were never cleaned up (Deadnight #906, #907).
  The review found `BlastEffect` never freed: 14 nodes alive 30 s after 5 blasts, each blast keeping 3 alpha-0 draw
  calls and an energy-0 light (a slot in the 8-per-mesh light cap) for the rest of the night, and 7 gib nodes left by
  every blast kill (Deadnight #929). The client decoded the whole crowd five times a tick (#930), and the server built
  its target list twice (#931): about 11.9 ms of a 16.7 ms tick at 98 alive with 3 bots.
- **Cause:** the effect was written as "play and forget" for the grenade range, where a scene lives a minute; a fade to
  alpha 0 was taken for freed. And cost had no owner: the 120-alive desktop ceiling (#453) was set from the server step
  and the client draw with no bots, no HUD and no client script, so the per-tick GDScript of the clients was never in
  the budget, and no pull request said what its per-frame work cost or how it scaled.
- **Fix:** each finding is its own issue (Deadnight #929 to #936, #938). The kit's
  [Performance review](../engines/godot/performance-review.md) page: a pull request that adds per-frame work, a spawn,
  a light,
  a shader or a message states its cost (what runs, how often, what it scales with, the number at the ceiling, what
  frees it); every run-time `.new()` / `instantiate()` has a free or a capped pool and a test that the node count is flat
  after N events; the budget is one tick of the real night with the bots on at the platform ceiling, counts first.
- **Also:** the reviewer stopped its own run with `taskkill /IM` on the Godot program name and may have killed another
  agent's run: on a shared machine, stop a run by its own process id.
