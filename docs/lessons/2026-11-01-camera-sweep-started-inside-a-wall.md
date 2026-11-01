# A camera sweep test reported thousands of false failures

2026-11-01

- **Saw:** a test that swept the shoulder camera over a grid of the lot failed on 16,000 samples, the first at the
  lot's outer corner, where the "player" stood inside a thin wall.
- **Cause:** the grid took the floor from a ray cast from above (which hit wall tops), and "a capsule fits here" said
  yes inside a CSG wall: concave shapes do not report a shape lying inside them, and `cast_motion` ignores bodies it
  starts inside, so the camera passed through the wall.
- **Fix:** take standing places from the baked navigation mesh (within 0.15 m of it), start every sweep from a clear
  point, and cast the ground ray from just above the floor.
- **Docs:** [Third-person camera](../godot/camera.md#walls).
