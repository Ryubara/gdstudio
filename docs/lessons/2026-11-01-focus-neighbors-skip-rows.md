---
areas: [godot-ui, input]
---
# Arrow keys from a tab strip skipped the page's rows

2026-11-01

- **Saw:** on a settings screen, Down from a tab button focused the footer's Reset, never a row, so a keyboard or
  gamepad player could not reach the controls.
- **Cause:** Godot picks the next focus by geometry: the footer sits straight below the left-aligned tab, the rows are
  in a column to the right. A tab switch also hides the focused control, which drops focus to null.
- **Fix:** set `focus_neighbor_*` by hand on the ends of the column (strip, first row, ..., last row, footer), refresh
  them on every tab switch, and grab focus on the new tab's button. Test with `find_valid_focus_neighbor` after two idle
  frames (it needs a layout).
- **Docs:** [UI controls](../engines/godot/ui-controls.md); Deadnight `docs/research/settings.md`.
