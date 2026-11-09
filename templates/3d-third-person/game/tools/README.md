# tools

Captures, benches and probes, one folder per purpose (`tools/capture/`, `tools/web_smoke/`). They are left out of the
export, so shipped code never refers to `res://tools/`: the other way round is fine, tools may use the game.

- `tools/capture/level_tour.tscn` records the level from a few angles for a pull request's screenshots.
- `tools/capture/walkthrough.tscn` plays the character through the map by pressing the input actions, for a clip.
- `tools/capture/action_tour.tscn` plays the character through the range, the crouch course and the cubes by pressing the
  input actions, for a clip with the sound.
- `tools/capture/camera_walls_tour.tscn` stands the character by a wall of the map and aims, fires and sprints at camera
  yaws all round by pressing the input actions, for a clip of the camera against a wall (it prints the lens-to-head
  distance each physics frame, lines starting `LENS`).
- `tools/web_smoke/touch_smoke.py` drives the web export in a phone-sized browser with real touches (run it under
  `gds quiet`; the command is in its header).
- `tools/editor_swap/` is an editor plugin (never enabled in a game) that deletes the player's model in the Scene dock,
  drops `mannequin.glb` on `Model` and checks that the clips, the pistol and the tree survive. The header of
  `swap_in_editor.gd` says how to run it.
