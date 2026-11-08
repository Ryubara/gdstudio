---
areas: [godot-ui, tests]
---
# A new row pushed a form off a phone held sideways

2026-11-03

- **Saw:** the map picker (two stacked cards, 74 units each) added to Deadnight's Play screen. On a desktop window
  it looked right, and every headless test passed, including one that checks each control sits inside a 1168 by 540
  canvas. The capture tour at 844 by 390 (real fonts) printed `fit: 12 controls outside the window`: the panel was 632
  units high on a 540 unit canvas.
- **Cause:** the phone's canvas is 540 units high and the screen before the change used about 510 of them: it had no
  spare height for any new row, let alone one taller than a tap target. A headless run measures text as nothing, so
  its layout test cannot see the overflow (the test window is 64 pixels and rows have no text height); only a window
  with real fonts shows it.
- **Fix:** design the phone form first and budget its height: the cards sit two to a row (`GridContainer`, columns 2),
  so the row is one card high; the picker, the form and the screen drop their gaps from 16 to 8 units and the margins
  above and below to 8. Re-count focus neighbours after the columns change (Up from either card of the first row
  leaves the form, Left and Right walk a row). Run the capture tour at `--resolution 844x390` before reporting, and
  keep its fit check: it prints what lies outside the window.
- **Docs:** [UI controls](../engines/godot/ui-controls.md#a-picker-of-cards-in-a-form-row); Deadnight
  `game/tests/captures/map_picker_tour.gd` and `docs/design/maps.md`.
