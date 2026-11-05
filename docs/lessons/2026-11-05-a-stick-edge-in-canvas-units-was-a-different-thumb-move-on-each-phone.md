---
areas: [godot-ui, input, tests]
---
# A stick's sprint edge in canvas units was a different thumb movement on each phone

2026-11-05

- **Saw:** the move stick's ring was 105 canvas units and the sprint edge a share of it. A phone's night is 1080 units
  tall whatever the page is, so the same ring was 36 CSS px at 667 x 375 and 38 at 844 x 390, and a margin past the edge
  would have been 3 to 5 percent more thumb on one phone than the other. After the ring moved to CSS pixels
  (111 units, not 105), `tests/night/test_input_matrix.gd` failed all nine tests: its pushes of 70 and 150 units had
  been tuned to the old ring (70 units no longer reached the 0.5 the night's command needs; 150 no longer passed the
  sprint edge), and no suite beside the touch ones had been run.
- **Cause:** a distance a finger travels is physical, so it belongs in CSS pixels of the page (`MenuScale.css_per_unit`,
  as `TouchSlop` and `tap_units` already do); in units it follows the canvas. And a constant moved in a shared class has
  consumers in suites that never name it.
- **Fix:** `TouchTuning.stick_radius_px` and `sprint_margin_px` in CSS pixels, turned into units at each use
  (`TouchControls.stick_radius`), measured on a real page at both sizes (40.0 and 58.0 CSS px each). Before pushing a
  change to a shared geometry constant, grep `tests/` for the constants' consumers (`grep -rln "STICK_\|stick_"`) and run
  those suites, not only the folder of the file. A browser probe that reads a speed finds a wall within seconds of
  walking one way: change direction between steps and assert only what a short hold can show.
- **Docs:** the game's `docs/research/mobile-controls.md`, "The stick's sprint latch".
