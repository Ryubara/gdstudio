---
areas: [godot-ui, tests]
---
# A button that held a container was 8 units tall and the rows under it stood on each other

2026-11-04

- **Saw:** Deadnight #1073, a poster set on the Challenges tab built as a focusable `Button` (so a pad walks the list)
  with a `MarginContainer` of rows and a poster inside it. Both sets drew at the same place, one over the other. A
  probe said the button was 974 by 8, and `body.get_combined_minimum_size()` was 0 right after building it and 1,901
  tall once in the tree.
- **Cause:** three things at once. A `Button` is not a container: it never asks its children how tall it is
  (`_get_minimum_size` in a script is not consulted on a native `Button`), so its height is its own minimum. A container
  built outside the tree reports zero. And a `Label` with `autowrap_mode` reports a minimum height for the width it has
  *now*, which is nothing before the first layout: one word a line, 1,900 units. Setting `custom_minimum_size.y` from
  `_ready` also did not move the list (its sort had run with the old size); only a `queue_sort` after the settle did.
- **Fix:** lay the height out by hand from the fonts (`font.get_height(size)` times the lines, the rows, the poster),
  a few units over and never under, set before the node is added; break a title into lines with `get_string_size` and
  put `\n` in the text instead of autowrap. A test reads each view's `size` and that the next view starts below it.
- **Docs:** [UI controls](../godot/ui-controls.md) (a button holding a container) and Deadnight's
  `docs/research/calling-cards.md#poster-sets-1073`.
