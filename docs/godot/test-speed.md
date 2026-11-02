# Test speed

How to keep a GdUnit4 suite from running at the speed of the clock, from Deadnight's CI job that took 20 minutes
(Deadnight #524). The numbers and the suite-by-suite list are in the game's `docs/research/ci-time.md`.

## Measure first

The job log has a timestamp per line. A suite's time is the gap between its `Run Test Suite:` line and the next one
(its `before()` and `after()` included). Sort the gaps; the top twenty are the work. Run the whole suite locally the
same way only when nothing else is loading the machine: a loaded machine doubles unrelated suites.

## What makes a suite run at the clock's speed

| Cause | What to do |
| --- | --- |
| `await get_tree().physics_frame` per hand-stepped tick | switch the node's `_physics_process` off once and call its tick by hand, back to back; one `process_frame` per measurement |
| `create_timer(s)` to let an animation finish | wait the same game seconds at `Engine.time_scale = 10` and set it back to 1 before the next step (restore it in `after_test` too) |
| a batch of seeded runs bigger than the case needs | keep the full count where it is the gate; a case that proves the gate can fail needs a wall, not a statistic |
| a test about the engine's own callback, a socket or a freeze | leave it on the clock and say so in its first comment |

## What hand stepping needs

- **One physics step for new bodies.** The physics server indexes a body on its next step. After loading a room and
  after adding a collider, `await get_tree().physics_frame` once; then tick by hand. Without it a hand-ticked body falls
  through the floor ([lesson](../lessons/2026-11-02-a-hand-ticked-player-fell-through-a-floor-no-step-had-seen.md)).
- **The same code path.** Call what the engine calls (`_physics_process`, or the node's public `tick`), with the same
  delta, so a faster suite plays the same game. A node whose `_physics_process` is switched off is not ticked twice.
- **Delta-sensitive comparisons stay in one kind of frame.** `move_and_slide` steps an idle frame by its wall-time
  delta; a recording made in a physics callback and replayed in an idle frame can differ by millimetres under load
  ([lesson](../lessons/2026-11-02-a-replay-in-an-idle-frame-missed-by-millimetres-on-a-loaded-machine.md)).
- **Prove it still tests.** Break the behaviour once, locally, and see each sped-up suite fail.

See also [a physics frame per tick](../lessons/2026-11-02-a-physics-frame-per-hand-stepped-tick-ties-a-test-to-the-clock.md)
and [Engine.time_scale](../lessons/2026-11-01-time-scale-also-scales-the-physics-step.md).
