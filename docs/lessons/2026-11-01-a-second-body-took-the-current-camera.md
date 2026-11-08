---
areas: [camera, godot-ui]
---
# A second body in the same process took the current camera

2026-11-01

- **Saw:** a capture of the HUD's names and markers showed a frozen view while the numbers (distance to the door)
  changed; every screenshot looked the same (Deadnight #134).
- **Cause:** a second `Player` body joined in the same process (a teammate for the capture) and made its own
  `Camera3D` current when it entered the tree, so the viewport looked through the teammate's camera. Projection
  through `get_viewport().get_camera_3d()` agreed with what was drawn, so nothing looked broken in the HUD.
- **Fix:** `make_current()` on the player's camera after any join; a capture prints the current camera's path once a
  second while the view is checked (Deadnight #430).
- **Docs:** [Camera](../engines/godot/camera.md#projecting-world-points-to-the-hud); Deadnight `docs/research/hud.md`.
