---
areas: [godot-ui, input, web]
---
# A tap size gated by the window's pixels missed the real phone page

2026-11-05

- **Saw:** Deadnight #1192 made the night's Leave and pause buttons 44 px high "on a phone", with tests at an 844 x 390
  window and `MenuScale.is_phone(window.size)` as the switch. They passed. The coordinator then pointed out that a real
  phone page is 844 x 390 CSS px at a pixel ratio of 2: the engine's window is 1688 x 780, which is not "a phone" by
  the menu's short-side test (780 is over 500) and 44 window px there are 22 CSS px.
- **Cause:** a size a finger meets is in CSS px, and the test and the switch were in window px. A headless window of
  844 x 390 happens to have a ratio of 1, so every check agreed with itself.
- **Fix:** the least size is `MenuScale.TAP_PIXELS` CSS px times the page's ratio over the pixels to a unit; the switch
  is `TouchMode.wanted` (a finger is the pointer), not the window's size; tests run pages of 1688 x 780 at ratio 2 and
  read CSS px, a capture runs at `--resolution 1688x780`, and `tools/web_smoke/night_taps.py` reads the exported page's
  buttons (44.1 CSS px) and presses one with a real touch at its edge. Check for next time: for any phone size or
  tap target, say which pixel the number is in (units, window px, CSS px), and run one case at the real page's size
  (ratio 2) before calling it done.
- **Docs:** Deadnight `docs/research/mobile-controls.md` (Tap targets in a night); see also the lesson on a phone test
  that read the canvas and not the page.
