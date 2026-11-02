---
areas: [godot, gameplay]
---
# A SceneTree script could not host nodes that need the tree

2026-11-01

- **Saw:** a measuring script run with `godot --script` (extending `SceneTree`) built the game's night and failed with
  `!is_inside_tree()`.
- **Cause:** the nodes it adds in `_initialize` are not in the tree yet when the code that needs them runs.
- **Fix:** for anything that builds scenes or nodes, write a small scene with a root script and run `godot --path .
  res://that_scene.tscn`; keep `--script` for pure data work.
- **Docs:** Deadnight `docs/research/bots.md`.
