---
areas: [godot-ui, tests]
---
# A HUD overlapped itself only at one window size and UI scale

2026-11-01

- **Saw:** captures at 1080p and 1440p were clean; a test that built the busiest HUD at every canvas the stretch and UI
  scale can give found 17 overlaps at 1536 x 864.
- **Cause:** the canvas is 1920 / ui_scale wide, and content-driven columns (long text, wide rows) grew until they met
  the centre parts. Short test values hide it too: test with the longest names and numbers and the widest font.
- **Fix:** fix widths for text rows (wrap or trim), cap list lengths, and keep the test: every visible part's
  `get_global_rect()` is inside the canvas and disjoint from the others.
- **Docs:** [UI controls](../godot/ui-controls.md); Deadnight `docs/design/hud.md`.
