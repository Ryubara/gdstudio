---
areas: [tests, godot]
---
# Tracers and flashes were missing from a capture

2026-11-01

- **Saw:** a shot's tracer and muzzle flash were never in any frame, though the game showed them.
- **Cause:** Movie Maker at 10 fps steps 0.1 s a frame, so an effect that lives 0.1 s is gone before the next frame.
- **Fix:** make effects in a captured scene live 0.2 to 0.3 s, look at single frames next to the shot (not only a
  sheet), and cross-check frames with a headless log of the events.
- **Docs:** [Capture](../capture.md).
