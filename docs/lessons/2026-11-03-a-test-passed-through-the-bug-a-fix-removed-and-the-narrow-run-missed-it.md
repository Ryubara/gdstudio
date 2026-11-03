---
areas: [gameplay, tests]
---
# A test passed through the bug a fix removed, and a narrow test run missed it

2026-11-03

- **Saw:** the fix for a dead tearing the boards of a window it was not at (Deadnight #810, #817) passed the zombie
  suites and went up; CI then failed two more: the second map's "the dead come in through every window" (four of twelve
  windows never torn) and the flare lure test. A third, a seeded solo-bot night, also moved.
- **Cause:** the window test put the person in the hall, so the dead of three windows on one wall took the one gap that
  was shortest to the hall; it had passed for months because a dead held at its own window's wall-wide line tore that
  window's boards from beside another. The lure test dropped a dead on open ground by hand and left its breach set,
  which the old line cleared by position. The solo-bot night buys its first weapon in 240 s only on some seeds (6 of 7
  before the fix, 5 of 7 after). I had run `tests/zombies` and three night suites, not the suites that use the same
  sim on the whole map.
- **Fix:** the window test puts the person behind each window in turn; the lure test clears the breach as the shared
  `drop_zombie` does; the bot night takes a seed that passes both ways. A window the walking mesh did not join
  (`upper_b1`, #824) showed up at once. Before a pull request that changes how a sim picks a target or a gate, run every
  suite that builds a night (`tests/night`, `tests/world`, `tests/zombies`), not only the ones named after the code.
- **Docs:** Deadnight `docs/research/zombies.md`, "A dead tearing the boards of a window it was not at". Check: a test
  that sets a dead down by hand sets all of its state (`gate_id` too), and a test that says "every X" stands the person
  where each X is the way in, not where one X is the shortest.
