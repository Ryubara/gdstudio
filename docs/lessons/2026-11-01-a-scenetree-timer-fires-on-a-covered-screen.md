---
areas: [godot, godot-ui]
---
# A SceneTree timer fired on a covered screen

2026-11-01

- **Saw:** a main menu waited 0.55 s with `SceneTree.create_timer` before focusing `Play`; a screen pushed over the menu
  inside that window lost its focus to the covered menu's button.
- **Cause:** a `SceneTree` timer belongs to the tree, not the node: it ignores the node's disabled `process_mode` and
  outlives it.
- **Fix:** wait with a child `Timer` node (it stops with a disabled parent and is freed with it), take focus only while
  the screen is the router's top, and make the delay settable so tests need no wall time.
- **Docs:** [UI controls](../godot/ui-controls.md); Deadnight `docs/research/ui-foundation.md`.
