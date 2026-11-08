---
areas: [tests, audio, ci]
---
# The settle test's object count fell by 5 and 8 while the suite before's sounds ended

2026-11-04

- **Saw:** `test_audio_settle` failed `godot (3)` on a UI pull request (`objects 6541 -> 6536`) and `godot (4)` on an
  art one (`5487 -> 5479`), passing on a rerun; the test allows 2 and neither pull request touched audio (Deadnight
  #1134). Both falls were downward, so nothing was leaking.
- **Cause:** the suite before it (`test_night_challenges`, a real night) leaves sounds playing on the `Audio` autoload
  (8 playing when the test starts, locally). Each one that ends frees its engine playback, a few objects, in a frame of
  its own, so the count drifts down across the test's 30 frames, 3 to 10 at a time, whatever the frame time (a 3 s
  stall did not flush them). The test called `AudioSettle.until_idle`, which only ends the background load and the
  decode queue, and not `QuietCount.settle`, which stops voices and waits for the mixer: the same gap the two lessons
  before it closed in other tests. Reproduced locally in the shard's order (bots, challenges, character suites, then
  this one): 3 of 3 runs failed by 3.
- **Fix:** the test calls `QuietCount.settle` first (after starting 12 sounds itself, so it fails alone without the
  settle: -10, and passes with it). Failed first: shard 3's first 15 suites in CI order, 3 of 3 runs failed before,
  20 of 20 passed after. `JITTER` unchanged.
- **Rule:** a test that counts objects across frames calls both waits, `AudioSettle.until_idle` (queues and loads) and
  `QuietCount.settle` (voices, tweens, the mixer), and brings its own leftover sounds when it claims to be immune to the
  suite before; to find which suite makes a count move, run the shard's suites in CI order (the job log's `shard N:`
  line) and cut the list in halves.
- **Docs:** [Performance review](../engines/godot/performance-review.md), "How to measure it"; earlier lessons:
  [a count test read a peak](2026-11-04-a-count-test-read-a-peak-while-the-fight-and-the-menu-kept-moving.md),
  [a count test that skipped the Audio queue](2026-11-04-a-count-test-that-skipped-the-audio-queue-failed-on-main.md).
