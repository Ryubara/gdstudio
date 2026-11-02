---
areas: [tests, godot]
---
# A paused SceneTree hung a GdUnit4 test that used `await_millis`

2026-11-01

- **Saw:** a test that set `get_tree().paused = true` and then awaited `await_millis(...)` never finished; the headless
  run sat until the outer timeout.
- **Cause:** GdUnit4's wait timer is not an always-processing node, so it stops with the tree.
- **Fix:** wait with `await get_tree().create_timer(seconds, true).timeout` (the second argument ignores pause) and
  reset `get_tree().paused = false` in `after_test`.
- **Docs:** [Godot testing](../godot/index.md#testing-and-capture).
