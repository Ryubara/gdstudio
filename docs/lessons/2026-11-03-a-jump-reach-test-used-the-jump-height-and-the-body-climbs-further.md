---
areas: [tests, gameplay, godot]
---
# A reach test took the jump height as the most a player climbs; the real body gets onto a ledge 0.15 m higher

2026-11-03

- **Saw:** the lot's jump-reach test and the map page count a barrier as safe when its top is more than the jump height
  (1.1 m) above everything a player can stand on. A probe that ran the real player body (`PlayerSimulation`) at blocks of
  every height from level ground got onto one 1.25 m high and not 1.3 m (Deadnight #833). The second map's start-room
  counter, built "a little over a jump" at 1.2 m, is climbed from the floor, and the middle of its top is out of every
  zombie's reach: ten dead for 40 s landed 0 blows on a player there and 7 (a death) on the floor.
- **Cause:** a body's reach is the jump plus the step-up the simulation gives on landing at an edge and the rounded
  foot of the capsule; no number in the tuning says it, so a test written from `jump_height` was 0.15 m short on every ledge.
- **Fix:** measure the reach by running the real body at ledges (`tools/world/ledge_probe.gd`: sprint and walk at a block
  of each height, jumping at nine moments) and write the number where tests read it; judge every wall, door slab and
  prop against the measured reach, and run the body, not a formula, at each candidate. Look at a prop's height against
  1.25 m, not 1.1 m, when a design page says "unjumpable".
- **Docs:** [Map review, collision hygiene](../godot/map-review.md#7-collision-hygiene-out-of-bounds-and-skipped-doors).
