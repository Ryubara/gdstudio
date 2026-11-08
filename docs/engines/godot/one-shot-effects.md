# Pooled and one-shot effects

A client-side effect (a blast, gibs, a scorch mark, a flash) is made while the game runs, often hundreds of times a
night. What it does when it ends decides whether a night is flat or grows for as long as it lasts. Found in Deadnight's
performance review (#907, #929); the lessons are linked below.

## The rule

- **A one-shot frees itself.** Whoever makes it does not have to remember: the effect counts its parts (a tween each, or
  a timer) and calls `queue_free` on the last. A part that has faded to alpha 0 or energy 0 is not "gone": it is still
  a draw call, and a light still holds one of a mesh's eight light slots on the Compatibility renderer
  ([Compatibility lighting](compat-lighting.md#dynamic-lights)). Free the part at the end of its own tween
  (`tween.finished.connect(part.queue_free)`), not with the effect.
- **Do not hide what you can free.** A hidden node still costs its `_process` and its place in the tree; a hidden gib was
  0.47 us a frame for the rest of the night.
- **Frequent and small: pool it with a cap** (blood, tracers, damage numbers in Deadnight); rare and big: free it.
- **Prove it with counts**, not by eye: count the effect class, `Light3D`, `MeshInstance3D` and all nodes under the scene
  before, play N effects, wait the longest effect time and compare (`tests/night/test_blast_frees.gd`). Run the clock
  fast (`Engine.time_scale`) for the long wait, but check the early moments (a light gone, a scorch still there) at real
  speed: one slow frame at a fast clock skips past everything.

## `_process` is on after ready

A script that defines `_process` has it turned on when the node is ready, *after* `_init` ran. `set_process(false)` in
`_init` does nothing; put it in `_ready` (or call it from the code that decides the node has nothing to move). The same
holds for `_physics_process`. See the [lesson](../../lessons/2026-11-03-set-process-false-in-init-was-turned-back-on-at-ready.md).
