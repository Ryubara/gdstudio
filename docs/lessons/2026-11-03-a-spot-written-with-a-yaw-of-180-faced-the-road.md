---
areas: [godot, gameplay, tests]
---
# A spot written with a yaw of 180 faced the road, and aiming it right put a seventh light on the stand

2026-11-03

- **Saw:** the booth's projector spot (`ProjectionBooth/Lamps/ProjectorBeam`, Deadnight #840, found by #832's
  `GlowBleed`) lit the booth's south door and the road plaza through the booth's wall (0.89 energy). Turning it north,
  at the middle of the screen 70 m off, made `test_lot_light_cap.gd` fail: the stand's roof, walls and sign were lit by
  7 lights where the lot keeps 6 for a fight, and four cars too.
- **Cause:** a spot's forward is its -Z, so the builder's `yaw 180` pointed it at +Z (the road) for the whole life of the
  map: the builder's number read as "face the screen" and no test or capture looked at where the light lands. Then the
  renderer lights a mesh by the **box** of a spot's cone, not its shape (`LightCap.reaches`): aimed at the middle of the
  screen the lower edge of the 7 degree cone dipped under the stand's roof (4.3 m) 20 m from the booth, and a box is
  lit by every light whose box touches it. The cap test was the one that saw it, and only after the aim was fixed.
- **Fix:** yaw 0, and a pitch equal to the cone's half-angle, so the lower edge runs level at the spot's own height
  (5.4 m, over every roof, car and the ground): the axis meets the screen's face 14 m up and the cone still covers its
  middle. A test holds the aim (the axis lands on the screen, its middle is inside the cone, the edge is level) and that
  no wall or roof of the lot is inside the cone; run the lot's light-cap test after any change to a light's aim, not
  only its position (the lesson on [a moved lamp](2026-11-03-a-moved-lamp-went-over-the-light-budget-next-door.md)
  says the same of a lamp that moves).
- **Also:** to count what one light changes in a before and after capture, free it (`queue_free`, one more frame) rather
  than setting `visible = false` after the circuits are on: hiding the spot, setting its `light_cull_mask` to 0 or
  hiding the screen's lamp each changed the whole plaza's brightness (mean 40.9 to 32.3, 160 000 pixels) from a spot
  facing away from it, while freeing the spot changed 2. Not traced to its cause; the nearest known one is
  [the renderer choosing other lights](2026-11-03-a-before-after-capture-differed-because-the-renderer-drops-lights.md).
  The screen's own grain also moves between two runs: count pixels away from the screen face.
- **Docs:** [Compatibility lighting](../engines/godot/compat-lighting.md#lamps-in-a-game-what-looks-like-light-and-what-is-light),
  Deadnight `docs/research/night-environment.md` (the booth's spot).
