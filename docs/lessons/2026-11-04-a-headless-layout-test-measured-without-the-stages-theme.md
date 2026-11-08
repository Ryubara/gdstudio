---
areas: [godot-ui, tests]
---
# A headless layout test measured without the stage's theme and "could not see" overflows

2026-11-04

- **Saw:** three lessons and a page said "a headless run measures text as nothing", so a fit test of a screen passed on
  layouts a phone cut off; a Play screen test carried a 100-unit "headless text allowance" and the capture tour was the
  only judge. A title label was 23 units high in a test and 83 in a window.
- **Cause:** not the headless run. The tests built the screen under a bare `Control` (a holder, a `CanvasLayer`), and
  the theme (type sizes, fonts, the scroll areas' room, the bars) comes from the router's stage
  (`UIThemeBuilder.build(UITokens.active())`). Without it a label has the engine's default 16 px font. With the theme
  a headless run printed the same sizes and rectangles as a window, to the unit (the Deadnight fit sweep, run both
  ways at 844 x 390: the same problem lines, word for word).
- **Fix:** open a screen through the router (`UIRouter.reset`), or under a `Control` whose `theme` is
  `UIThemeBuilder.build(UITokens.active())`, and a headless GdUnit test is a real layout test: Deadnight's
  `UiFitRun` does, and `UiFit` asks every control whether it crosses its area, the footer, the header or the screen.
  Keep a capture for the eyes, not for the numbers.
- **Docs:** [UI controls](../engines/godot/ui-controls.md#a-card-taller-than-its-screen).
