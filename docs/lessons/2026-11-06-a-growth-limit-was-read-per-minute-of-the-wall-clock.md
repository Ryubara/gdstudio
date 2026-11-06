---
areas: [tests, ci]
---
# A growth limit was read per minute of the wall clock, and a fast runner read three times as steep

2026-11-06

- **Saw:** Deadnight's nightly `leak` job (a fixed-step night, `tools/perf/check_budget.py`) failed on static
  memory growth (1.8 MB a minute against 1.5) on 2026-11-04 and, in a dispatch to prove a fix, on nodes (44.3 a
  minute against 40)
  while the same code read 1.0 MB and 11 nodes on other nights. Memory had been "fixed" by raising its limit to 2.5, the
  wrong answer.
- **Cause:** the check fitted its line through `t` of the sampler's rows, which is the wall clock. The night is the same
  on every machine (a fixed step, one row a second of the night, 60 frames each), the wall clock is not: the same 1 079
  steady rows took 280 s on a laptop, 314 to 317 s on one runner, 437 and 553 s on others. So the same growth read 1.8,
  2.2, 1.0 and 1.0 MB a minute; per minute of the night it read 0.4 to 0.6 on all six nights (resources 4.2 to 5.8,
  nodes 0.6 to 12.8, objects 18 to 39), the "6, 34, 6 and 0.4" the limits were written from.
- **Fix:** the line is fitted through the frames stepped at the budget's `fixed_fps` (the night's own minutes);
  `leak_budget.json` has `fixed_fps: 60`; the memory limit is back at 1.5. Tests run the real budget on a flat night and
  on a rise of 1.2 and of 0.5 times each limit, on a fast and a slow runner (`tools/perf/test_check_budget.py`): the
  old read fails the half-limit case.
- **Check next time:** a rate limit on a fixed-step run is read in the run's own time, never the wall clock; before a
  limit moves for a red rate, print the rate over two other nights and the wall seconds of the same window (if the
  seconds differ by 1.5 times or more, the unit is the suspect).
- **Docs:** Deadnight's `docs/research/performance.md#the-two-red-leak-nights-of-2026-11-04-and-2026-11-05-1319`.
