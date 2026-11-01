# A full-screen Control built in code drew at the top-left corner

2026-11-01

- **Saw:** markers and a crosshair drawn as `size * fraction` all landed at (0, 0), with no error.
- **Cause:** `set_anchors_preset(PRESET_FULL_RECT)` changes only the anchors and keeps the control's current rect, so a
  freshly made Control stays 0 x 0.
- **Fix:** use `set_anchors_and_offsets_preset(PRESET_FULL_RECT)` for any Control built in code.
- **Docs:** [UI controls](../godot/ui-controls.md); Deadnight `docs/research/hud.md`.
