---
areas: [godot, gameplay]
---
# A look change rebuilt the body, and the pool that was meant to avoid it cost a millisecond a reuse

2026-11-04

- **Saw:** a blast that crippled 20 zombies cost one frame of 44 to 59 ms (steady 1.2 ms) in Deadnight (#932, from the
  #907 performance review). Spawns and kills used a pool of parked bodies; only a change of look (walker to crawler)
  went around it.
- **Cause:** `ZombieHorde.apply_snapshot` called `ZombieView.dress` on a look change (free the model, instance the .glb,
  build a tree). After routing it through the pool the call was still 24 ms: `_scene_for` did `load(path)` before looking
  for a parked view (1 ms each), and `park()`/`_restart()` switched `tree.active` off and on, which drops the resolved
  tracks (the next advance of 20 trees: 2 ms).
- **Fix:** take a parked view of the new look (no scene lookup unless one must be made), keep a parked tree active and
  advance it once when it is made, keep 20 parked crawlers, prewarm them. A bench that cripples 20 and reads the worst
  frame, a test that counts the views made in the tick (zero) and the place, gait and clip kept.
- **Check:** every path that changes a zombie's body goes through the pool, and a cost measured once ("reuse 2 us")
  is measured again on the path the game takes (a pool reuse inside a real horde, not a bare view).
- **Where:** [Crowds](../godot/crowds.md#a-pooled-body-costs-1-ms-to-take-if-the-pool-still-looks-the-scene-up).
