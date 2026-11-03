---
areas: [tests, godot]
---
# A capture's camera drew a tick behind the scene it was placed in

2026-11-03

- **Saw:** a Movie Maker tour that moved its camera and switched light cards on in the same `_process` gave a "before"
  frame with the cards already on: the camera still showed the last spot while the cards had changed (Deadnight #636).
- **Cause:** the project has physics interpolation on, so a `Camera3D` placed by hand in `_process` is drawn where the
  last physics tick left it; node visibility changes at once.
- **Fix:** `physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF` on a capture camera (and any model it places
  by hand), and take the settled frame a frame before the switch.
- **Docs:** [physics interpolation](../godot/physics-interpolation.md).
