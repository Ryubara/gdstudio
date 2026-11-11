# tools

Captures, benches and probes, one folder per purpose (`tools/capture/`, `tools/bench/`, `tools/web_smoke/`). They are left
out of the export, so shipped code never refers to `res://tools/`: the other way round is fine, tools may use the game.

- `tools/capture/level_tour.tscn` records the level from a few angles for a pull request's screenshots.
- `tools/capture/model_tour.tscn` films the player's model from the front and from behind with the pistol up, for the
  screenshots of a model change (it films the model `player.tscn` holds).
- `tools/capture/carry_tour.tscn` films how the pistol is carried, from the character's right side with the game
  camera: stand, walk, jog, sprint, crouch walk, a jump, then aim, hip fire, aim with fire and an aim walk
  (`CARRY_MODEL=male` films the male mannequin; `CARRY_BONES` and `CARRY_HELD=1` try another grip or the held pose).
- `tools/carry/measure_clearance.gd` measures how deep the held pistol sinks into the body in each locomotion clip on
  both mannequins (the header says how to run it; `tests/gameplay/test_pistol_clearance.gd` pins it at none).
- `tools/capture/pistol_hold_study.tscn` poses a mannequin in every pistol clip and the locomotion clips with the
  pistol out, prints how each hand meets the pistol (lines starting `HOLD`) and, with a window and `HOLD_OUT`, saves
  close-ups from the gun's left, its right, above and the player's camera (`MODEL=male`; `HOLD_OFF=1` is the clips'
  own fist).
- `tools/hold/` solves the pistol hold: `dump_hold_rig.gd` writes the rig as Godot plays it,
  `solve_pistol_hold.py` (numpy and scipy; `hold_rig.py`, `hold_field.py` and `hold_hand.py` are its parts) closes
  both hands on the pistol for both mannequins, and `write_hold.gd` writes the seat and the three `HandPose` files.
- `tools/capture/rack_closeups.tscn` poses a mannequin on every frame of the pistol's slide-rack clip
  (`assets/animation/pistol/`), the left hand reached to the slide and the `Slide` node moved, prints how each hand
  meets the pistol (lines starting `RACK`) and, with a window and `RACK_OUT`, saves close-ups of the reach, the grip,
  the pull, the release and the follow-through from the front left, the gun's right, above and the player's camera
  (`MODEL=male`); `tools/hold/write_slide_rack.gd` writes the clip's `SlideRack` file from the clip build's data.
- `tools/bench/hold_cost.tscn` times 40 mannequins with no hold, the carried hold or the aimed one (the run is its
  user argument, one run a process).
- `tools/capture/walkthrough.tscn` plays the character through the map by pressing the input actions, for a clip.
- `tools/capture/action_tour.tscn` plays the character through the range, the crouch course and the cubes by pressing the
  input actions, for a clip with the sound.
- `tools/capture/camera_walls_tour.tscn` stands the character by a wall of the map and aims, fires and sprints at camera
  yaws all round by pressing the input actions, for a clip of the camera against a wall (it prints the lens-to-head
  distance each physics frame, lines starting `LENS`).
- `tools/capture/shake_tour.tscn` sprints, aims and fires, and sets off two blasts through `CameraShake.shake()`, with the
  sprint shake and the shot kick turned up, for a clip of the shake (it prints the turn of the view each physics frame,
  lines starting `SHAKE`).
