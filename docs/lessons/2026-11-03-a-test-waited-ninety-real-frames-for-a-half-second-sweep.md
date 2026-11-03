---
areas: [tests, godot]
---

# A test waited 90 real frames for a time-based sweep and a fast runner stopped at 93%

- **Symptom:** Deadnight #802 passed locally and failed in CI: `test_the_skin_sweeps_on_in_the_hand_when_the_re_cut_is_bought`
  expected the skin's reveal to be 1.0 after `await get_tree().process_frame` 90 times and read 0.934.
- **Cause:** the sweep advances by each frame's delta (0.7 s in all). A headless runner draws no picture, so 90 frames
  took about 0.65 s there and 1.5 s or more on a desktop: the test counted frames and assumed a frame time.
- **Fix:** give the animation its time by hand, `animation._process(seconds)` with the style's own length (the same rule
  as the drag-rate lesson), and assert relative to the start (`greater(begun)`, then `equal(1.0)` after more than the
  whole length). Never count real frames for something that runs on a delta.
- **Documented:** this lesson; the tests page rule is "the test keeps its own clock".
