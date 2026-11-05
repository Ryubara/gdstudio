---
areas: [godot-ui, input]
---
# A hidden button took the smallest page's column from the world markers

2026-11-05

- **Saw:** Deadnight #1277 moved the touch buttons and `test_hud_marker_cards` went red in 18 places on the 667 x 375
  page at interface size 1.25: markers "under" the health card and the banner, none placed.
- **Cause:** the markers keep clear of `TouchControls.button_boxes()`, and that listed the interact button even while
  it was not drawn. Its new place was the farthest from the edge (716 units against 617), and the one column left
  between the cards and the buttons on that page had 25 units to spare (344 for 319 of words).
- **Fix:** `button_boxes` leaves a hidden button out and the layer emits `layout_changed` when the button comes or
  goes, so the markers settle again; the test's own list does the same and a second test puts the button up on the
  smallest page. A layout change that adds width on the buttons' side is checked on that page first.
- **Docs:** Deadnight `docs/research/mobile-controls.md`, "The right side".
