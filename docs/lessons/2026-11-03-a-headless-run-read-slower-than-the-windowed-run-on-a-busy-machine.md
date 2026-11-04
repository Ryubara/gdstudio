---
areas: [tests, tools]
---
# A headless run read slower than the windowed run of the same night

2026-11-03

- **Saw:** the same night at 100 dead took 18 to 24 ms a frame windowed and 58 to 237 ms headless, on a machine at 88 to
  100 % CPU with 20 to 46 Godot processes (Deadnight #906). One windowed run of an earlier build read 115 ms a frame at
  45 dead and 8 ms an hour later.
- **Cause:** wall time on a shared machine is the share of the processor the run got, and the share differed between
  runs of the same code by 10 times or more. The headless run lost most (why it fared worse than a windowed one was not
  found); at real time it also runs several ticks a frame to catch up, so its frame is longer still.
- **Fix:** time a headless run at `--fixed-fps 60` (a frame is a tick) and read labelled script times and the
  process's CPU seconds a tick; hold a frame to a multiple of a calibration loop timed in the same process; record
  machine load beside each run; interleave before and after; report every repeat.
- **Docs:** [Performance budgets](../godot/performance-budgets.md#reading-a-timing-on-a-shared-machine).
