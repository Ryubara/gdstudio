# An input action defined twice in project.godot kept only the later binding

2026-11-01

- **Saw:** on a gamepad, X both reloaded and bought a door, and B (crouch) paused the night and, through the router's
  back handling, would have left it.
- **Cause:** two pull requests each added `interact` to `[input]`; Godot keeps the last block, so the intended button
  was lost and `reload` and `interact` shared one. `InputMap` cannot show it (the first block is already gone). B is
  also `ui_cancel`, which the player, the screen and the router each listened to.
- **Fix:** one block per action; gameplay actions listen to their own actions (`pause`, `interact`), not `ui_cancel`;
  an in-game screen refuses the router's back. A test reads the project file for a repeated action, and the InputMap
  for two gameplay actions on one pad button or stick direction.
- **Docs:** [UI controls](../godot/ui-controls.md); Deadnight `docs/design/slice.md`.
