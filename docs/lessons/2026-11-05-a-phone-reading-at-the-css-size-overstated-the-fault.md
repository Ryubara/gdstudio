---
areas: [tests, godot-ui, web]
---
# A phone reading taken at the page's CSS size overstated the fault by half

2026-11-05

- **Saw:** Deadnight #1161 read the HUD on a phone in a window of 844 by 390 (0.36 px to the unit in a night) and the
  issue it opened (#1189) described words "nearly unreadable". The coordinator pointed out that a real phone page is
  844 by 390 CSS pixels at a pixel ratio of 2 (the web export caps it): a canvas of 1688 by 780, 0.72 px to the unit,
  and 2532 by 1170 (1.08) is a real size too.
- **Cause:** a window of the page's CSS size is the page at a pixel ratio of 1; the phone's canvas is the CSS size
  times the ratio. The reading was taken at the size on the phone's spec sheet, not the canvas the game draws on.
- **Fix:** read a phone at the canvas (1688 by 780 and 2532 by 1170) and keep 844 by 390 as the pixel ratio 1 worst
  case. Measured both ways: at 1688 by 780 the red seat's strongest pixel was 1.81 at its worst (1.31 at 844 by 390)
  and 105 of 408 words were under 4.5 (254): smaller, and still a fault. A fix is judged at the real canvas and the
  worst case is only reported; the heavier type chosen for 0.36 px per unit is off at 0.72.
- **Docs:** [UI controls](../engines/godot/ui-controls.md#reading-a-screen-under-test-the-scale-it-really-runs-at); Deadnight
  `docs/research/plate-words-contrast.md`.
