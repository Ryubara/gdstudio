---
areas: [tests, godot-ui]
---
# A phone capture without the phone scale showed the wrong layout and read as proof

2026-11-05

- **Saw:** Deadnight #1071's capture of the equip screen at 844 by 390 showed the full-height layout (overline, big
  tabs), although the same screen had just been changed for short screens; a second capture, made after the change,
  still did. Only the layout test (`test_ui_fit`, which sets the scale) knew the screen was short.
- **Cause:** the game gives a phone's window `content_scale_factor = MenuScale.factor(window.size, ui_scale)`, so a
  phone lays out on a 1169 by 540 canvas. A capture scene that does not set it is a 1920 by 1080 design canvas shrunk to
  the window: the right pixels, the wrong layout, and nothing says so.
- **Fix:** every capture that takes phone shots sets the factor the game does (`MenuScale.factor(window.size, 1.0)`,
  then one frame) before it builds the screen. Check for next time: after a phone capture, read the layout (is the short
  variant on show?), not only the pixels, and compare the canvas size in the capture with the one the fit test names.
- **Docs:** [UI controls](../godot/ui-controls.md), Deadnight #1175.
