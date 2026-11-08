---
areas: [camera, godot]
---
# A capture camera moved between ticks drew its old view

2026-11-02

- **Saw:** a capture script moved its own Camera3D to a new view and saved the frame; the PNG showed the previous
  view (a top-down shot where a side view was asked for), though the printed position was right.
- **Cause:** physics interpolation is on: a node moved outside a physics tick is drawn where the last tick left it.
- **Fix:** `physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF` on cameras and props a capture places by
  hand (as the game's remote avatars already do).
- **Seen again (2026-11-03, Deadnight #850):** a script that cut between six breaches saved frames that looked
  at the wrong things (a car park where a fence was asked for) while its printed positions were right; the log had one
  line, `WARNING: [Physics interpolation] Interpolated Camera3D triggered from outside physics process`, and
  `unproject_position()` of the aim point put it off screen. It cost an hour of guessing at stands and layers. First
  check of any capture that cuts between spots: the camera's `physics_interpolation_mode` is OFF, set once when it is
  made; the first frames of the old fix are not enough when the camera jumps tens of metres.
- **Docs:** [Physics interpolation](../engines/godot/physics-interpolation.md).
