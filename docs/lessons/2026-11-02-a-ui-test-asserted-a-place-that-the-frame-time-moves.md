---
areas: [tests, godot-ui]
---
# A UI test asserted a place that the length of a frame moves

2026-11-02

- **Saw:** in shuffled runs of Deadnight's `tests/ui` made while the machine was busy (my own parallel runs, about five
  Godot processes), `test_the_slide_dim_and_parallax_come_from_the_tokens` failed twice (2 assertions each). It passed
  in file order and when quiet. (`test_a_drag_from_the_aim_button_turns_the_view_and_keeps_aiming` failed once the same
  way, `-0.1225` against `-0.168 <> -0.128`; Deadnight #582 fixed it on main while this was open.)
- **Cause:** a bound with no room for a long frame, on a quantity set by the time the frames took. The
  slide test looked three frames into a transition whose tween is driven by the real frame time (at a 145 fps idle the
  screen was already 4.7 % of the way, `-0.4526` of the width against a bound of `-0.45`; with 100 ms frames it was
  75 % of the way, even at `Engine.time_scale = 0.002`).
- **Fix:** assert what does not depend on the frame length. The slide test no longer names a place: the position and the
  colour ride one tween, so the share the position shows must be the share the colour shows (it fails with another
  parallax or dim, checked by mutation, and passes with every frame slowed by 100 ms).
- **Check for next time:** reproduce a load flake by slowing every frame in a copy of the test
  (`OS.delay_msec(100)` after each `await process_frame`) and watch the old assertion fail; then assert a
  relation between two measures taken at the same moment, or a range from the tuning, not one value at a place the
  clock chose.
