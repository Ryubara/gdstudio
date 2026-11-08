---
areas: [godot, tests]
---
# MultiMesh transforms read as zero in a headless test

2026-11-03

- **Saw:** a GdUnit test that every copy of a backdrop's multimeshes stands outside the yard reported copies at
  `(0, 0, 0)`; the scene's buffer had them 60 m out.
- **Cause:** a `--headless` run draws with the dummy renderer, which keeps no instance data:
  `MultiMesh.get_instance_transform(i)` returns the zero transform for every copy (probed for 1 to 30 copies).
- **Fix:** read the `buffer` property (12 floats a copy, each basis row followed by its origin's coordinate), which
  keeps the scene's values.
- **Docs:** [The headless renderer](../engines/godot/headless-renderer.md#multimesh-copies-have-no-transform-headless).
