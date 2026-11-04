---
areas: [gameplay, general]
---
# A barricade shaped like a door told players they could walk through it

2026-11-03

- **Saw:** "every single barricade should be a window, not a "door" -- it gives the players this false idea that they
  can walk through it, but in reality it's just to barricade" (Deadnight #915). The drive-in's six fence breaches and
  the second map's side breach were gaps from the floor to the lintel with boards across; the second map's other
  eleven were windows with a sill.
- **Cause:** the shape of an opening is read as what it affords. The breaches were built as the dead's way in (a path
  needs a gap at the ground) and the generator's gap doubled as the drawn opening, so what the navigation needed set
  what the player saw. The windows had already split the two: the walking mesh sees a gap, the drawing is a sill, a
  frame and a players-only blocker.
- **Fix:** every barricade is a window made by the generators: a 0.9 m sill, jambs and a header as bodies the baker
  never reads, a players-only blocker in the opening, and the dead lifted over the sill by the simulation (the link
  across it) and drawn scrambling in. `test_barricade_windows.gd` walks every barricade of both maps, so a breach added
  later is held to it.
- **Docs:** [map review checklist, section 3](../godot/map-review.md#3-spawns-and-how-the-dead-arrive).
