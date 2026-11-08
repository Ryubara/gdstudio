---
areas: [tests, ci]
---
# A section of a few microseconds was held to a ratio of the calibration loop, and the ratio moved 2.1 times by runner

2026-11-05

- **Saw:** Deadnight's `server.challenges` budget (limit 0.012 times the calibration loop) failed a UI-only pull request
  at 0.0123 and `main` at 0.0120, with unchanged code. The same ratio over 46 runs: 0.0057 to 0.0123. The XP award
  section beside it had a limit (0.01) that a section twice as slow never reached (it read 0.0010 to 0.0026).
- **Cause:** the calibration (a hot loop of 3 ms, best of five) is the wrong ruler for 30 microseconds of cold script.
  The runners come in three kinds the loop tells apart (3.1, 4.5 and 6.0 ms) and the section costs the same on all
  (0.032, 0.039, 0.041 ms): the ratio of the fast kind sat at 84 % of the limit with nothing changed. A busy neighbour
  slows the frame and the section together, and a best-of-five loop does not see it. Regressing the log of the section
  on the logs of the frame and the calibration over the 46 runs: slope 0.98 on the frame (r 0.92), 0.35 on the
  calibration (r 0.49). The guess ("load the calibration does not measure") was half of it; the other half was hardware.
- **Fix:** hold the section as a share of the frame the same rows took (`frame_ms`): the spread fell from 2.1 to 1.36
  times. Put the limit between the highest share seen and twice the lowest, show on the logs of the last runs that
  unchanged code passes and the code made twice as slow (multiply the label) fails on every one, run a throwaway
  `while Time.get_ticks_usec() - began < 2 * spent: pass` once in the real command, and keep both facts in a unit test
  of the checker so a moved limit fails in CI. Check for next time: before choosing what a timing is divided by, fit
  the slope of the log of the timing on the log of each candidate across runs; a candidate whose slope is far from 1 is
  not cancelling the host. Also keep a mean's rounding below the quantity (0.001 ms on 0.006 ms is 7 %).
- **Docs:** [Performance budgets](../engines/godot/performance-budgets.md#budgets-counts-tight-time-loose) and Deadnight's
  `docs/research/performance.md`, "What the label limits mean".
