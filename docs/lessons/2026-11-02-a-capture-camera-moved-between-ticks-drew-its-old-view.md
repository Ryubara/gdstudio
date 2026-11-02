# A capture camera moved between ticks drew its old view

2026-11-02

- **Saw:** a capture script moved its own Camera3D to a new view and saved the frame; the PNG showed the previous
  view (a top-down shot where a side view was asked for), though the printed position was right.
- **Cause:** physics interpolation is on: a node moved outside a physics tick is drawn where the last tick left it.
- **Fix:** `physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF` on cameras and props a capture places by
  hand (as the game's remote avatars already do).
- **Docs:** [Physics interpolation](../godot/physics-interpolation.md).
