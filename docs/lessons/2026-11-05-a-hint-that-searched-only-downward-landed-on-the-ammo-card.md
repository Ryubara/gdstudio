---
areas: [godot-ui, input]
---
# A hint that searched only downward for a free place landed on the ammo card

2026-11-05

- **Saw:** after Deadnight #1277 moved the touch buttons, CI failed `test_popup_lane` at the 1536 x 864 canvas: "look
  [P: (1004, 697.6)] covers Ammo", both hands, with and without a boss card. My local run had not included that suite.
- **Cause:** `TouchHints._below_the_buttons` slid the first-run "DRAG TO LOOK" hint down from its place until no
  button was under it. A new button ring left no gap for 60 units below, and the first free place was 520 units
  down, on the HUD's ammo card, which the search knows nothing about.
- **Fix:** the search tries the nearest free place up or down (a few units up cleared it) instead of only down.
  The test was not loosened. Run the whole `tests/ui` folder, in parts, before pushing a layout change: the hints,
  the lane and the marker cards each read the buttons' places.
- **Docs:** [Touch controls](https://github.com/Ryubara/deadnight/blob/main/docs/design/touch-controls.md), Deadnight.
