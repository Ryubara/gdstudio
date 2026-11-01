# A hand-blended camera left the body stepping at 144 Hz

2026-11-01

- **Saw:** seen from the side while strafing, the character looked doubled and blurry on a 120, 144 or 165 Hz screen,
  and fine at 60 Hz.
- **Cause:** the body moved on 60 Hz physics ticks and was drawn at its tick position, while the camera blended the last
  two ticks by hand with `Engine.get_physics_interpolation_fraction()`: a smooth camera over a stepping body, so the
  body swung by a tick of travel (18 px at 1280x720) every two or three frames. `physics/common/physics_interpolation`
  was off.
- **Fix:** turn on the project setting; set `physics_interpolation_mode = OFF` on the hand-blended camera rig (left on,
  the engine blends it a second time and the body still wanders 11 px); `reset_physics_interpolation()` after a
  teleport or a first placement; OFF on anything a tween or `_process` moves. Prove it by the position on the
  screen at 144 fps over 60 ticks, never by the node's `global_transform`, which never shows the blend.
- **Docs:** [Physics interpolation](../godot/physics-interpolation.md).
