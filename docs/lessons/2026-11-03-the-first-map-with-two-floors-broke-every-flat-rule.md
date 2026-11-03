---
areas: [gameplay]
---
# The first map with two floors broke every rule that measured flat

2026-11-03

- **Saw:** on Deadnight's second map (two storeys, 3.4 m apart) a zombie on a stair struck a player standing beside it
  through the wall, a player upstairs was offered the door on the ground floor under him, and a zombie that had risen at
  an upper window walked the ground floor's height: the dead of the upper floor stood in the floor.
- **Cause:** every distance in the zombie simulation, the use button and the targeting was the flat distance (x and z
  only), and a zombie kept the height it spawned at, because the only map until then (the drive-in lot) had one floor.
  Nothing said so: each rule was right on that map.
- **Fix:** a map that declares a storey turns on the floor rules (`ZombieSim.storey`): the dead follow the walking
  mesh's heights (the path point less the baker's lift), weigh a player on another floor by the stair, and swing only
  at a target within half a storey in height with a clear ray to it; a press reaches only what is on the player's floor
  (`NightWorld.on_level`). The flat map keeps the old code path, so its tests did not move. Found by tracing a bot's
  deaths: `HURT` lines with each zombie's `dy`, not by the tests, which had no floors.
- **Next time:** before the first map with floors (or a roof, a pit, a platform you can stand on), `grep` every
  `_flat(` and every `Vector2(a.x - b.x, a.z - b.z)` in gameplay code and decide for each what a metre of height does to
  it; give the map a test where the two points are one floor apart and a flat distance of 0.3 m.
- **Docs:** Deadnight's design page for the second map, "Floors for the dead"
  (`docs/design/smallmap.md`).
