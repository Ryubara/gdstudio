---
areas: [godot-ui, tests]
---
# Menu panels ran under the footer's key hints because nothing bounded them

2026-11-04

- **Saw:** the maintainer pointed out that no container should be too tall or run under the footer's key hints
  (Deadnight #980). The Loadout tab's wardrobe ended 47 units under the
  hints on a 1080 canvas and past the right edge of the screen; on a phone (a 372-unit panel) it was 757 high and
  1020 wide. The Settings screen was 741 to 1103 units high and 1280 wide, Play together 897 high, Join 599, the
  Quick join card 975 high on a failure, on a canvas of 540 by 960 to 1170.
- **Cause:** each panel was a column (`VBoxContainer`, full rect) in a `Control`, or a card in a `CenterContainer`:
  a container grows to its content, and nothing clips or scrolls it, so a column taller than its area just
  runs past it. The wardrobe's scroll list had a fixed minimum height (640), its rows a minimum width (786 to 886)
  that no panel of 900 or 818 holds once the theme's scroll room is added, the Settings card a fixed 1200 width.
  Every test looked at one screen at one size, or at the controls' own states (hover, focus), never at "does this
  screen stay inside its area" at each canvas.
- **Fix:** a sweep: open every screen and tab at every size, and fail on any control whose shown rectangle crosses the
  screen's edge, its panel, the header or the footer, or is cut where it cannot scroll (`UiFit`, `UiFitRun`,
  `test_ui_fit.gd`); it failed 167 and 64 times on `main`. Then the parts: `UIFitScroll` bounds a card, `MenuPanel.hold`
  scrolls a tab's column, the wardrobe's list flexes in the height it is given and its rows stack on a narrow tab, the
  Settings card caps its width and scrolls its rows, the name plate takes what the tab bar leaves.
- **Docs:** [UI controls](../engines/godot/ui-controls.md#a-card-taller-than-its-screen); Deadnight
  `docs/research/menu-shell.md`.
