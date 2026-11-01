# Movie Maker ignores `--resolution`

2026-11-01

- **Saw:** `--write-movie` with `--resolution 1280x720` (or 960x540) still wrote 1920x1080 frames.
- **Cause:** the movie is the project's viewport size; the window resolution request does not change it (Godot 4.7.2).
- **Fix:** scale afterwards, which `gds capture sheet` and `gds capture clip` do.
- **Docs:** [Capture](../capture.md).
