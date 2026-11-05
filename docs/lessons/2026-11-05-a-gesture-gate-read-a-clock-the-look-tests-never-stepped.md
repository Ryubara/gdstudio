---
areas: [input, tests, godot-ui]
---
# A tap gate on the look read a clock the look tests never stepped

2026-11-05

- **Saw:** Deadnight #1288 holds a touch on free ground back from the look while it can still be one tap of a double
  tap (under 250 ms, inside 10 CSS px). Three smoothness tests of `test_touch_player.gd` went red: a steady 40 unit a
  second drag had 54 frames with no turn and a rate variation of 1.89 (the limit is 0.35), and a 100 unit drag made a
  1.06 degree step (the limit is 1), because the drag sat in the gate for its whole run.
- **Cause:** those tests play time by hand (`controls.set_process(false)`, then `_process(1/60)` per step), so a real
  250 ms never passes in them; the gate read `Time` and so never timed out. A test that wants the boundaries to the
  millisecond has the opposite need: a real frame in its clock moves a 350 ms edge by a few milliseconds.
- **Fix:** the layer's clock is a `Callable` (`TouchControls.clock`, real `Time` in the game). `TouchFixture` hands every
  suite the layer's own stepped time plus a `pass_time` offset, so a hand-stepped drag and a test of the gate share one
  time; the double tap suite alone uses a pure test clock for its 250 and 350 ms edges. Check for next time: a rule
  that reads time or distance in the touch layer needs a clock and a slop a test can set, and every suite that plays a
  drag runs with the rule on (`tap_slop` 28 units, a phone's night), not switched off.
- **Docs:** Deadnight `docs/research/mobile-controls.md`, "The double tap that changes shoulder (#1288)".
