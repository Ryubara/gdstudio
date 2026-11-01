# Coincident bodies were thrown 66 m by a separation push

2026-11-01

- **Saw:** two zombies spawned on one point; a tick later one stood 76 m away, and forty on one point ended up to 2.6 km
  away. The test spread its zombies 0.01 m apart and passed.
- **Cause:** the exact-overlap branch set `d = 0.001` and returned `unit / d * speed`, a 1000-times push; a test that
  offsets bodies never reaches a branch that only runs at distance zero.
- **Fix:** push along a direction made from the two ids (no random draw), at `speed`, and cap the sum of pushes on one
  body. Test the degenerate input directly and assert a per-tick bound on movement, not only the end state.
- **Docs:** [Zombie crowds](../godot/crowds.md).
