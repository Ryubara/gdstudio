---
areas: [gameplay, tests]
---
# A round that would not end on one seed after dressing a map was there before, on another seed

2026-11-03

- **Saw:** after the second map's kit went on, one solo bot night (seed 1) never closed round 1 ("a round that would not
  end"), where seeds 1 to 3 of the undressed map all reached round 10. It looked like the dressing's fault.
- **Cause:** not the dressing. A baseline of eleven seeds on a detached checkout of the commit the branch began from
  stalled too (seed 11, round 9), by the same mechanism: a dead whose path crosses another window's gap stops at its own
  gate's line (a line across the wall with no width), out of sight behind the wall, and tears that gate's boards while
  the bot mends them. Three seeds had hidden it. Moving one prop that did block a window (a rubble cone in front of a
  window, found by a probe of each window's way through the walking mesh) did not change seed 1.
- **Fix:** judge a soak regression against a baseline of at least eight seeds measured the same way (detached checkout,
  the start commit named in the log), compare the kind of failure and not the seed number, and open an issue for a
  failure the baseline shows too.
- **Docs:** [the second map, the soak and the phone profile](https://github.com/Ryubara/deadnight/blob/main/docs/research/maps/small-map-play.md).
