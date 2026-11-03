---
areas: [gameplay, general]
---
# A team job gated by a rotating turn and a one-errand lock was never done

2026-11-03

- **Saw:** four bots on the second map (Deadnight #696) bought the door and the first stair, then held thousands of
  points for a whole night; the second stair was never bought, where one bot alone bought all three by round 6 to 8.
- **Cause:** two gates stood in front of a link: the door's own "turn" (the nearest bot that can pay, rotating every
  40 s) and the team's one-errand turn (30 s slices, spent on ammo and weapons first). The holder of either was rarely
  free with the dead within 5 m, and nobody else was allowed to act, so the job waited on a bot that could not do it.
  A second cause sat behind it: a link set in a stair has a stand at its foot and one a flight up, and the flat-nearest
  stand sent a bot on the ground floor round the whole map (and 180 s of fights) to the upper one.
- **Fix:** the job is claimed by the nearest bot that is free right now (the same claim by distance the bodies use),
  outside the other turns, so the busy and the far cover; a stand is chosen by walking cost (8 m a metre of height).
  A soak of four bots over five seeds is the check: every link by round 3, no bot over twice a link's price for more
  than 16 s (before: the second stair never in three of three, 400 s over). Look at the trace of what a bot that holds
  points is doing (`--trace --every=3`), not only at who holds the turn.
- **Docs:** the game's `docs/research/maps/small-map-play.md` and `docs/design/smallmap.md#bots-on-the-map`.
