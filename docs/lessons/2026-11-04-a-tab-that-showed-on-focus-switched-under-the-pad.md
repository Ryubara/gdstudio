---
areas: [godot-ui, input]
---
# A tab that showed its page on focus switched the page under the pad

2026-11-04

- **Saw:** a gamepad test walked down from a tab into the wardrobe's grid and up again, and ended on another tab with
  that tab's page showing (`'legs'` expected, `'hair'` found).
- **Cause:** the strip showed a page whenever a tab took the focus, and Up from the first row of the grid went to the
  engine's nearest control above, which was the tab over that cell, not the tab the player had come from.
- **Fix:** a page shows when its tab is pressed; the first row of the grid links Up to the tab on show (set in a
  deferred call after each `sort_children`, since the rows exist only after the layout) and the tabs link Down to the
  page's first cell. The pad test checks both ways and that walking along the strip changes the focus, not the page.
- **Docs:** [A grid of items with locked silhouettes](../godot/ui-controls.md#a-grid-of-items-with-locked-silhouettes).
