---
areas: [gameplay, tests]
---
# A use reach was a distance, so prompts and presses worked through walls

2026-11-03

- **Saw:** the maintainer: "double check collision detectors e.g. that we don't get prompted to interact with an object
  through walls (this is already an issue)" (Deadnight #831). A walk of every interactable on both maps found 910
  prompts through walls on `main` (the wall weapons, re-cut bench, soda fountain, lockers, crane, breaker posts, boards)
  and 41 presses that bought or changed something from the far side; a downed teammate was raised through a wall too.
- **Cause:** "in reach" was written as a flat distance (`use_reach`, `fuel_reach`, `revive_reach`), plus a floor on the
  second map. Each interactable was built with its own check (spots, doors, posts, fuel, revive) and none was a sight
  line, because a reach looked like a number to tune, not a question about the world. The test of each kind stood in
  front of the thing, where no wall is.
- **Fix:** one `UseSight` the server asks in every one of those checks (a static ray from hand to thing: walls, props,
  doors and floors count, a person does not, #805), a side check for things that hang in a wall (a post, a door slab,
  the boards), and a test that walks a grid of standing points around every thing on both maps and demands no prompt
  and no press where a wall is between. The client's card is the server's `prompt` in the frame, so it needed nothing.
- **Docs:** Deadnight `docs/research/use-reach.md`. Check for next time: every "within reach" of a world object is a
  distance **and** a line to it (and a side for a wall mount); a test for it stands behind the wall, not in front.
