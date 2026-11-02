---
areas: [tests, input, camera]
---
# A drag test expected one turn while a time-based ease still scaled the look

2026-11-02

- **Saw:** Deadnight `test_a_drag_from_the_aim_button_turns_the_view_and_keeps_aiming` failed on `main` and on branches
  with no related change (#576): the view turned 0.112 to 0.125 rad where the test expected 0.148 within 0.02. It also
  failed on an idle machine, so "it fails under load" was only partly right.
- **Cause:** the issue blamed the touch look's flick gain. It was not that: a finger's first three drags have a zeroed
  velocity, so the gain is 1. The aim button also steadies the look: the camera rig scales every mouse motion by
  `lerp(1, aim_sensitivity_scale, aim_amount)`, and `aim_amount` is a damped spring stepped by the frame's `delta`. The
  drag lands a frame or two after the press, so the scale is anywhere from 1.0 to 0.7 depending on the frame times.
  The test asserted one point of a range that a clock sets.
- **Fix:** assert the range the ease allows (`hip_turn * aim_sensitivity_scale` up to `hip_turn`, read from the player's
  tuning), not a point. Proved with two mutants: the aim button's drag turning nothing (0.0) and the look doubled
  (0.296 or 0.245) both fail; 40 runs of the whole touch folder, four at once, passed.
- **Check for next time:** before blaming the code under test's own timing, list every time-stepped value between the
  input and the asserted number (springs, eases, blends in the rig), and read the first failing number back through
  them (0.112 / 0.148 = 0.756, between 0.7 and 1). Assert the range those allow, or snap the ease first, and prove the
  test with a mutant that turns nothing.
- **Docs:** the test's own comment, and `game/tests/ui/touch/test_touch_player.gd` in Deadnight.
