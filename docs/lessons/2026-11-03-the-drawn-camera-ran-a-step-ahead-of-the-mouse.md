---
areas: [input, camera, godot, tests]
---
# The drawn camera ran a step ahead of the mouse, so lag made the look jerk and turn back

2026-11-03

- **Saw:** the maintainer, playing a night with bots: the mouse look went odd whenever the game lagged, which other games
  do not do (Deadnight #905). Every look test passed: the rig's yaw was exactly the hand's at every frame rate.
- **Cause:** `ThirdPersonCamera._place` set the child `Camera3D`'s `global_transform` and then moved its parent (the
  `top_level` rig, new yaw and pivot). The child keeps its local transform, so the lens was drawn at the view plus one
  more step of the rig's last turn: a frame with no mouse turned the view back, a long frame overshot by its whole
  turn. With a recorded mouse path at 144 to 15 fps and with hitches, the drawn view was 33 to 133 degrees from the
  hand at the worst frame and 11 to 67 frames in 7 s went against it. Gamepad and touch look took the same path.
- **Fix:** set the rig before the lens. `tests/player/test_look_frames.gd` replays the path through the real input path
  over 1/144, 1/60, 1/30, 1/15 s frames and a seeded uneven run (alone and as a client of a game server) and reads the
  `Camera3D`'s transform, not `rig.yaw`; all six cases failed on `main` and pass.
- **Docs:** [Mouse look at any frame rate](../godot/mouse-look.md); Deadnight `docs/research/mouse-look-under-lag.md`.
  Check: a test of a view or an aim reads the node the renderer draws (the `Camera3D`'s `global_transform`), and
  anything placed by hand in `_process` sets the parent's transform before the child's.
