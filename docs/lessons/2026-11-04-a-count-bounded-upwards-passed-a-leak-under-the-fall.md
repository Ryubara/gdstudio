---
areas: [tests, audio]
---
# A count test bounded upwards let a leak through under the fall of the last night's sounds

2026-11-04

- **Saw:** after #1134 the four other tests that count objects across frames (`test_zombie_pool`, `test_grenade_trail`,
  `test_shot_effects_pool`, `test_hud_shapes`) had never failed, so they looked safe (Deadnight #1138).
- **Cause:** they bound the count upwards (`now - start <= SLACK`, a peak against a start), so sounds that end during
  the count lower it and the test still passes: the fall is a free allowance for a leak. With 12 sounds left playing
  and a leak injected on purpose: the zombie pool fell 16 to 20 and passed a 12 object leak (slack 6) in 2 of 2 runs;
  the grenade test fell 3 to 5 and passed a 3 object leak in 1 of 2 runs, a flake in the direction that hides; the
  shot effects test hid a 10 object leak (slack 4) only with 60 sounds left (12 had ended before its baseline).
- **Fix:** `await QuietCount.settle(get_tree())` before the baseline: the same runs failed on the leak 3 of 3 times,
  with the same numbers each time. A scan test (`tests/core/test_object_count_settle.gd`) fails a suite that reads
  `Performance.OBJECT_COUNT` and awaits frames without it. `SLACK` and `JITTER` unchanged.
- **Rule:** a green count test that has never failed has not shown it can; before calling one safe, inject a leak
  of 2 to 3 times its slack with sounds left playing, and see it fail. An upward bound needs the settle as much as a
  two-sided one: the fall is the opposite of the flake and costs the test its teeth.
- **Docs:** [Performance review](../engines/godot/performance-review.md), "How to measure it"; the lessons before it:
  [a count fell while the sounds ended](2026-11-04-a-count-fell-while-the-last-night-s-sounds-ended.md),
  [a count test read a peak](2026-11-04-a-count-test-read-a-peak-while-the-fight-and-the-menu-kept-moving.md).
