---
areas: [gameplay, tests]
---
# A bot cut off from the walking mesh banned every place for ten minutes and stood

2026-11-04

- **Saw:** a Rookie stood idle for 26 s in a break on one seed of a two-bot night (Deadnight #1041), through the next
  round too: the soak's `idle under Roam over 8 s` gate, found only while fitting another change. Nights are not
  repeatable by seed (about half the reruns showed it).
- **Cause:** the bot had stepped (a yield to the other bot at a repair stand) onto a 2 by 2 m piece of the walking mesh
  that joins nothing, because the polygons across a barricade's line are cut out of it. Every path from there ends in the
  piece, so Roam found each place "unreachable" and banned it for ten minutes; nothing in the brain moves a bot with no
  goal. A log of the state machine said nothing (`note=hold`, goal `inf`); only a print of the path queries (two points,
  every goal) and of the refusals (all banned) did.
- **Fix:** a refusal says nothing about the places when the bot cannot even reach the spot it chose from a moment ago:
  `BotRoam` keeps that spot, takes the refusals back and walks straight to it. When a bot has no goal for no reason you
  can see, print the path query's own answer (point count, end point, the layer) before reading the state machine again,
  and test with the real lot: set the bot down beside the piece, move it onto it and read where it is 15 s later.
- **Docs:** Deadnight `docs/research/bots.md#a-rookie-idle-for-26-s-on-a-piece-of-mesh-joined-to-nothing-1041`.
