---
areas: [godot-ui, tests]
---
# Two UI tests passed on their own branch and went red only after merging another layout change

2026-11-05

- **Saw:** Deadnight #1280 was green on its own, then merging #1283 (a new ring of touch buttons) turned two tests red:
  `test_hud_marker_cards` (two of eight markers met on the 667 x 375 page) and `test_touch_weapon_places` (a count of
  boxes expected 15, found 14).
- **Cause:** each test had a number that came from the layout as it was: a marker capacity of eight, and a box count
  taken as "every circle plus three places", which forgot that a hidden Interact button draws no box. Neither number was
  derived from the thing it counts, so a change elsewhere moved it without any edit to the test.
- **Fix:** the count is now derived (circles minus the hidden Interact, plus the places), and the small phone's marker
  capacity is a named constant with the reason written next to it (`CROWDED_HOLDS`). Run every suite of the folder the
  change touches (all of `tests/ui` in parts) after a merge, not only the suites of the change: the red one was found
  by the full run.
- **Docs:** the mistakes glossary (`gds lessons <area>`), area `tests`.
