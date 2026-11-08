---
areas: [godot-ui, godot]
---
# A `move_child` in a fit method was refused while the row was setting up its children

2026-11-05

- **Saw:** `ERROR: Parent node is busy setting up children, move_child() failed` from `HudSlots._order_tag`, called by
  `_fit_touch_cells` from a night's `_on_night_over`, in `test_night_tap_targets`; the move did nothing.
- **Cause:** the fit method runs from signals (a part's `visibility_changed`, the night's events) that can arrive while
  the container is inside a child-setup pass, and `move_child` is refused then.
- **Fix:** move only when the child is not at its place, and with `move_child.call_deferred(child, index)`. Run the
  suites of the other screens that build the part (the night's tap-target suite found it, not the touch suites).
- **Docs:** [Touch controls](../engines/godot/ui-controls.md#touch-controls).
