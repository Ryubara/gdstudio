---
areas: [godot-ui, tests]
---
# A lane in a HUD column jumped when its neighbour left, and a test measured it before the column had laid out

2026-11-04

- **Saw:** Deadnight's popup lane (#1064), put last in the top-middle column under the round banner, moved up by the
  banner's whole height the frame the banner left, and with a banner and a boss bar up its third card was over the
  crosshair box. A first layout test measured a banner 772 units high and a column of width 0.
- **Cause:** a container places its children a frame late, so a rectangle read in the frame a part was added or shown
  is not where it will be; and a part that must stay clear of something (the crosshair) cannot take its room from the
  container it sits in.
- **Fix:** put the lane beside the column, not in it, and ease it to the bottom of whichever neighbours are up (read
  only once their column has a width); give the queue the room down to the crosshair box and start a card only when
  it fits. In tests, `await await_idle_frame()` before measuring or stepping, switch the part's own `_process` off so
  the awaited frames do not move it too, and measure at every canvas, with the busiest neighbours up, against every
  part of the HUD and the crosshair box.
- **Docs:** the game's `docs/research/popup-lane.md` (Deadnight, #1064).
