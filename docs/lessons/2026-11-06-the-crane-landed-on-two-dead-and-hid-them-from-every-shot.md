---
areas: [gameplay, tests]
---
# The crane landed on two dead and hid them from every bot and shot

2026-11-06

- **Saw:** three bots 0.8 to 2.6 m from the last two dead of round 10 (autopilot night, seed 13, 1 040 s) had no contact,
  never fired and stood on `hunt` and `choke`; one bot's `look` read the same number for 1 000 s. Deadnight #1352.
  About 25 nights on `main` and a staged night with the dead at those places saw nothing wrong: the bots saw and shot them.
- **Cause:** the prize crane's cabinet is a solid box (`CraneBlock`, layer 1) that the rules move at a breakdown, and it
  landed on two dead standing at the new spot. The dead are not physics bodies, so they were inside a wall that every sight
  line and shot ends on, and a swing on the lot has no wall check: they hit the bot beside the box for ever (and every blow
  reset the director's rescue clock). Nothing looked at the world the dead stand in; every earlier check (the map at round
  1, the rays at the night's coordinates) was made before the crane had moved.
- **Fix:** `ZombieSim` keeps a dead that stands (and every dead on the step after a landing) out of the box
  (`ZombieSolid`, `docs/research/zombies.md`); `test_crane_cabinet_dead.gd` lands the crane on two dead on the real lot.
- **How it was found:** the night was not repeatable by seed, so the repro was the original commit with the original
  probe's prints (a print shifts the timing of the night; a lighter probe gave another night), plus a probe that fires on
  the symptom (a bot hit and holding no contact for 8 s) and dumps a physics point query at each dead's feet, which named
  `CraneBlock`. Query a point with the node's name, not only a ray: a ray said "blocked at 1.1 m" and could be a body.
- **Check next time:** when a unit stands still and nobody can hit it, list what the physics space holds at its feet
  at that moment, in the night that had it; and a thing that moves in a night (a crane, a door, a board) is tested with
  everything that can stand where it lands.
