---
areas: [godot-ui, tests]
---
# A plate sized once at build stood over the last tab on the narrowest phone page

2026-11-05

- **Saw:** on the 667 x 375 page (960 x 540 units) the menu's tab bar read "MOR": the account plate covered 29 units
  of MORE. `test_ui_fit` and `test_phone_floor` were green, the plate and the bar are both 44 px tall, and a tap on
  the covered end still opened the tab (the plate ignores the mouse), so no floor test could say it was wrong.
- **Cause:** `MenuShell` sized the plate once, in `_build_chrome`, from `get_viewport_rect()`. A menu built under a
  screen that is not shown yet runs `_ready` before the phone factor is on the window, so the canvas was still 1920
  units wide and the plate took its whole 372. Every test set the window, and the factor, first and then built the
  shell, so the order the page has was never run.
- **Fix:** the plate lays itself out again whenever the canvas may have changed (`MenuPlate.fit`, called when the
  factor is set and on `resized`), and the tests build the shell hidden, on a window at the interface size, and show
  it a frame later. The web probe publishes `header_overlap` and `phone_layout.py` fails on it. Deadnight #1271.
- **Check for next time:** a size computed from the canvas is computed again when the canvas changes, not once at
  build; a layout test builds the thing in the page's order (hidden, at the interface size, then shown), and compares
  the rectangles of neighbours (`intersects`), because a height or a text size does not show a cover.
- **Docs:** Deadnight `docs/research/phone-page-scale.md` (the tab bar and the Loadout card on the narrowest page).
