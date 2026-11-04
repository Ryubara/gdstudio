---
areas: [tests, gameplay]
---
# A stand-in walker's stall count blamed the dead for stalls of its own

2026-11-03

- **Saw:** a stand-in person running laps in a bot night showed 170 to 480 s of "stalled" time in four six-minute nights
  with the dead on, and none with them off; it looked like the dead held the walker for minutes (Deadnight #914).
- **Cause:** the counter runs while the walker has a goal and does not move. Part of it was time lying downed (the dead
  now hurt a runner), and most of the rest was one night in which the walker, straight-lining along the navigation path,
  stood wedged on a car's corner for four minutes with no zombie within 3 m: a limit of the stand-in, which the dead
  only moved to a place where it showed.
- **Fix:** the count is cleared while the player is downed, `--stalls` prints where the walker stood, how far the
  nearest zombie was and whether it was downed at each stall, and the report is judged on downs, blows, damage and the
  seconds held by a zombie (`pinned`), not on the stall count. Read what a counter counts, and where, before it is
  evidence about the change under test.
- **Docs:** Deadnight `tests/captures/dead_walk.gd`, `docs/research/dead-contact.md`.
