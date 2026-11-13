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
  both hands on the pistol for both mannequins, and `write_hold.gd` writes the seat and the `HandPose` files, with the
  finger poses set by hand
  (`pistol_authored.json`, read by `authored_pose.gd`) laid over them (`lay_authored.py` lays them into the solve's
  own file before `--magazine-only` or `--way-only`); `pose_bench.gd` measures such a file on the
  tests' stage before it is written (`PARTS=1`, `JOINTS=`, `OBJ=`).
- `tools/capture/rack_closeups.tscn` poses a body on every frame of the pistol's slide-rack clip
  (`assets/animation/pistol/`) with the hold's hands, the left hand reached to the slide and the body's own fingers
  (`tests/fixtures/rack_stage.gd`): headless it prints how each hand meets the pistol (lines starting `RACK`) and,
  with a window and `RACK_OUT`, saves close-ups of the reach, the grip, the pull, the release and the follow-through
  from six sides (the gun's right, its left, above, the front, the player's camera close up and the game camera), on
  the female body or the male (`MODEL=male`); `RACK_CARRY=0` holds the pistol where the clip has it and
  `RACK_FINGERS=0` leaves the clip's own fingers. `tools/hold/write_slide_rack.gd` writes each body's `SlideRack`
  file from the clip build's data, and `tools/hold/hold_files.py` reads a body's hold out of the project's files
  for the rack's solver and build.
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
- `tools/capture/rifle_clip_closeups.tscn` pictures the rifle clips (`assets/animation/rifle/`) pose by pose on both
  bodies, eight views at once (the body from the right, above, the front and the player's camera; the grip hand
  and the support hand from both their sides, from cameras that ride the rifle), with the hold told what the game
  tells it (`CLOSEUPS_OUT=<folder>`); it prints each hand's gap and depth.
- `tools/capture/vault_study.tscn` plays the vault clips (`assets/animation/vault/`) on the mannequin over each clip's
  reference box, with a sprint in and out, from four views; headless it prints how still the planted hand stays
  (`MODEL=male`, `VIEWS`, `SLOW`, `LOW_HEIGHT` and `HIGH_HEIGHT` are in the header).
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
- `tools/soak/ai_soak.tscn` is the AI soak: the AI section's population (times `--scale`) fighting the player's
  autopilot (`tools/soak/section_pilot.gd`) and civilians in the pathing section, seeded, at the fixed step; the gates
  of `ai_soak_watch.gd` (an engine error, a stuck episode, stuck time, idle with a threat in view, a task past its hard
  timeout, a path-query storm, think p99, a belief naming a wall, a round that never ends) print what the character
  held, did and decided (`AI_SOAK_GATE {...}`); `ai_soak_faults.gd` breaks a character for each gate
  (`--faults all`). `--lines` prints a line of numbers a character. The header says how to run it; the nightly
  `ai-soak.yml` runs 50 seeds, `tests/gameplay/test_ai_soak.gd` the pull-request seed and the faults.
- `tools/soak/ai_pose_log.tscn` runs the AI soak and prints a `POSE {...}` line each time an AI character's animation
  changes (its state, the locomotion node, the action, reload, shoot and melee layers, the weapon layer's weights,
  its tier and whether its tree is throttled), to trace a pose seen in play to the clip that played it (gdstudio #1345).
- `tools/capture/enemy_pose_tour.tscn` films, from the player's camera, a body on the enemy's mannequin taking chest
  shots while it aims and one that fires its pistol dry and reloads.
- `tools/web_smoke/ai.py` runs the soak's web export (`gds template bench-web 3d-third-person
  tools/soak/ai_soak.tscn`) in Chrome at each population and CPU throttle and prints the frame's work, the AI step
  and ticks a frame.
- `tools/capture/section_tour.tscn` films the AI section's population from the game camera (`SECTION_TOUR=fight`,
  `cover`, `chase` or `civilians`).
- `tools/capture/ai_section_online_tour.tscn` films the AI section's fight online from a client's screen: the game
  server spawns the population for her body and her client draws every character as a puppet.
- `tools/bench/ai_section_bench.tscn` times the AI director's step with the AI section's population, the player
  watching and fighting (`AI_SECTION_BENCH {...}`); `ai_section_bench.py` runs it in Chrome
  (`gds template bench-web 3d-third-person ai_section_bench --run`).
