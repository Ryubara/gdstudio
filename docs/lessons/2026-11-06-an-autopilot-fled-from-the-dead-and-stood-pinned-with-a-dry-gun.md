---
areas: [gameplay, tests]
---
# The nightly's autopilot stood for minutes pinned by the dead with a dry shotgun and its points unspent

2026-11-06

- **Saw:** a 30 minute night (`autopilot_run.gd`, seeds 2, 3 and 8) stopped at round 10 to 16 for 100 to 640 s at a
  time: the autopilot (a person who cannot die) at one spot with the shotgun at 0 and 0, 465 to 2 325 points, and
  one to twenty-six dead in attack at 0.3 to 1.9 m, the bots 8 to 50 m away with no target. The issue guessed at the
  shop (`_refill_gun`) and the blade rule; the shop was fine.
- **Cause:** two faults of the same rule. The flight from the nearest zombie within 7 m comes before every goal and is
  a straight line, so (1) in a corner it ends against a wall (the stuck rule's sidestep turns to one side only, into
  the next wall) and the walk to the locker, which started past the zombie, is never taken; the zombie of seed 2 stood
  in the booth's wall and hit through it, so it was no target either; (2) with nothing to shoot the flight still
  went on, the dead (as fast as it) closed a ring round it, and it never struck with the quick melee. I first read
  it as the second only, wrote the melee rule and a test, and the test passed: it had put one zombie in the open,
  and the real states (the `STALL` rows of the run) still stood.
- **Fix:** copy each stall's own numbers into a test and run it on `main` first (the corner and the zombie in the wall
  moved 0.11 m in 60 s; the 23 dead of seed 3 with both guns emptied: 0 kills, 28 dead standing). Two sidesteps
  within 3 s now mean it is pinned, and for 4 s it walks its way to its goal instead of away from the dead; a
  firearm with no round and none to load is not fled with (it walks to the locker through the dead) and strikes
  with the quick melee. Each rule alone fixes only its own test: the pin rule alone left the mob at 0 kills.
- **Docs:** Deadnight `docs/research/bots.md` ("The autopilot pinned by the dead (#1351)").
