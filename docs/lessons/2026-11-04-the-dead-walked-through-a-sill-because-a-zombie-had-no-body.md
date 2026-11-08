---
areas: [gameplay, tests]
---
# The dead walked through a window's sill because a zombie was a point

2026-11-04

- **Saw:** "zombies would just phase through the wall" (Deadnight #915). On the second map the dead came in through
  every window at floor height, through the 0.9 m sill and the jambs, with no climb and no clip for one.
- **Cause:** a zombie is a point in the simulation: it walks the navigation path and has no collider. The windows had
  split the walking mesh (a 2.0 m gap) from the drawing (a sill, a 1.2 m opening) so players were blocked, and nothing
  asked whether the dead's *bodies* fit the drawn opening. Every test asked only that they got in. A rig with no climb
  clip made it look like one more missing animation.
- **Fix:** the simulation is the link over the sill (an exact lift that starts a body's width before the ledge, a clamp
  between the jambs, a 1.5 m gap so the way stays inside the opening), the view draws it with the crawl clip, and a test
  walks a capsule of the zombie's width through every barricade of both maps along the real navigation mesh at a stroll
  and a sprint, asking at each step whether it stands in a solid. A climb slowed to 0.6 of the dead's pace moved a bot
  night (the weapon bought a break later in 2 seeds of 4): keep a change of look from being a change of pace.
- **Docs:** [map review checklist, section 3](../engines/godot/map-review.md#3-spawns-and-how-the-dead-arrive).
