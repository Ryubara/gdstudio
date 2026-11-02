---
areas: [audio, godot]
---
# A scheduled sound was stamped with the end of the step that ran it

2026-11-01

- **Saw:** a test of a reload's steps against the clip's event frames read every sound a step late (0.832 s for a frame
  at 0.8333 s), and a gun's tail came out at 0.26 s instead of 0.05 s after the shot.
- **Cause:** the schedule moved its clock to the end of the step before running the items that fell due inside it, so
  anything that asked `now()` while running saw the end of the step.
- **Fix:** while an item runs, `now()` (and a chained `add`) count from that item's own due time.
- **Docs:** [Layered gunshots and event-timed sounds](../godot/audio.md).
