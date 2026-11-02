---
areas: [input, godot]
---
# Godot adds a buffered mouse motion to the next one under the first one's device

2026-11-02

- **Saw:** moving the touch layer's look from the drag handler to `_process` (to smooth it, Deadnight #598) made a test
  that sends a stray browser mouse motion beside a drag turn the view by nothing: the layer's own motion was dropped as
  a stray.
- **Cause:** `Input.parse_input_event` keeps events in a buffer until the next frame and, with accumulated input on (the
  default), adds a mouse motion to the previous buffered one when the buttons and modifiers match
  (`InputEventMouseMotion.accumulate`): the sum is kept under the first event's `device`. A stray motion already waiting
  absorbed the layer's tagged motion, and the player ignored the whole as a stray. The old code parsed during the flush,
  where the stray had already been delivered, so the order never met.
- **Fix:** `Input.flush_buffered_events()` before and after parsing an event whose `device` or origin matters, so it is
  delivered alone and at once.
- **Docs:** Deadnight `docs/research/touch-look-smoothness.md`.
