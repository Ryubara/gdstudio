---
areas: [tests, godot]
---
# A capture switched to the camera rig instead of its camera

2026-11-02

- **Saw:** `SCRIPT ERROR: Invalid call. Nonexistent function 'make_current' in base 'Node3D (ThirdPersonCamera)'`,
  and the Movie Maker frames stayed on the overview camera (Deadnight #634's stair capture).
- **Cause:** a player's `camera_rig` is the rig (a `Node3D` that places the lens), not the `Camera3D` it moves.
- **Fix:** make the rig's own camera current: `rig.find_children("*", "Camera3D", true, false)[0].make_current()`;
  read the capture's log for `SCRIPT ERROR` before looking at its frames.
- **Docs:** [Modular kits: stairs](../blender/modular-kits.md#stairs-rails-and-blockers).
