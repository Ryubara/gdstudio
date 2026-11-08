---
areas: [godot-ui, tests]
---
# A card over a night needed the phone factor of its own, and everything that sized it read the window

2026-11-05

- **Saw:** Deadnight's pause card and the Settings opened from it were 0.36 CSS px to the unit on a phone page (card text
  11.6 px, Settings text 9.4 px, its sliders and selectors 18.8 px high), while the menu's screens were at 0.72. The night
  must keep the window's factor at the interface size (its HUD and touch layer are made for 1080 units), so the factor
  of the window could not be raised for the pause.
- **Cause:** a screen drawn over a night takes the night's scale, and its layout rules read the window, not the screen:
  `UIFitScroll` took the viewport's height as its room, `MenuScale.tap_units` took the window's pixels per unit, and
  `UiAudit` multiplied by the window's stretch alone. A control drawn at `scale = 2` has half the canvas it appears to
  have, and each of those still said 1080 units.
- **Fix:** a control that is the factor of a part: `PhoneScale` (scale 2, size = holder / 2, asks `MenuScale.is_phone`
  again on `size_changed`) holds the card and the Settings; the Settings sees 540 units and takes its phone form,
  `UIFitScroll.limit` is the screen, `tap_units(window, touch, inner_scale)` divides by the part's scale and `UiAudit`
  multiplies by the control's global scale. Godot draws the scaled text sharp. A test and a probe measure the part
  alone (`NightScreen.card_root`), because the HUD behind it is another page's. Two traps on the way: a test that sets
  the window's size and then the page's CSS size (`UiFitRun.set_window`) lets `size_changed` run with the old page, so
  the part has to be told to ask again; and `git stash` is refused by the hooks, so a "before" build is a
  `git archive HEAD` in the scratch folder. Check for next time: a part drawn at a scale of its own is measured by its
  own size and its global scale, never by the window's or the viewport's; run the failing test against main's files
  (`git archive`) before calling it a test of the fix.
- **Docs:** [UI controls](../engines/godot/ui-controls.md), Deadnight #1205 and its `docs/research/phone-page-scale.md`.
