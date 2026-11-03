---
areas: [tests, input, godot]
---
# A "small steps" check on real frames failed when one frame outlasted the smoothing window

2026-11-03

- **Saw:** Deadnight #889: `test_a_100_unit_drag_turns_about_8_degrees_in_small_steps...` failed 3 of 5 runs on a busy
  machine, on clean `main` too, with "less than 1.0 but was 3.44" (the biggest turn of one frame, in degrees).
- **Cause:** the test sent 10 units a frame and waited one real frame each time; `LookSmoother` lets out a share of its
  backlog by the frame's length over a 40 ms window. On a quiet machine frames are about 6 ms and the backlog 27 mouse
  pixels is let out gently. One frame longer than the window (injected: `OS.delay_msec(120)`, a loaded machine does it
  by itself) lets out the whole backlog in that step. The game is right: the backlog is the finger's own movement and the
  total is the same (8.49 degrees with the hitch); a longer frame turns what is due.
- **Fix:** the test keeps its own clock like the drag-rate case (`set_process(false)`, `send_drag`,
  `_process(1.0 / 60.0)` by hand): the biggest step is 0.859 degrees every run. A second case sends a 120 ms frame and
  asserts the total only. 20 of 20 pass beside three looping `tests/ui` runs; a 20 % change of `radians_per_height` or
  of the sensitivity setting still fails the case.
- **Check:** a bound on the size of one frame's turn is measured on frame lengths the test chooses, never on real
  frames; a hitch is a case of its own that asserts the total.
- **Docs:** the earlier
  [drag-rate lesson](2026-11-03-a-rate-test-paired-each-turn-with-the-previous-frame-s-length.md) is the same family.
