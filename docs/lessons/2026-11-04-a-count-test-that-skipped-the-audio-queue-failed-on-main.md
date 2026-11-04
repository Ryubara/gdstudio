---
areas: [tests, audio, ci]
---
# A test that counted objects across frames failed on main because the Audio queue was not empty

2026-11-04

- **Saw:** `test_labels_made_and_freed_leave_no_objects_behind` (Deadnight #1093) failed on main twice in two runs, in
  shard 8 only: 55 and 78 more objects than before, with `Loading resource: ...soldier_female/*.ogg` lines in the log
  right above the failure. Run alone, the same test failed by 4 to 6 with nothing queued.
- **Cause:** the deferred sound banks queue their files on the `Audio` autoload, which decodes a few milliseconds a
  frame while any suite runs; every decoded sound is objects. An earlier lesson had fixed that in one test
  (`test_shot_effects_pool`, a private loop in its `before_test`), so every other test that counts `OBJECT_COUNT`
  across `await process_frame` was still open to it, and the shard deal (stale times) decides what runs before it. The
  second cause: the first `HudLabel` of a process makes about six objects that stay (a `TextLine`, caches), so the
  count must start after one label has been made and freed.
- **Fix:** one shared helper, `AudioSettle.until_idle(tree, service)` (Deadnight `tests/core/audio_settle.gd`), awaited
  before the first count in every test that counts across frames; a warm label before the count. Failed first: a test
  that queues 40 deferred sounds on a service of its own, runs the count, and fails (+32) with the settle removed.
  No slack widened, no retry.
- **Rule:** a fix for an order-dependent count belongs in a helper every counting test calls, not in the one test that
  failed, and the test that proves it brings its own queue (a fresh service) instead of hoping an earlier suite left
  one.
- **Docs:** [Performance review](../godot/performance-review.md), "How to measure it"; earlier lessons:
  [a resource-count test counted the sounds an earlier suite queued](2026-11-03-a-resource-count-test-counted-the-sounds-an-earlier-suite-queued.md).
