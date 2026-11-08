---
areas: [camera, gameplay, godot]
---
# A cutscene camera at a fixed offset stood behind the lot's movie screen

2026-11-04

- **Saw:** Deadnight's helicopter drop (#1057) put its camera 14 m back and 24 m up from the player's spot, along a
  heading turned from their facing. In the first capture the picture was the back of the drive-in's movie screen, a
  grey slab across the whole frame, and the helicopter was out of the top of it. The spot is by the screen, and the
  fixed offset put the camera on the far side of it.
- **Cause:** the camera was placed from the spot alone and never asked what stands in the way. The same fixed framing
  also cropped the helicopter: the look-at point was at 42 % of the hover height, which put the rotor over the top edge.
- **Fix:** a heading chosen by rays: twelve headings, nearest the preferred first, each casting camera to spot, spot to
  the sky above it and camera to the look-at point against the world layer, the first with all three clear (the most
  clear when none is; the nodes the show hides, a roof, are skipped by the rays). The look-at point rose to two thirds
  of the hover height and the camera backed off, then comes in toward the Soldier as he lands. A test puts a wall where
  the preferred camera would stand and fails if the heading does not turn.
- **Check next time:** a camera that is not the player's own goes through a capture on every map the game ships
  before it is called done, and is placed by what is between it and its subject, not by an offset.
- **Docs:** [A cutscene one client plays](../engines/godot/client-cutscene.md), "Stand the camera where nothing solid
  is between
  it and the spot".
