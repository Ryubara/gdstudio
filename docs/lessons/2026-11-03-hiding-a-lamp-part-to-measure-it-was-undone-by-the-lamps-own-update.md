---
areas: [tests, godot]
---
# A lamp part hidden to measure its bleed through a wall was shown again by the lamp's own update

2026-11-03

- **Saw:** the bleed check of the back lot's lamps (Deadnight #851, #832's method: hide a part, draw again, count the
  pixels that change) first read 0 pixels for every part of every lamp, where a camera behind the wall plainly showed a
  pool; the next try hid "every `Pool` and `Light` left of x = -16" and read 94,000 and 620,000 pixels that were the
  field's own lamps.
- **Cause:** two faults in the probe. `visible = false` on a lamp's pool, halo or light is undone: the lot's lamp code
  sets `visible` and the energy every tick (the flicker is a function of the tick), so the part came back before the
  frame was drawn. And the filter was a coordinate test, so it hid the neighbours' parts too.
- **Fix:** hide with what the game does not touch (`light_cull_mask = 0` for a light, `layers = 0` for a mesh) and pick
  the parts by their path under the group being measured (`/BackLot/Lamps/`). A probe that must read non-zero somewhere
  is run first on the unfixed scene (here 28,000 to 330,000 pixels behind each wall), so a 0 after the fix means
  something.
- **Docs:** [Compatibility lighting: a lamp near a wall](../godot/compat-lighting.md#a-lamp-near-a-wall).
