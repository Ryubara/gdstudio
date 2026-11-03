---
areas: [tests, gameplay]
---
# A trimmed sweep test passed on the map it was written to catch

2026-11-03

- **Saw:** the test for the midway's stair over the fence (Deadnight #846) ran the real player body from a 1.5 m grid
  of ground cells beside the fences, three hops deep. On the unfixed map it passed. The full probe's chain started at
  `(-13.5, 0, 1.5)`: a sprint-jump with the button down on tick 20 puts the body on the barrels, and the nearest cell of
  the 1.5 m grid was 0.25 m off, where the same jump lands on the floor.
- **Cause:** a body-run sweep is a search, not a proof, and a jump's landing depends on the start to a few centimetres.
  The trimmed grid was never run against the broken map, so nothing said it could not see the thing it was written for.
- **Fix:** run every new sweep test on the unfixed map first and tune it (a 1.0 m grid, the jump ticks the chain used)
  until it fails there with the chain; keep the recorded hops of the known escape as a second test that replays them
  (each hop from where the last landed) and fails on the old map, so the sweep's coverage is not the only guard.
- **Docs:** [Map review, collision hygiene](../godot/map-review.md#7-collision-hygiene-out-of-bounds-and-skipped-doors).
