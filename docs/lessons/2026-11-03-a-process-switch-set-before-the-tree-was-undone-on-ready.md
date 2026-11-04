---
areas: [godot, camera, gameplay]
---
# A `set_process(false)` made before the node was in the tree was undone when it became ready

2026-11-03

- **Saw:** Deadnight #938. The puppet of another machine's player turned its camera rig off with
  `rig.set_process(false)`, and the code comment said only bots' rigs ran. A process-count probe showed every rig of a
  night, the puppets' too, with `is_processing()` true and a shape sweep each drawn frame.
- **Cause:** the body is made (`make_puppet`) before `add_child`. When a node becomes ready, the engine switches
  `_process` (and `_physics_process`) on again if the script defines it, so a switch set before the tree is lost.
  Probe: `set_process(false)` before `add_child` leaves `is_processing()` true and one call a frame; the same call
  made in the script's own `_ready()` sticks.
- **Fix:** the rig keeps its own flag (`rest()` / `resume()`) and re-asserts it in `_ready()`
  (`set_process(not _resting)`). A test counts the nodes with `is_processing()` in a built night (1 in a night of a
  person and three bots), never trusts the call that was made.
- **Docs:** [Third-person camera](../godot/camera.md#a-rig-no-one-looks-through).
