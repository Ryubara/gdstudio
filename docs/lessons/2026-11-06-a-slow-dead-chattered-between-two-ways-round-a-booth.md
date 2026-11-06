---
areas: [gameplay, godot]
---
# A slow dead stood six minutes between two near-equal ways round a booth

2026-11-06

- **Saw:** the nightly's `regular_3_hold_person` cell had 13 nights of 100 that ended as `stalled_round`, in 12 of them
  with one crawler parked at the same point, `(-8.5, 45.2)`, tails of 365 to 413 s (Deadnight #1347). The guess was a hole
  in the mesh or a gate the crawler could not leave; neither was there. The same cell re-run on the unfixed commit: 9 of
  45 nights stalled, all nine at that point.
- **Cause:** the spot is the west face of a 2.4 m ticket booth. The way round the booth to the north and the way to the
  south are within a metre or two of one length, and the walking mesh's search names the north way from a diagonal strip
  beside the face and the south way from both sides of it. A body repaths every 0.3 m of walking (a crawler: 1.2 m/s),
  so it walked out of the strip along one way, was told the other, walked back into the strip and was told the first
  again, for ever. Nothing was stuck: the body moved all the time, so a stuck detector and a look at the mesh saw nothing.
- **Fix:** hold the route (the same hysteresis the zombies already had for a much longer one, `ROUTE_FLIP`): a new
  route that sends the body back the way it is going is not taken unless it is `ROUTE_GAIN` (4 m) shorter than what is
  left of the old one; a body shoved off its route (more than 1 m from its leg) takes the new one, and a route that
  goes on the same way is taken as ever, so a crowd still spreads. The test puts a crawler and a walker on a 0.3 m
  grid round the face and needs all of them past the gate in 40 s (with the rule off: 31 crawlers and 18 walkers
  stayed south). Look for this when a body is "stuck" but its position changes: print its path's first leg at every
  repath, and if it flips sign it is a chatter, not a trap. A probe that starts the body from a grid of places round
  the spot (not from one) shows it, because only the starts in the strip stick.
- **Docs:** Deadnight `docs/research/bots.md`, "A crawler that parks at the drive-in's west ticket booth (#1347)".
