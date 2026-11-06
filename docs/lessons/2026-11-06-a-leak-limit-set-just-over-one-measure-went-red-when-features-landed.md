---
areas: [tests, godot]
---
# A leak limit set just over one measure went red when features landed

2026-11-06

- **Saw:** Deadnight's nightly `leak` job (a 30 minute night at a fixed step, `tools/perf/leak_budget.json`)
  failed on 2026-11-04 on memory growth (1.8 MB a wall minute against 1.5) and on 2026-11-05 on
  `resources peaked at 2576, over its limit
  2500`, with every growth inside its limit. The limits were set the day before from one night (2 324 resources, 7.6%
  under the limit).
- **Cause:** not a leak. The resources a headless run holds at its first second rose from 1 414 to 1 586 in one day of
  merges (94 more files in the cache by path, 85 of them GDScript of new systems, and 86 unnamed ones), and the rise from
  the start to the peak stayed at 967 to 994. That rise is the sounds a night plays: a dump of the cache by path
  (`ResourceLoader.has_cached` over every file, at six moments) showed the Ogg streams going from 14 to 401 of 840, 2.0
  to 2.8 resources and 0.2 MB of static memory each, flattening as the night goes on (60 new streams in the first 30 s,
  191 to minute 6, 84, 47, then 5). A 60 minute night confirmed it: resources 5.7, 1.1 and 0.0 a night minute in the
  three windows after minute 12. An absolute peak limit on a count that every feature adds to goes stale with the first
  batch of features. (The memory failure of 2026-11-04 was not this: see
  `2026-11-06-a-growth-limit-was-read-per-minute-of-the-wall-clock.md`.)
- **Fix:** the limit moved with the measure, not past it: resources 2 500 to 2 750 (6% over the most any 30 minute night
  read, 4% over the 60 minute plateau), memory growth was moved to 2.5 here too and put back to 1.5
  when the wall clock was found to be the fault, with the table of measures in `docs/research/performance.md`.
  The resource cache dump is how to name what a count is made of.
- **Check next time:** when a nightly count goes red, find the first-second value and the rise to the peak before touching
  a limit (if only the first-second value moved, a feature did it); dump the cache by path to see what the rise is; and
  run one night twice as long to see whether the count flattens.
- **Docs:** [naming what the resource count is made of](../godot/resource-count.md); Deadnight's
  `docs/research/performance.md#the-two-red-leak-nights-of-2026-11-04-and-2026-11-05-1319`.
