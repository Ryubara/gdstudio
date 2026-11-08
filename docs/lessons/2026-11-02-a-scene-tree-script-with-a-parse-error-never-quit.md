---
areas: [godot, tests]
---
# A headless SceneTree script with a parse error ran for minutes and printed nothing

2026-11-02

- **Saw:** `godot --headless -s res://.../report.gd` piped into `tail` sat for six minutes with no output and
  almost no CPU; a second run without the pipe showed `Parse Error: Cannot infer the type of "mine"` in a class it
  used, and then `Parameter "data.tree" is null` from `get_tree()`.
- **Cause:** a script error in `_initialize` stops that call, but the `SceneTree` keeps running with nothing to quit
  it; and a node added to `root` in `_initialize` is not in the tree yet, so its `get_tree()` is null.
- **Fix:** parse-check the scripts first (`godot --headless --check-only -s <script>`, once per file), give every
  headless run a `timeout`, write its log to a file instead of a pipe, and start the work after
  `await process_frame`. A report tool also exits 1 when it measured nothing.
- **Docs:** [Navigation in tests](../engines/godot/navigation-in-tests.md#measuring-a-map-on-its-mesh).
