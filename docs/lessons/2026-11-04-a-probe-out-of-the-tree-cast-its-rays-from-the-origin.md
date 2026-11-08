---
areas: [godot, tests]
---
# A probe out of the tree cast its rays from the origin and reported clear

2026-11-04

- **Saw:** a `godot --script` check of the helicopter (Deadnight #1057) said a rope straight down from `RopeAnchor`
  was clear at every offset. Its position checks failed beside it, which is the only reason anyone looked: alone,
  the ray results would have passed.
- **Cause:** the known one ([a SceneTree script](2026-11-01-a-scenetree-script-cannot-host-the-game.md)): the root is
  not in the tree in `_init` or `_initialize`, so `add_child` leaves the scene outside it. What is new is how it hides:
  `global_position` and `global_transform` return the origin and an identity basis, and the only trace is
  `!is_inside_tree()` on the log. A grep for the check's own lines removes it. A test that passes when nothing is
  hit, passes from the wrong place. Moving the code from `_init` to `_initialize` changed nothing.
- **Fix:** `get_root().add_child.call_deferred(root)`, two `await process_frame`, then fail outright if
  `not root.is_inside_tree()`. Give every "nothing is in the way" check a control that must hit: the sweep from the
  anchor went from clear at 10 cm to hit at 13 cm, which is where the sill frame is, and only that made "clear" mean
  anything. Read a probe's whole log, or grep for `^ERROR` along with its own lines.
- **Docs:** [headless probes](../engines/godot/headless-probes.md).