- `tools/capture/near_hit_tour.tscn` lands rounds from an unseen shooter beside the standing character, then one 20 m
  away, for a clip of the near-hit shake (lines starting `SHAKE`, and `HIT` with each hit's distance from the camera).
- `tools/capture/hud_tour.tscn` films the HUD with its health and ammo parts fed by a stand-in, on a desktop or (user
  argument `phone`) with the touch controls up on a phone-sized window.
- `tools/capture/ragdoll_tour.tscn` runs the character, kills it mid-run with the `ragdoll` key, orbits the body,
  gets it up and runs it off the ragdoll ledge, by pressing the input actions (`RAGDOLL_MODEL=male` films the male
  mannequin).
- `tools/capture/hit_tour.tscn` shoots three targets from the player's camera: a headshot kill, a body-shot kill, two
  hits on a target walking past (it flinches and walks on) and shots into a body on the ground (`HIT_MODEL=male` puts
  the male mannequin on the targets).
- `tools/bench/hit_zones_bench.tscn` prints what a shot's second test, the zones following the bones and the flinch
  cost for 1, 4 and 10 characters (`HIT_ZONES_BENCH`); `hit_zones_bench.py` runs its web export in headless Chrome
  under `gds quiet`.
- `tools/capture/rifle_hold_study.tscn` holds the rifle on the mannequin five ways with the clips the template has
  (the pistol clip, left-hand IK, shouldered with both hands on IK, aimed up, low ready), prints how far each hand stops
  from its target and, with a window and `HOLD_OUT`, saves the renders (the header says how to run it).
- `tools/capture/prone_clips_tour.tscn` plays the prone and crawl clips (`assets/animation/prone/`) on the mannequin
  over a floor of 0.25 m squares, from the side, the front quarter and the game camera's place, crawling at the clip's
  speed (`MODEL=male` films the male mannequin; `PRONE_SHOTS=<folder>` saves side, front and top stills of each clip).
- `tools/ragdoll/measure_joints.gd` measures the joint limits of `CharacterRagdoll.BODIES` from every clip on both mannequins
  (the header says how to run it).
- `tools/capture/muzzle_flash_tour.tscn` fires the pistol in slow motion at the orange block, with the flash on and then
  off, for a clip of the muzzle flash.
- `tools/bench/effects_cost.tscn` fires the pistol in six runs (no flash, flash, flash with impacts, at 4 and 30 shots a
  second) and prints frame time, script time, draw calls and nodes for each (`BENCH` lines; the header says how to read
  it in the browser).
- `tools/bench/sound_start_bench.tscn` prints what starting a sound costs (`SOUND_START` lines): the pistol's shot
  as an Ogg randomizer, one take as Ogg, PCM and QOA, 3D and flat, the weapon's `ShotSound` and an impact through the
  emitter, and the decode the level's load pays; `tools/bench/sound_start_bench.py` reads it from a web export in
  headless Chrome under `gds quiet` and counts the browser samples and the output's peak per case.
- `tools/bench/effects_first_use.py` runs a web export of that bench in headless Chrome and fails when a run after the
  level's warm-up links a GL program (the first flash, its light or the first impact stopping the frame); run it under
  `gds quiet`, the command and the export are in its header.
- `tools/bench/player_step_bench.tscn` times a character's own physics tick for 1, 8 and 40 bodies, by the input and by
  commands; `tools/bench/player_step_bench.py` reads it from a web export in headless Chrome (run it under `gds quiet`).
- `tools/bench/parts_cost_bench.tscn` prints what the parts cost a frame: 1 to 50 dressed characters idle and walking,
  each character part timed apart, a first and a later death on each mannequin, and 100 of each world part
  (`PARTS_COST_BENCH` line); `tools/bench/parts_cost_bench.py` reads it from a web export in headless Chrome (under
  `gds quiet`).
- `tools/web_smoke/touch_smoke.py` drives the web export in a phone-sized browser with real touches (run it under
  `gds quiet`; the command is in its header).
- `tools/net/echo_server.gd` is a bare server for transport probes (echo, and a numbered stream on request); it prints
  `LISTENING <port>` (the header says how to run and stop it).
- `tools/bench/server_bench.tscn` times the game server's step with 1 to 8 bots on real sockets in the map and counts
  the bytes each way (`-- --bodies=8 --ticks=1200`; prints `SERVER_BENCH`).
- `tools/net/server_bot.gd` plays bots against a running server (`-- --server`) in another process and prints what
  each saw (`SERVER_BOT`: slot, TICKs, players, ack, round trip, bytes); with `--moves` each runs the weapon presses, a
  slide and the map's vault course and lists the states the server sent it; the header has the command.
- `tools/net/predict_bot.gd` is a predicting client (`NetClient`, the map, `RemotePlayers`) against a running server:
  circles, sprints and jumps, optional `--delay-ms` and `--freeze s:ms,...`, and prints `PREDICT_BOT` (corrections,
  snaps, worst error, end gap, stalls, puppets, starved steps, round trip, microseconds a step); the header has the
  command.
- `tools/capture/online_tour.tscn` records a server and two clients in one process side by side: Ada's own screen
  and Bo's, where she is drawn from the server (`gds capture frames --scene res://tools/capture/online_tour.tscn`).
- `tools/net/relay.py` is a TCP relay with a delay each way and a byte counter, for a real round trip on one machine
  (the browser's throttling does not touch WebSockets).
- `tools/web_smoke/net_link_smoke.py` drives the web export's `NetProbe` (`?netprobe&url=ws://...`) against the echo
  server: the link opens from the page address, survives a 5 s frozen tab, refuses `ws://` from `https` (run it under
  `gds quiet`; the command is in its header).
- `tools/editor_swap/` is an editor plugin (never enabled in a game) that deletes the player's model in the Scene dock,
  drops the other mannequin (`mannequin_male.glb`) on `Model` and checks that the clips, the pistol and the tree
  survive. The header of `swap_in_editor.gd` says how to run it.
- `tools/map_bake/` is an editor plugin (never enabled in a game) that bakes what only the editor makes for the map
  and its sections: the blocks' meshes with their lightmap UVs, the navigation meshes and the lightmaps. The header of
  `map_bake.gd` says how to run it.
- `tools/world/ledge_probe.gd` prints how high a ledge the character climbs from level ground, one line a height (the
  number `tests/world/test_jump_reach.gd` pins).
- `tools/capture/sections_tour.tscn` saves stills of the two map sections from the player's camera and from above
  (`--debug-navigation` draws the navigation meshes); the header says how to run it.
