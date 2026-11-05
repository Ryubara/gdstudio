---
areas: [godot-ui, input]
---
# Moving the stick's resting ring up moved the first-run hint over the cards

2026-11-05

- **Saw:** lifting the players' column by the weapon strip's height (Deadnight #1280) put the faint resting ring of the
  move stick over the points card by 17 units; raising `TouchLayout.STICK_REST` by 60 cleared it and
  `test_touch_hints` failed: "move on (2340.0, 864.0) covers scoreboard / the round_part card".
- **Cause:** the "DRAG TO MOVE" hint is placed from the ring (`TouchHints`), so one constant moves the ring, the hint,
  the stick zone's feel and whatever the hint now covers on the smallest canvas. The stick belongs to another issue
  (#1276), which edits the same file.
- **Fix:** the constant was put back and the overlap is reported to that issue; a layout change never moves a number
  another issue owns to make room for itself. Run the hints suite after any change to a layout constant.
- **Docs:** [Touch controls](https://github.com/Ryubara/deadnight/blob/main/docs/design/touch-controls.md) in Deadnight.
