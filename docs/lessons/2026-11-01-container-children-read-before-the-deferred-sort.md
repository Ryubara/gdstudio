# Tweening a container child's position collapsed the rows, sometimes

2026-11-01

- **Saw:** after a tab click every row of the page sat at the top, overlapping; only sometimes, never in tests
  (deadnight #345).
- **Cause:** a `Container` sorts its children in a deferred call that runs after `SceneTree.process_frame` is
  emitted. Input is handled before the signal in the same frame, so `await process_frame` from an input handler resumes
  before the sort unless a physics step ran first. A control just shown has never been sorted, so its `position` is
  (0, 0). Tests that call from a `process_frame` coroutine resume after the sort and never see it.
- **Fix:** read positions two `process_frame`s after the change, stop the previous tween of the same control, and
  `queue_sort()` the container when the tween ends. Reproduce with `Input.parse_input_event` and
  `Engine.physics_ticks_per_second = 1`; a click's position in window pixels is
  `viewport.get_final_transform() * control.get_global_transform_with_canvas() * (size / 2)`.
- **Docs:** [UI controls](../godot/ui-controls.md).
