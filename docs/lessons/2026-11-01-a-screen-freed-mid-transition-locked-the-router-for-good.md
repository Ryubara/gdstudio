---
areas: [godot, input]
---
# A screen freed mid-transition locked the router for good

2026-11-01

- **Saw:** after a screen was freed while a transition ran, `UIRouter.busy` stayed true, every later push was queued
  forever and input was swallowed; no error was logged.
- **Cause:** the transition awaited a tween created on that screen (`node.create_tween()`). A tween is killed when its
  node is freed and its `finished` signal never fires, so the `await` never returns.
- **Fix:** bind a transition's tweens to a node that outlives the screens (the stage), check `is_instance_valid` after
  every await, and drop a screen from the stack when it leaves the tree. Anything that awaits a signal from a node it
  does not own needs the same thought.
- **Docs:** deadnight `docs/research/ui-foundation.md` (Router).
