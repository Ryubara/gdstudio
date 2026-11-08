---
areas: [godot-ui]
---
# A container put its child's scale back to one, so a ticket shrunk to fit stayed whole

2026-11-05

- **Saw:** Deadnight #1287 shrank the scoreboard's ticket with `scale` to keep it off the touch buttons. The fit
  maths said 0.65; a probe of the ticket's rectangle (`get_global_transform() * Rect2(Vector2.ZERO, size)`) said 1.0
  and the ticket drew whole, over the buttons.
- **Cause:** the ticket stands in a `CenterContainer`, and a container's `fit_child_in_rect` sets its child's rotation
  to 0 and its scale to 1 every time it sorts. The property I set was reset on the next layout.
- **Fix:** scale (and move) the holder, which is a plain `Control` of the HUD and not managed by a container, about
  its middle (`pivot_offset`); the ticket in the middle of it follows. `Hud._fit_board`, Deadnight.
- **Check for next time:** to scale or move something a container holds, change the node above it or give the
  container an offset; read the result back from the global transform in the test, not from the property.
- **Docs:** [UI controls](../engines/godot/ui-controls.md).
