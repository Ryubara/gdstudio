# Movie Maker ignores `--resolution`

2026-11-01

- **Saw:** `--write-movie` with `--resolution 1280x720` (or 960x540) still wrote 1920x1080 frames; so did a
  window resized from a script (Deadnight #442).
- **Cause:** the movie is the project's viewport size; the window resolution request does not change it (Godot 4.7.2).
- **Fix:** scale afterwards, which `gds capture sheet` and `gds capture clip` do. To record at a real smaller size
  (a UI test at 720p), write an uncommitted `game/override.cfg` with `window/size/window_width_override` and
  `window_height_override`; the stretch base stays 1920 x 1080, so the UI scales as it does for a 720p player. Delete
  it afterwards.
- **Docs:** [Capture](../capture.md).
