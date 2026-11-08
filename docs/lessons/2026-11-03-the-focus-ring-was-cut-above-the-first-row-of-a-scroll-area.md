---
areas: [godot-ui]
---
# The focus ring was cut above the first row and below the last of a scroll area

2026-11-03

- **Saw:** In the lobby the focused "Share in Discord", the last row, lost the bottom 9 units of its ring
  (Deadnight #644). The hover fix a day before (#628) had left exactly this open.
- **Cause:** The theme made room at the sides of every `ScrollContainer` and not above and below, because the lobby's
  `_fit` and the credits' `_scroll_end` computed heights from the content and a vertical margin would have broken them.
  The sweep only grew the ring sideways, so it never looked at the other two sides either.
- **Fix:** The margin is on all four sides (`UITokens.scroll_room` above and below), and the two sums read the area:
  `_fit` adds `UIScroll.margins(scroll)`, `_scroll_end` reads the bar's `page`. The sweep grows the ring on every side
  and failed on main first (9 failures in the lobby); a test of the only row of an area and one of the lobby's last
  row keep it measured. The margin alone was not enough: a sweep that only scrolls to the top, end and middle
  missed that `follow_focus` stops flush at the control's edge, so a row reached with Down kept a cut ring; a listener
  on the focus scrolls the rest of the way and a walk of the focus over every button (failed first) measures it.
  A shortcut taken in a shared rule ("the sides only") is a line in the
  issue list the same day.
- **Docs:** [UI controls](../engines/godot/ui-controls.md#a-control-that-draws-outside-its-rect).
