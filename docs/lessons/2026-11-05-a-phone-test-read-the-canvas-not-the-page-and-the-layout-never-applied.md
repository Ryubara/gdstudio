---
areas: [godot-ui, web, tests]
---
# A phone test read the canvas, not the page, and the phone layout never applied on a phone

2026-11-05

- **Saw:** Deadnight's whole phone layout (`MenuScale`, the phone forms, the tap targets) had been tuned, tested
  (`test_ui_fit`, `test_level_ink`, the lobby fit) and captured at 844 x 390 and looked right. In the web export in
  Chromium as a phone (844 x 390 CSS pixels, pixel ratio 3, touch) the menu was the desktop's: a unit 0.36 CSS px, body
  text 7.9 to 9.4 px, tap targets 19 to 23 px, the panel 32 % of the page. The maintainer's own phone showed it; no
  check had.
- **Cause:** `MenuScale.is_phone` read the *window's* short side (under 500). A web page's window is its canvas in
  device pixels, and the page reports a pixel ratio of up to 2 (`PhoneRender`): an 844 x 390 page is a 1688 x 780
  window, short side 780, "not a phone". Every test and capture made a Godot window of 844 x 390, a canvas that no
  phone page has, so each result was true of a layout nobody reached. The earlier lesson on phone captures
  ([a phone capture without the phone scale](2026-11-05-a-phone-capture-without-the-phone-scale-showed-the-wrong-layout.md))
  had the right idea (say which scale a capture runs at) at the wrong level: it still counted pixels of a window.
- **Fix:** a phone is what the person holds, in CSS pixels. `PageSize` reads the canvas's box in CSS pixels from the
  page (`getBoundingClientRect`, so an iframe such as Discord's reports its own); `MenuScale.is_phone` is true for a
  window whose own short side is under 500 (native windows, a small desktop window at ratio 1: as it was) or for a
  touch device whose page's short side is under 500 CSS px. The layout is the same 1169 x 540 canvas at any pixel
  ratio, because the factor scales with the window. A desktop window, a tablet (744 CSS px and up) and a desktop build
  keep what they had, one test each (`test_page_size.gd`). Tests and captures name a page, not a window:
  `UiFitRun.set_window(size, scale, ratio)` puts a touch device and a CSS size behind a 1688 x 780 (ratio 2) or 2532 x
  1170 (ratio 3) canvas. **Measure what the person measures:** `UiAudit` reads the smallest text and tap target in CSS
  pixels, the web probe publishes it (`window.deadnight_audit`, `tools/web_smoke/phone_layout.py`), and a test fails
  under 14 and 44. Switching the layout on showed faults nobody had seen: sliders, toggles and fields 37.6 px high,
  the lobby's rules not in their phone form, the plate tabs at 10 px, a layout that did not follow a page turned under
  a covering screen, and the Play screen after Leave night left at the night's scale. Check for next time: for a rule
  about a device class, run the real device once (the web export in phone emulation, and in an iframe for Discord) and
  read the numbers there before trusting a fixture; say in a capture's name which page it is (`MenuScale.describe`
  prints it); a fixture of a size no real page has is allowed only where a test says so.
- **Docs:** [UI controls](../godot/ui-controls.md), [web export](../godot/web-export.md), Deadnight #1197.
