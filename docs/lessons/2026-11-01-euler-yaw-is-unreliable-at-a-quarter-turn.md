# A marker's yaw read from its Euler angle was wrong at a quarter turn

2026-11-01

- **Saw:** a prop placed from a marker's `global_rotation.y` landed a few centimetres off for markers turned 90 or
  270 degrees, and a test of the distance failed by 0.05 m.
- **Cause:** Euler angles in YXZ order are ambiguous near a quarter turn about Y; the engine may return the same
  rotation as another triple, so `rotation.y` is not the turn you set.
- **Fix:** read the turn from where an axis points: `atan2(basis.z.x, basis.z.z)` gives the yaw about the up axis.
- **Docs:** [camera](../godot/camera.md) holds the other rotation notes.
