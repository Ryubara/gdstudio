# `FileAccess.get_as_text()` returned nothing for a /proc file

2026-11-01

- **Saw:** a headless server on Linux logged `Out of bounds get index '11' (on base: 'PackedStringArray')` every 5 s
  from code that read `/proc/self/stat`.
- **Cause:** procfs files report a length of 0, and `get_as_text()` reads `get_length()` bytes. On Windows the path does
  not exist, so it only showed in the container.
- **Fix:** read it with `get_line()` (the file is one line) and treat an empty result as no data; test Linux-only paths
  in the Docker image.
- **Docs:** [Multiplayer](../godot/multiplayer.md#headless-server-image).
