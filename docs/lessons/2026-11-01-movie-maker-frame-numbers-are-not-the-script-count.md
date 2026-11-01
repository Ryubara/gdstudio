# The wrong frame of a Movie Maker capture

2026-11-01

- **Saw:** a capture script printed "keep frame 23" and that file showed another moment (a different camera, no
  effect).
- **Cause:** the script counted its own `_process` calls; Movie Maker numbers files from the first rendered frame,
  loading frames included.
- **Fix:** print `Engine.get_frames_drawn()` for the frame to keep.
- **Docs:** [Shot feedback](../godot/shot-feedback.md).
