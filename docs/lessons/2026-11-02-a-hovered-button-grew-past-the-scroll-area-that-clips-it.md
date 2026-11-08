---
areas: [godot-ui]
---
# A hovered button grew past the scroll area that clips it

2026-11-02

- **Saw:** In the lobby the hovered "Copy the link" grew and its left edge was cut off by the panel's side
  (Deadnight #628). The maintainer pointed out that nobody had considered the clipping a scale-up causes.
- **Cause:** A scale is paint, not layout: `UIButton` grew 3.5 percent on hover and no container reserved room for it,
  while the lobby's rows sat in a `ScrollContainer` (which clips at its own rectangle) with every button filling the
  width edge to edge. Layout tests read resting rects, so nothing measured a hovered control against the control that
  clips it. A ring or shadow drawn outside the rect is cut the same way.
- **Fix:** Two shared rules, no screen touched: the button grows only by the room it has inside its nearest clipping
  ancestor (per axis), and the theme keeps `hover_room` free at the sides of every `ScrollContainer`. A sweep test hovers
  every button of every menu screen at 720p, 1080p and the phone canvas, scrolled to the top, end and middle, and
  fails when the grown rect leaves its clipper; it also asserts the buttons still grow, or a guard that shrinks them to
  nothing would pass.
- **Docs:** [UI controls](../engines/godot/ui-controls.md#a-control-that-draws-outside-its-rect).
