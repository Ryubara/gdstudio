---
areas: [tests, audio, ci]
---
# A count test failed on main because it counted sounds, tweens and a menu's background load

2026-11-04

- **Saw:** `test_kill_allocations` failed `godot (6)` on main with `objects held: 49` against 48 (52 once locally,
  passing alone), and `test_hud_shapes` failed `godot (2)` on a pull request by 40 and 22 objects, with UI `.ogg`
  loads inside the failing test's 72 ms (Deadnight #1102).
- **Cause:** none of the extra objects was a kill's or a label's. In the night, a torn or mended board is a Tween with
  its tweeners (5 and 3 objects, up to nine at once) and every sound that starts is a budget voice plus the engine's
  playback (2 each, 20 or more at once); the test read the peak of a swing against a start taken at another point of it
  (37 to 45 locally, 49 and 52 elsewhere). In the HUD test, the main menu's background load of every sound
  (`Audio.start_background_preload`, begun in any earlier suite that builds the menu) went on in its frames; the
  helper from the lesson before waited only for the deferred decode queue, not for this second queue. Also: the
  resource monitor counts only resources with a path, so a mesh and a material a kill makes in code show in the object
  count and not in the resource count; the object count is the one that has the teeth.
- **Fix:** read objects at a standstill, never at a peak: stop the source of motion, then `QuietCount.settle` (sounds
  stopped, tweens finished, `Audio.wait_for_mixer`, which also frees the playbacks the audio thread holds a few steps
  longer), before and after, with the same number of dead alive; `AudioSettle.until_idle` also ends the background load
  and settles the autoload beside a test's own service. Failed first: 13 extra sounds at the peak made the old test
  fail (79 held), the same sounds passed the new one (10); a test that started the menu's load made `test_hud_shapes`
  fail with the helper as it was (+28 and +22) and pass with it as it is. Teeth kept: a kill that holds one object (+25)
  or a material and a mesh (+40) still fails.
- **Rule:** a test that counts objects waits for every kind of work the process does by itself (queues, loads, tweens,
  voices) before it reads, and compares two readings taken in the same state; it never takes a maximum over frames of
  a live fight. No assertion between two readings (an assertion is objects of its own).
- **Docs:** [Performance review](../godot/performance-review.md), "How to measure it"; earlier lessons:
  [a count test that skipped the Audio queue](2026-11-04-a-count-test-that-skipped-the-audio-queue-failed-on-main.md).
