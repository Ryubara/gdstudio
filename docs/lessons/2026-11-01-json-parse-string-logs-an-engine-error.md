---
areas: [tests, gameplay]
---
# Reading a damaged JSON save turned the smoke run red

2026-11-01

- **Saw:** a test (and the CI smoke run) that fed bad text to `JSON.parse_string` printed
  `ERROR: Parse JSON failed. Error at line 0: Expected key`, and the pipelines grep for `^ERROR`.
- **Cause:** `JSON.parse_string` reports a syntax error through the engine's error log, not only by returning null.
- **Fix:** use an instance: `var json := JSON.new()` then `json.parse(text) != OK` handles bad text silently, and
  `json.data` is the result. Do this for every file that came from a player's disk or from the network.
- **Docs:** [Godot](../engines/godot/index.md).
