---
areas: [tests, godot]
---
# A screen test passed the layout it was written to catch

2026-11-03

- **Saw:** a test that the crane's prize is not behind the Soldier passed with the prize moved down behind his head.
- **Cause:** three things: a headless test's viewport is 1920 x 1920, not the screen's shape; the body's rectangle came
  from skinned mesh boxes, which in a test that never animates are the rest pose's (arms straight out, the rectangle
  most of the screen); and the first `snap_to` after turning the camera rig left the camera's old transform.
- **Fix:** project into a `SubViewport` of 1920 x 1080 with its own `Camera3D` copying the player camera's transform
  and FOV; build the body as a box round the `Head` bone (0.36 m over it for the hair, 0.7 m across, measured on a
  capture); snap twice. Then run the test once with the bad layout and see it fail before trusting it.
- **Docs:** [Measuring an effect on the screen](../engines/godot/measuring-effects-on-screen.md#a-reveal-from-where-the-player-stands).
