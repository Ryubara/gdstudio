---
areas: [tests]
---
# A before-and-after probe died on a parse error in the "before" tree and counted as 90 deaths

2026-11-04

- **Saw:** the cold loop reported "completed 0 of 30, died 30" for every group before the change, and 30 of 30 after,
  a perfect-looking result. The death lines said `Too many arguments for "warm()" call`.
- **Cause:** one probe script was run against both trees, and it called the new `ShippedCells.warm(specs, assist)`; the
  untouched copy of main only has `warm(specs)`, so the script never started. A loop that counts "no done line" as a
  death cannot tell a crash from a script that did not load.
- **Fix:** a separate probe for the old tree without the new call, and the loop prints the first error line of every
  dead run; read those before trusting a rate (the real before rates were 2, 3 and 0 of 100).
- **Docs:** [Worker threads](../engines/godot/worker-threads.md). Check for next time: run each arm once by hand and
  see its
  success line before looping, and read the first dead run's output.
