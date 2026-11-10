# tools

Captures, benches and probes, one folder per purpose (`tools/capture/`, `tools/web_smoke/`). They are left out of the
export, so shipped code never refers to `res://tools/`: the other way round is fine, tools may use the game.

- `tools/capture/level_tour.tscn` records the level from a few angles for a pull request's screenshots.
- `tools/capture/model_tour.tscn` films the player's model from the front and from behind with the pistol up, for the
  screenshots of a model change (it films the model `player.tscn` holds).
- `tools/capture/walkthrough.tscn` plays the character through the map by pressing the input actions, for a clip.
- `tools/capture/action_tour.tscn` plays the character through the range, the crouch course and the cubes by pressing the
  input actions, for a clip with the sound.
- `tools/capture/camera_walls_tour.tscn` stands the character by a wall of the map and aims, fires and sprints at camera
  yaws all round by pressing the input actions, for a clip of the camera against a wall (it prints the lens-to-head
  distance each physics frame, lines starting `LENS`).
- `tools/capture/shake_tour.tscn` sprints, aims and fires, and sets off two blasts through `CameraShake.shake()`, with the
  sprint shake and the shot kick turned up, for a clip of the shake (it prints the turn of the view each physics frame,
  lines starting `SHAKE`).
- `tools/capture/ragdoll_tour.tscn` runs the character, kills it mid-run with the `ragdoll` key, orbits the body,
  gets it up and runs it off the ragdoll ledge, by pressing the input actions (`RAGDOLL_MODEL=male` films the male
  mannequin).
- `tools/ragdoll/measure_joints.gd` measures the joint limits of `PlayerRagdoll.BODIES` from every clip on both mannequins
  (the header says how to run it).
- `tools/web_smoke/touch_smoke.py` drives the web export in a phone-sized browser with real touches (run it under
  `gds quiet`; the command is in its header).
- `tools/editor_swap/` is an editor plugin (never enabled in a game) that deletes the player's model in the Scene dock,
  drops the other mannequin (`mannequin_male.glb`) on `Model` and checks that the clips, the pistol and the tree
  survive. The header of `swap_in_editor.gd` says how to run it.
