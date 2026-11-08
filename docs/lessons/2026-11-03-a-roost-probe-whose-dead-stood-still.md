---
areas: [tests, gameplay]
---
# A roost probe reported "no blows" with ten dead that never moved

2026-11-03

- **Saw:** the map review's `roost_probe.gd` (ten dead chasing, 40 s) printed 0 blows with the player on the second map's
  counter and 7 on the floor, but its "nearest zombie" never fell under the 3.08 m of the ring the dead were put on.
- **Cause:** the probe called `sim.spawn(id, 0.0, position)`; the second argument is the zombie's speed, so its ten dead
  stood where they were put. The blows came from the director's own first wave, not from the ten.
- **Fix:** give the probe's dead a walking speed (2.4 m/s) and print the nearest 3D distance. With moving dead the numbers
  keep the finding (counter middle 0 blows, edge 5, hall floor 5, a rack top 5). A probe of "can the dead reach it" prints
  how close they got, and a result of "nobody came" is a probe fault until the nearest distance says otherwise.
- **Docs:** [Map review](../engines/godot/map-review.md) (the roost probe).
