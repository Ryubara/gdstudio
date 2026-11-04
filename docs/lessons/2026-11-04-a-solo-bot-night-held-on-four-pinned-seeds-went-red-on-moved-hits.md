---
areas: [tests, general]
---
# A solo bot night held on four pinned seeds went red on a change that did nothing wrong

2026-11-04

- **Saw:** Deadnight `test_smallmap_bot_night` held the solo bot on seeds 1, 3, 4 and 7. It went red on seed 7 for a
  change that only moved where the dead are hit (#1038), and had flaked on a seed before (#821, #890, #910). Main itself
  fails 5 of seeds 1 to 100 (38, 40, 50, 64, 84: the lone bot is downed in round 3 or 4), so four seeds picked on the
  night they passed said nothing about the rate.
- **Cause:** the night is chaotic: one moved hit moves every night after it, on every seed. A test over a few pinned
  seeds asks "is this seed one of the 5%?", which a reshuffle answers at random.
- **Fix:** the test plays seeds 1 to 10 and allows 3 failures; the limit comes from a sweep of 100 seeds on main (5 of
  100; ten-seed blocks fail 0 to 2), with the false-red chance of the limit from the binomial (0.1% at 5%, 1.8% at 11%)
  and the teeth shown by a deliberate break (the bot buys only the links): 10 of 10 nights fail. A night is 4.6 s, so the
  sweep (100 seeds, `smallmap_solo_sweep.tscn`, four processes) lives outside the suite and the suite keeps ten.
- **Check:** a test on a chaotic night asserts a rate with a limit measured on main (seeds, rate, margin written in the
  test), never seeds picked to pass; if the seeds needed cost too much for the suite, put the sweep in a capture scene.
- **Docs:** Deadnight `docs/research/bots.md` (the solo night). Related: the lesson on a pinned seed that moved when
  the dead were hit differently (kit pull request 546).
