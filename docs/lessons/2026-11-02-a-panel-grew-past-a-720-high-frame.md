---
areas: [godot, web]
---
# A centred panel grew past a 720-high frame

2026-11-02

- **Saw:** the Together invite panel (Share, the clipboard line, the selected-code field) and then the new lobby
  screen with a blocked copy ran off the bottom of a 720-high window: Start and Leave were out of reach.
- **Cause:** every screen was captured in its common state, never the tallest one (all optional lines showing), and
  the panel had no height limit.
- **Fix:** capture and unit-test the tallest state at 1280 x 720 (`SubViewport` in GdUnit4); put buttons in rows,
  ellipsise one-line text, cap a `ScrollContainer` at the viewport height minus a margin, `follow_focus = true`, and
  `ensure_control_visible` two frames after showing a field (Deadnight #537).
- **Docs:** [UI controls](../godot/ui-controls.md).
