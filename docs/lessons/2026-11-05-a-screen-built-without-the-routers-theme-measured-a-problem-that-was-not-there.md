---
areas: [tests, godot-ui]
---
# A screen built without the router's theme measured a problem that was not there

2026-11-05

- **Saw:** Deadnight #1161's pixel test showed the lobby's framed seat with its icon covered by the frame (8 of 24 units
  gone). A margin of 9 units above and below each framed seat "fixed" it and made a lobby of eight framed seats 144
  units taller (827 to 971 units left to scroll at 1080p). The real lobby never had the fault.
- **Cause:** the test added the screen to a bare `Control`. The router's stage gives every screen the game's theme
  (`UIRouter` sets `stage.theme`); without it the seat labels are Godot's default font and a row is 24 units high
  instead of 45, so the frame's 7 units sat on the icon. A reading of pixels is only as true as the layout it reads.
- **Fix:** a test that builds a screen itself gives its host `UIThemeBuilder.build(UITokens.active())`, or opens it
  through `UIRouter` like `UiFitRun` does; the margin is gone and `test_lobby_framed_fit.gd` holds a framed lobby of
  eight to the height of a plain one. Check for next time: before fixing a layout fault a test found, compare the
  test's row height or font size with the real screen's (a fit run or a capture through the router) and that the fault
  is on screen in the game, not only in the fixture.
- **Docs:** [UI controls](../godot/ui-controls.md), Deadnight #1181 (`docs/research/level-badge-alignment.md`).
