---
areas: [tests, godot-ui]
---
# A phone capture without the phone scale showed the wrong layout and read as proof

Note (Deadnight #1197): the 844 x 390 window this lesson reads is a canvas no phone page has; on a web page the window
is twice the CSS size and the phone layout did not apply at all. See [a phone test read the canvas, not the
page](2026-11-05-a-phone-test-read-the-canvas-not-the-page-and-the-layout-never-applied.md).

2026-11-05

- **Saw:** Deadnight #1071's capture of the equip screen at 844 by 390 showed the full-height layout (overline, big
  tabs), although the same screen had just been changed for short screens; a second capture, made after the change,
  still did. Only the layout test (`test_ui_fit`, which sets the scale) knew the screen was short.
- **Cause:** the game gives a phone's window `content_scale_factor = MenuScale.factor(window.size, ui_scale)`, so a
  phone lays out on a 1169 by 540 canvas. A capture scene that does not set it is a 1920 by 1080 design canvas shrunk to
  the window: the right pixels, the wrong layout, and nothing says so.
- **Fix:** every capture that takes phone shots sets the factor *the screen under test really runs at* (then one
  frame) before it builds the screen: a menu or the lobby has `MenuScale.factor(window.size, 1.0)` (2 on a phone), but a
  night has the interface size alone (`NightScreen._ready` puts it back), so the HUD on a phone is about 0.36 px to the
  unit, half the menu's 0.72. "Phone scale" is not one number: ask which screen it is, then read what it sets
  (Deadnight #1181 read the HUD at the menu's factor first). Check for next time: after a phone capture, read the layout
  (is the short variant on show?), not only the pixels, and compare the canvas size in the capture with the one the fit
  test, or the screen's own `content_scale_factor`, names.
- **Docs:** [UI controls](../engines/godot/ui-controls.md), Deadnight #1175.
