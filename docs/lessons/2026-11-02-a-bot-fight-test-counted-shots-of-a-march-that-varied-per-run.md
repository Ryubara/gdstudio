---
areas: [tests, gameplay]
---
# A bot fight test counted the shots of a 40 s march that changed from run to run

2026-11-02

- **Saw:** Deadnight #596. `test_the_aim_and_fire_distributions_of_phase_1_hold_in_a_boss_fight` failed once on main's CI
  (`shots > 30` but was 3) and passed on the next run. Repeated in one process with the same seed, the count was 133, 155,
  206 or 218 depending on the run, and only one of the four bots fired at all.
- **Cause:** the dead spawn 60 m and more away and the test waited for them to walk to four bots for 40 s: the first
  bot fired at tick 1542 of 2400, so the count was set by how far the dead had got in the last 14 s. Their route, and the
  bots' own positions, differ by centimetres between runs (the physics bodies' floor contact and the navigation map are
  not bit-for-bit repeatable across nights built one after another in a process), enough to move the first shot by
  seconds. On a loaded machine the cut-off came earlier still.
- **Fix:** the test stages the dead in front of the bots (`SeatedNight.stage_the_dead`, made for this): over 12 runs the
  count was 1381 to 2100 against a bound of 30, and every other assertion (the turn cap, no rejected shot) held.
- **Check for next time:** a test that counts events of a fight must not wait for a march: put the dead where the fight
  is (`stage_the_dead`) or assert the count in a window where a run's variation cannot empty it; to see whether a test
  is stable, run its body 10 to 40 times in one suite and print the number it asserts on, not just pass or fail.
- **Docs:** none beyond this page.
