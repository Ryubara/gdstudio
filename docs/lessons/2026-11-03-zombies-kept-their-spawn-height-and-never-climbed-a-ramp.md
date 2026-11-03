---
areas: [gameplay, tests]
---
# The dead kept the height they spawned at and never climbed the booth ramp

2026-11-03

- **Saw:** players said zombies have trouble going upstairs. A pack sent at a person on the booth's roost: 0 of 6 at the
  top in 40 s (0 of 16 for a bigger pack), shuffling at the ramp's foot; the small map's stairs the same (Deadnight #681).
- **Cause:** the zombie sim moved a zombie in x and z only ("the lot is flat"), so its height stayed 0 while the path
  climbed. Each repath snapped that ground-level position to the nearest mesh point, which a little way up the ramp is
  the floor beside it, and the path from there led back to the ramp's foot. The earlier ramp tests walked a physics
  body (the bots, the players), never a zombie, so nothing sent the dead up anything.
- **Fix:** the sim reads the floor off the path (the segment ending at its waypoint, minus the baker's 0.4 m offset) and
  moves the zombie there; separation and swing reach look at height too. A pack test sends six and sixteen up the ramp
  and both small-map stairs, with a control that walks the same mesh with the heights left out (it fails on `main`).
- **Docs:** [Zombie crowds: height](../godot/crowds.md#height-a-crowd-off-the-physics-engine-must-be-given-its-floor);
  Deadnight `docs/research/zombies.md`, "Climbing". Check: a feature that moves things by hand (no physics body) is
  tested on every slope of the map with the real mover, not with the player's body.
