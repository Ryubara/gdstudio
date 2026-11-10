# The character and its model

<!-- new section: split out of the third-person template page when it reached the size limit (#983) -->

The 3D Third Person character: the animation libraries, the mannequins, replacing the model, the controller, the
ragdoll and touch controls. Part of [the 3D Third Person template](../third-person-template.md).

## The animation libraries {#animation-libraries}

<!-- new section: no page said how the Universal Animation Library reaches a Godot character -->

- **Approach:** Import each Universal Animation Library glb as an `AnimationLibrary` (`importer="animation_library"` in
  its `.import`, the "Import As" choice of the Import dock), add it to the player's `AnimationPlayer` under a library
  name (`ual1`, `ual2`), and keep the mannequin as a plain scene whose root is the `AnimationPlayer`'s `root_node`.
  **Watch out for:** the importer drops the glb's mesh (the library is 0.75 MB where the file is 7.6 MB), removes the
  `_Loop` suffix and makes the clip loop (`Idle_Loop` is `ual1/Idle`, `Jump_Loop` is `ual1/Jump`), and the track paths
  are `Armature/Skeleton3D:<bone>`, which match the mannequin's scene (`mannequin/Armature/Skeleton3D`) with no
  retargeting, since the libraries and the mannequin share the Quaternius universal rig. A test walks every track of all
  86 clips and finds its bone. **Seen:** gdstudio #821, 2026-11-08.
- **Approach:** Name every point of an `AnimationNodeBlendSpace1D` (`add_blend_point(node, pos, -1, &"walk")`) and
  travel a state machine between states that all have transitions to each other. **Watch out for:** Godot 4.7 warns "No
  name provided" for an unnamed point, once per point and per player. **Seen:** gdstudio #821, 2026-11-08.
- The Pro and Source tiers of the packs are not free; the template holds the Standard files only (43 clips each, 86 in
  all). Their licence is CC0 on the official pages (itch.io and quaternius.com) and in each zip's `License.txt`.
  A download needs the itch.io page's free "name your own price" path (a CSRF token, then `download_url`, then
  `file/<id>`, all within seconds of each other); keep the zips in `<workspace>/cache/downloads/` and record their
  sha256 in the licence entry.

## The two mannequins {#mannequins}

<!-- new section: the template shipped one mannequin under a neutral name; #843 added the other and named both -->

The template ships both Quaternius mannequins, CC0, on the one universal rig (65 bones, the same names and parents), so
every clip of both libraries plays on either: `mannequin_female.glb` (the pack's `Mannequin_F.glb`, 1.4 MB, the
default in `player.tscn`) and `mannequin_male.glb` (0.6 MB). The pack has no model-only file for the male: he is the
`Mannequin` mesh inside `UAL1_Standard.glb` and `UAL2_Standard.glb` (byte for byte the same mesh, skin and skeleton in
both), so `mannequin_male.glb` is `UAL1_Standard.glb` with its 43 clips removed, by
`tools/models/strip_glb_animations.py` (it copies the nodes, mesh, skin and materials as they are and drops only the
animation data; no Blender round trip, which would have renamed and re-ordered things). The sha256 of the source and of
the result are in the folder's `LICENSE.md`. The female stays the default because the template's captures, the pistol's
seat and the clip checks were all made on her, and the two stand 1.8 m tall with the same feet; the male has longer
collarbones and upper arms (0.22 m and 0.27 m against 0.19 m and 0.22 m; the forearms are the same), so a clip reaches
a slightly different pose.
Swapping is [the editor steps below](#replacing-the-model) with `mannequin_male.glb` (or the other way round).

- **Approach:** Take a model that a pack ships only inside its clip files by dropping the clips from the glb itself
  (parse the glTF chunks, remove `animations`, keep only the accessors and buffer views the meshes and skins use,
  re-pack the binary chunk), and keep the source file's sha256 in the licence entry. **Watch out for:** the
  male's mesh node is `Mannequin` and the female's `Mannequin_F`, and the scene root of both imports as `Armature`/
  `Skeleton3D`, so nothing may refer to either by name (the player scene's node is its own `Mannequin`); the rest
  poses of the arms differ between the two files, so a test compares the bone names and parents, not the poses.
  **Seen:** gdstudio #843, 2026-11-09.
- **Approach:** Film each model through the scene that holds it: point `player.tscn`'s model at the other glb (what the
  editor swap saves) and record `tools/capture/model_tour.tscn`; read the aim-pose frame, where the pistol sits in the
  hand. **Watch out for:** swapping the model in code at run time (`remove_child`, `free`, `add_child` on `Model`) left
  the pistol's `BoneAttachment3D` at the new skeleton's rest pose, 0.65 m from the hand, in
  `ui/player_rig/player_rig.tscn` (the path was right; toggling `use_external_skeleton` off and on later fixed it, doing
  so in `_seat_attachments` did not), while GdUnit's swap and a scene saved with the male glb were right: the test
  passed and the capture showed the pistol on the floor. **Seen:** gdstudio #843, 2026-11-09 (follow-up issue opened).

## Replacing the model {#replacing-the-model}

<!-- new section: a swap of the player's glb in the editor broke the clips, the pistol and the game (gdstudio #844) -->

The player's model is a **slot**: `Model` is a plain `Node3D` with the `CharacterModel` script, and the glb sits under it
(`Model/Mannequin`) with the pistol (`Model/PistolHeld`, a `BoneAttachment3D` on `hand_r`). Nothing refers to the glb
by its name. The model is the dressed character's (`gameplay/character/character_dressed.tscn`): `player.tscn`
inherits it, so there the model is greyed out and cannot be deleted. To swap the character in the editor, open
`character_dressed.tscn` (every character and the player change), or a scene of your own that inherits
`character.tscn` for a second look:

1. In the Scene dock, select the old model (`Mannequin`) and delete it. Leave `Model` and `PistolHeld`.
2. Drag the new `.glb` from the FileSystem dock onto `Model` (the other mannequin, or any name; a glb of the
   Quaternius universal rig, with `Armature/Skeleton3D` under its root and the bone names of the mannequin).
3. Save. The `AnimationPlayer`'s Root Node, the `AnimationTree`, the pistol's skeleton path and the footsteps follow
   the new model by themselves; nothing is set by hand. Turn the new model to face +Z if its file faces the other way.

`CharacterModel.rig()` and `skeleton()` give the model and its skeleton, `rig_changed` says when they change, and the
node warns when it holds no model or two. `CharacterAnimation` points the `AnimationPlayer` at the new model and builds
the tree again; `Footsteps` asks the slot for the skeleton; `CharacterModel` seats every `BoneAttachment3D` child on it.
A model without `Armature/Skeleton3D` gets one configuration warning on `Animation` and no root at all (the engine logs
one line for the player, not one for every bone of every clip). `tools/editor_swap/` does the steps above through the
Scene dock and checks the result.

- **Approach:** Put a part that people replace (the model, a weapon) under a stable slot node and reference only the
  slot (an export); a `@tool` script on the slot finds the part and rewrites the paths that depend on it (the
  `AnimationPlayer`'s Root Node, a `BoneAttachment3D`'s `external_skeleton`) one idle frame after a child enters or
  leaves. Prove the swap with the editor's Scene dock, not `remove_child`. **Watch out for:** the editor **empties every
  NodePath that points at a deleted node**, the Root Node of the `AnimationPlayer` and of the `AnimationTree` among them
  (Godot 4.7.2, Delete key and confirm dialog: `../Model` became empty at once). A dropped-in scene takes its file's
  name and is not unique, so `%Model` in `_ready` ended the game on `null.rotation`. Pistol and muzzle hung inside the
  glb are deleted with it: put them under the slot. **Seen:** gdstudio #844, 2026-11-08.
- **Approach:** Compare the model the slot found with the last one it announced, not with the one it found last. **Watch
  out for:** `rig()` finds the model too, and the editor asks for it whenever it lists a scene's warnings, so a "new
  model" test against the last lookup saw nothing change and `rig_changed` never fired in the editor, while every
  GdUnit test (which never asks in between) passed. **Seen:** gdstudio #844, 2026-11-08.
- **Approach:** Do not rebuild the `AnimationTree` while there is no model (between the delete and the drop), and
  unseat a `BoneAttachment3D` in `child_exiting_tree`, while its skeleton still exists. **Watch out for:** a tree built
  against the emptied Root Node resolved 86 clips from the wrong node: 4,816 `couldn't resolve track` warnings and a
  stall for each rebuild; an attachment bound to a skeleton that was freed first logged "Attempt to disconnect a
  nonexistent connection ... skeleton_updated". **Seen:** gdstudio #844, 2026-11-08.
- **Approach:** To put a `BoneAttachment3D` on the skeleton of a model swapped in at run time, do not rely on the
  path: seat it with the steps of the next entry (`CharacterModel._seat_attachments`), and skip an attachment that
  already sits in the skeleton's `skeleton_updated` connections. **Watch out for:** the engine (4.7.2) connects the
  attachment to `skeleton_updated` only when it enters the tree and in the setters of `use_external_skeleton` and
  `bone_name`, and remembers that it is connected; writing the path neither connects nor disconnects. The old skeleton
  was freed with the mark still set, so the new one had 0 connections and the pistol stayed where the old hand last
  was, though the path read right and the attachment looked bound. **Seen:** gdstudio #860, 2026-11-09.
- **Approach:** Seat the attachment with `set_external_skeleton(NodePath())`, `use_external_skeleton = true`, the new
  path, then `bone_name = bone_name`. **Watch out for:** every setter first disconnects from the skeleton the path
  points at. A toggle written before the path connects nothing (0 connections: the first try in `_seat_attachments`);
  written after it, with the old mark stale, it finds no connection on the new skeleton, logs "Attempt to disconnect a
  nonexistent connection ... skeleton_updated" and then connects. With the path empty the first setter clears the mark
  without an error. `bone_name = bone_name` also looks the bone up again by name: a model with another bone order is
  not bound to the old index, and an empty skeleton is not connected (it logged "Index p_bone = 34 is out of bounds").
  **Seen:** gdstudio #860, 2026-11-09.
- **Approach:** Measure a seat against its bone, not the thing hung on it, to a few centimetres, in every frame of a
  crouch-walk after the swap, in the game scene as well as in the test arena, and check that the bone moved. **Watch out
  for:** the first test compared the pistol (0.13 m from its seat) with the hand 4 ticks after the swap against 0.35
  m. A seat left behind sits where the old hand last was, near the new hand while the pose has not changed (1.3 cm
  while aiming, 0.62 m after a crouch in the capture), so the same bug failed locally (0.71 m) and passed in CI, which
  the pose at the sample would explain (the CI run was not reproduced). **Seen:** gdstudio #860, 2026-11-09 (the three
  tests fail on `main` with 0.68 to 0.79 m and pass with the fix).
- **Approach:** Keep every unique name (`%Name`) off the path from the scene's owner to the model, and reference the
  slot from the `Character` by an export (`model`). **Watch out for:** `AnimationTree` sets its `root_node` to
  `get_path_to(model, true)` whenever its player changes, a path that starts at a unique node (`%Model/...`). Selecting
  the tree makes the editor copy it into an owner-less helper `AnimationPlayer`, which cannot resolve `%Name`: 9,632
  warnings and a freeze, in the unmodified template once the tree had filter paths (#836). **Seen:** gdstudio #844,
  2026-11-08 (0 `couldn't resolve track` warnings after; deleting the model still logs the engine's `invalid root_node`
  warning and one `!p_callable.is_valid()` error from the dock's undo bookkeeping, only while the tree is built in the
  editor, cause not found).

## The character controller {#controller}

<!-- new section: the controller page (gamedev) is engine-neutral; nothing held what the CharacterBody3D did here -->

- **Approach:** Lift a `CharacterBody3D` over a low edge with a probe made from its own shape (is something in the way,
  is there room above, is the way clear at step height, is there flat floor `radius + 0.06` past the edge) before
  `move_and_slide`, and test it on a 0.3 m and a 0.9 m block. **Watch out for:** a probe that looks down only one
  tick's motion ahead lands the capsule's rounded foot on the step's edge, reads a slanted normal (over 48 degrees) and
  refuses every step; the test saw the character stopped at a 0.3 m block that its step height of 0.32 allows.
  **Seen:** gdstudio #821, 2026-11-08 (fix: the probe looks `radius + 0.06` ahead).
- **Approach:** Make the movement direction `view.x * input.x + view.z * input.y` with the camera's flattened basis
  (`Basis(forward.cross(UP), UP, -forward)`) and an identity basis when there is no camera, and test the keys in a
  small arena with no camera first. **Watch out for:** the first version subtracted the `z` term, which pointed the
  opposite way and was invisible in a test that only held a key sideways. **Seen:** gdstudio #821, 2026-11-08; since
  gdstudio #901 the basis is the command's `yaw` (`PlayerCommand.world_move()`), and only `PlayerInput` reads the
  camera.
- **Approach:** A body never reads `Input` or a camera. It moves by `Character.step(command, delta)` alone: one
  `PlayerCommand` a physics tick, pulled from its `controller` (`PlayerInput`, the one script that reads the actions
  and the camera that draws its viewport) or passed in by a server or a test. Prove it with two instances in one world,
  with one stream in two `SubViewport` worlds (one camera looking elsewhere, one none) and with a grep of the body's
  source for `Input.`, `get_camera_3d(` and `get_viewport(`. **Watch out for:** the body read `Input` in 14 places and
  the camera in 2, so a second `player.tscn` walked in step with the first and died on the same key, and a headless
  server could not move one. **Seen:** gdstudio #901, 2026-11-10 (`test_two_characters.gd`; position, velocity and
  state bit-equal on all 780 ticks of `test_command_stream.gd` in two Jolt spaces of one process).
- **Approach:** Keep out of the step what only its owner or its picture knows: call `step` inside a physics frame with
  the physics step, show `facing` on the model through one null-safe method called in the tick, and on a fall out of
  the map say `fell` once and let the owner answer. **Watch out for:** `move_and_slide()` moves by the engine's own
  step whatever `delta` is passed; `model.rotation.y` written in the step fails on a body with no model (a server's),
  and moved to `_process` it would lose the engine's interpolation; the fall picked a spawn point with a generator
  seeded from the node path, which a server's body and a client's cannot share. **Seen:** gdstudio #901, 2026-11-10
  (the design review; `test_player_step.gd`).
- **Approach:** Split a body from its human by inheritance at the same node paths (`character.tscn` <-
  `character_dressed.tscn` <- `player.tscn`), give added nodes an `index=` so the tree keeps its old order, keep the
  group and the spawn on the subclass, and rename by a script with every reference listed first; then read the doc
  lines it changed. **Watch out for:** the class rename also rewrote six history entries about Deadnight's own
  `PlayerAnimation` in kit pages, and pushed nine comment lines past gdlint's 100 and markdownlint's 120 columns.
  **Seen:** gdstudio #901, 2026-11-10 (part 3; the action tour equal tick for tick against main); gdstudio #1012,
  2026-11-10 (a regex turning `.is_prone()` into the property `.prone` also rewrote the body's own
  `_prone.is_prone()` calls into `_prone.prone`; a grep for the new name found the twelve).
- **Approach:** Treat a command as hostile where it is stepped, not only where it is decoded: `step` replaces a command
  with a number that is not finite by one that asks for nothing, cuts a push to length 1, and reads the testing bit
  `ragdoll_pressed` only while `ragdoll_by_command` is on. A press (`jump_pressed`, `fire_pressed`,
  `interact_pressed`, `ragdoll_pressed`) is true in exactly one stepped command: whoever steps a command again calls
  `clear_edges()` first, and `merge_edges_from(earlier)` keeps the presses of a command that was never stepped.
  **Watch out for:** a NaN `yaw` made in script would make `facing` NaN for good through `lerp_angle`, a push of length
  1.4 moved 41 percent faster, and a command repeated with its presses jumps again on every landing (the test counts
  more than two jumps in 150 ticks, one when cleared). **Seen:** gdstudio #901, 2026-11-10 (the review).
- **Approach:** Take a camera's shake out of what the input sends (`PlayerInput` subtracts
  `PlayerCamera.current_shake()` from the heading, the pitch and the shot's ray when the drawn camera is the rig's
  own) and send the crosshair's ray as its own origin and angles. **Watch out for:** the rig turns the lens by
  `yaw + shake`, so a sprint shake would steer the walk on every footfall and a shot kick would be in the next shot;
  and an over-the-shoulder lens (`h_offset`, `v_offset`) starts the ray through the middle of the screen beside the
  camera's axis (over 0.4 m in the test), so the shot block is not the view's `yaw` and `pitch`. **Seen:** gdstudio #901,
  2026-11-10 (`test_player_input.gd`).
- **Approach:** Share a run-time key on an `InputMap` action by counting its holders (`PlayerInput` keeps a static
  count per key and the last holder takes the event off). **Watch out for:** `InputMap.action_add_event` does nothing
  for an event the action already has, and `action_erase_event` removes the one event equal to the one passed, so a
  second character added its `ragdoll` key (ignored) and, when it left, took the first character's key with it; the
  two-character test read an empty action. **Seen:** gdstudio #901,
  2026-11-10 (`test_two_characters.gd`).
- **Approach:** Move a moving body with `Character.teleport()` (or the player's `respawn()`), which resets physics
  interpolation and tells the camera to cut. **Watch out for:** setting `global_position` directly sends a damped
  Phantom Camera flying across the map for about 0.9 s, so a test that waited 40 ticks saw the lens 5 m from where it
  belonged. **Seen:** gdstudio #821, 2026-11-08.
- **Approach:** Give each character its own spawn generator (seeded from its node path, so a test repeats) and let
  `SpawnPoint.pick()` pass over a point already picked in the same physics frame; read the spot from
  `spawn_transform()` so a point's `radius` counts. **Watch out for:** every `Player` seeded its generator with 1, so
  two characters in one world stood on the same point (0.00 m apart), and `respawn()` read the point's transform
  directly, so `radius` did nothing for the player. **Seen:** gdstudio #922, 2026-11-10.
- **Approach:** Prove an interaction against the real physics world with a few ticks of a real key, pad button or touch
  event through `Input.parse_input_event` and the project's `InputMap`, in a small arena with a floor, and keep the
  sample map's own numbers (a jump a block high, steps lower than the step height) in a test of the tuning. **Watch out
  for:** GdUnit4 prints that input events do not work headless; an action key, a pad button and a pad axis do reach
  `Input.is_action_pressed` and `get_vector`, but the mouse cannot be captured (`Input.mouse_mode` stays visible), so
  the camera has `require_captured_mouse` and the test turns it off. **Seen:** gdstudio #821, 2026-11-08.
- A prop is pushed by giving it the share of the player's speed its mass allows, as an impulse along the contact normal;
  a test holds that a 5 kg crate moves more than twice as far as a 200 kg one in a second. A `TriggerZone` counts
  characters and props by default (its mask, and `counts` behind it) and a `Pickup` only characters (its mask, and
  `characters_only`); a camera zone still says `player` in `required_group` so that a pushed crate does not take the
  view. Every body is on a named layer ([Physics layers](../physics-layers.md#template-layers)).

## A second kind of controller {#second-controller}

<!-- new section: the controller section says how the human's body moves; nothing said how anything else (an AI, a
     server, a recording) drives the same body, which #904 and #963 build on -->

A character is driven by whatever gives it a `PlayerCommand` each physics tick. Three ways, all through `step`:

| Who | How |
| --- | --- |
| A node of its own (an AI) | Start from `gameplay/character/character_dressed.tscn` (the body with its model; `character.tscn` is the body alone, for a server), add the controller as a child, extend `CharacterController`, override `sample() -> PlayerCommand`, and set it as the body's `controller`. Keep the world directions (where to walk, where to look) and build the command once in `sample()` with `set_from_world(walk_direction, look_direction, strength)`: a zero look leaves the view level along -Z and a body that is not aiming faces where it walks; with `aim` or `fire` the body turns to the look. |
| An owner that steps (a server, a director with a budget) | `body.set_physics_process(false)`, then `body.step(command, delta)` inside the physics frame, with the physics step. Connect `fell` to decide where the body starts again, and turn `ragdoll_by_command` off for commands from a network. |
| A test | `tests/fixtures/command_driver.gd`: `CommandDriver.take(player)` and `run(tree, players, command, ticks)`, which steps the presses once; `tests/fixtures/route_controller.gd` is a scripted controller that walks a list of points. |

`Character` (`gameplay/character/character.gd`) is the body and joins no group; `Player` extends it with what only the
human has: the group `player`, which the HUD, the minimap and a camera zone's trigger look for (so an AI's character
is never taken for the player), the start at a `SpawnPoint` of that group and again on `fell`, and `input_enabled` and
`ragdoll_key`. The scenes inherit one another at the same node paths: `character.tscn` (capsule, `CameraTarget`,
`Interactor`, a `Weapon` with no muzzle) <- `character_dressed.tscn` (the `Model` slot, `AnimationPlayer`,
`AnimationTree`, `Animation`, `Footsteps`, `Ragdoll`, the weapon's muzzle) <- `player.tscn` (`PlayerInput`).
`character.tscn` and `character_dressed.tscn` step one stream of commands to the same positions, velocities and
states on every tick, and their shots fly the same way from starts within `no_muzzle_offset`
(`test_character_split.gd`). The character's code reads no `Input`, camera or viewport: `test_player_step.gd` reads
every script of `gameplay/character/` and `gameplay/weapon/`.

Over a network the command is what crosses the wire: one per tick with a sequence number, applied once and in order by
the server ([the pattern that worked](../multiplayer.md#own-protocol)).

`sample()` hands out the controller's own command, written again on the next call (`clone()` to keep one), and a press
is true in exactly one returned command. `Character.state_snapshot(into)` and `restore(state)` take and put back what
the
next step reads (`CharacterState.FIELDS`; a test fails when the body gains a variable that is neither there nor on the
test's list of what is not step state). A restore and the same commands gave the same path to the last digit on the
floor and from mid-air over 120 ticks, and the weapon's cooldown and its place in the spread's order go with it
(`CharacterState.weapon`). A character shoots along `Character.aim_ray()`: the command's shot block, or with none (an AI,
a test) from its eye along the command's view ([Crouch, aim and shoot](shooting.md#crouch-aim-shoot)). It is for
placing a body at a known state, not for replay: a step also pushes
props, uses doors, fires projectiles and collects pickups, and the engine's floor contact cannot be set from script.

- **Approach:** Between two runs of a body taken with `CommandDriver.take`, step it with an empty command for as long
  as it needs to settle (the arm down, the cooldown out) and assert that it did. **Watch out for:** a taken body
  changes only when it is stepped: awaiting 30 frames left the arm up, and the second run of a shot-threshold test
  fired on its first tick. **Seen:** gdstudio #901, 2026-11-10 (part 3, `test_character_tuning_more.gd`).

What it costs (`tools/bench/player_step_bench.tscn`, microseconds a body a physics tick for 1, 8 and 40 bodies; the
body's own tick, with no animation or camera): stepped by commands a body costs what it did when it read the keys
itself, and the sampler adds 3 to 9 µs a tick for each human.

| | 1 body | 8 | 40 |
| --- | ---: | ---: | ---: |
| Desktop, before (the body reads `Input`) | 34 | 24 | 21 |
| Desktop, `PlayerInput` then `step` | 40 | 27 | 24 |
| Desktop, `step` with a command | 34 | 23 | 21 |
| Chrome, before | 67 | 30 | 24 |
| Chrome, `PlayerInput` then `step` | 76 | 35 | 28 |
| Chrome, `step` with a command | 58 | 28 | 24 |
| Chrome at a 4x CPU throttle, before | 386 | 172 | 125 |
| Chrome 4x, `PlayerInput` then `step` | 409 | 195 | 147 |
| Chrome 4x, `step` with a command | 354 | 164 | 119 |

The desktop rows are the mean of two or three headless runs, the browser rows one run each of the web export in
headless Chrome (`tools/bench/player_step_bench.py`, under `gds quiet`), on a machine other agents were using.

## Prone and the crawl {#prone}

<!-- new section: the controller section covers standing and crouched moves; nothing said how the template lies a
     body down, crawls, fits under a gap and gets up, or where its defaults come from (gdstudio #1012) -->

The character lies down and crawls below crouch. It is its own module beside the body's other moves:
`CharacterProne` (`gameplay/character/character_prone.gd`) holds the stance (down or not, how far down, the time off
the ground) and what lying changes; `ProneTuning` (`prone_tuning.gd`, the player's `prone_tuning.tres`, the
`Character`'s `prone_tuning` in its Prone group) holds every number. The body asks the module once a step from the
command's held `prone` bit, so a server, a bot or a test lies a body down by sending that bit
(`CommandCodec.F_PRONE`, bit 15; `NetWire.VERSION` 3), and the stance is saved and put back with the rest of the step
state (`CharacterState.prone`). The human's `PlayerInput` turns the `prone` action (Z, the pad's d-pad down, the
Prone touch button) into that bit by the tuning's `input_mode`: a toggle (the default), a hold, or a long hold of
crouch (`crouch_hold_time`) with a press of crouch to get up; a jump or a sprint press gets up (`jump_gets_up`,
`sprint_gets_up`).

- **Down and up.** Going down takes `enter_time` and getting up `exit_time`; the capsule shrinks from the top to
  `height` and `radius` and the camera's target to `camera_height`, eased by the module's `share()`. A lying body is
  crouched underneath, so getting up ends at the crouch height and stands over the crouch time when crouch is let go
  and there is room (or stays crouched under a low ceiling). Getting up needs a crouched capsule's room above
  (`CharacterProne.has_room`, the stand probe's shape at the crouch height): under a gap only a lying body fits, it
  stays down. Off a ledge it stays down `air_time`, then gets up; it lies down again on landing while the bit is held.
- **The crawl.** `crawl_speed` ahead, `sideways_share` and `backward_share` of it to the side and behind (by the angle
  between the push and the facing), `aim_move_share` of it while aiming, its own `acceleration`, `deceleration` and
  `turn_speed` (a body on the ground turns slowly), and no crawl while going down or up unless
  `move_while_changing`.
- **Aim.** `aim_allowed` and `fire_allowed`; the weapon's spread times `spread_share` (`Weapon.spread_share`, set by
  the body each step); the look held to `look_up_limit` and `look_down_limit` (the view, the aim pose and the aim ray,
  so an AI is held too), and `PlayerCamera.pitch_limits()` draws the orbit in to the same limits as the body lies down.
- **The picture.** `Character.State.PRONE` (after `DEAD`, so the snapshot's state byte keeps its old numbers),
  `prone_changed(down)`, the read-only `prone` and `prone_amount`. `CharacterAnimation` has a `prone` state: the prone
  idle at `prone_idle_pace`, the crawl clip blended in by ground speed and played at `ground speed / crawl_clip_speed`,
  and `to_prone_clip` and `to_crouch_clip` played over the body for the enter and exit times. Until the template's own
  clips land (gdstudio #1009), the placeholder is the library's swim stroke held on its first pose for the idle and
  played for the crawl, lifted and moved ahead by `prone_pose_offset` (the stroke floats under a water line) and
  tipped by `prone_pose_lean`; with real clips the offset and the lean are zero.

The defaults, from shipped third-person and squad games (the numbers are measured or published by players, not the
studios; the template's run is 4.0 m/s and its walk 1.7):

| Setting | Default | Why |
| --- | --- | --- |
| `crawl_speed` | 1.0 m/s | PUBG crawls at 1.2 m/s against a 1.7 m/s walk ([PUBG wiki](https://pubg.wiki.gg/wiki/Movement_Speed)); Battlefield V at 0.85 m/s against 3.4 ([Symthic](https://sym.gg/legacy/pages/bfv/bfv_generalinfo.html)); between the two, under the template's 1.5 m/s crouch walk. |
| `backward_share`, `sideways_share` | 0.7, 0.8 | Arma 3: sideways about 80 % and backwards about 70 % of forward in every stance, from a 2013 post in [Bohemia's movement thread](https://forums.bohemia.net/topic/144224-movement-speed-tweaking/). |
| `aim_move_share` | 0.5 | Battlefield V halves the prone speed while aiming (0.425 of 0.85 m/s). |
| `enter_time`, `exit_time` | 0.5 s, 0.7 s | Battlefield V: 500 ms to go prone, 700 ms from prone to a sprint. The #1009 clips are 0.9 s and 1.0 s at their own pace and are played to these times. |
| `turn_speed`, `aim_turn_speed` | 3, 6 rad/s | A quarter of the standing turn (12) and a third of the standing aim turn (18): Arma's players ask for a slow, single-speed turn on the ground, not a snap. |
| `acceleration`, `deceleration` | 10, 12 m/s² | Up to the crawl in 0.1 s: a lying body has no burst. |
| `height`, `radius` | 0.6 m, 0.28 m | A soldier on elbows is about 0.4 to 0.5 m high; the capsule stands upright, so it is a little taller and covers the raised head. A 0.8 m gap fits it and not the 1.1 m crouch. |
| `camera_height`, `look_up_limit`, `look_down_limit` | 0.55 m, 12, 40 degrees | Arma's players note the short look up lying down. With the 1.7 m camera, 12 degrees up keeps the lens about 0.3 m over the floor; 20 put it 7 cm over (below). |
| `spread_share` | 0.5 | Lying is the steadiest stance in PUBG and Battlefield. |
| `input_mode`, `crouch_hold_time` | toggle, 0.5 s | PUBG (Z) and Ghost Recon Breakpoint (its own prone button) toggle; Metal Gear Solid V and the pads hold the stance button ([Konami](https://eu-support.konami.com/hc/en-gb/articles/9667348797975-Metal-Gear-Solid-V-Sneaking)). |
| `jump_gets_up`, `sprint_gets_up` | on, on | A jump press in PUBG and a sprint in Battlefield get up instead. |

What it costs (`tools/bench/player_step_bench.tscn`, `prone` mode: lying and crawling 80 % of the time, getting up
every 5 s; microseconds a body a physics tick, 40 bodies, two headless desktop runs on a shared machine): main's
`commands` 32.7 and 28.0, this branch's `commands` 31.4 and 32.5, `prone` 32.4 and 31.2. Lying costs what standing
does; the only new query is the room check, made only while a body that was let go of is still down. On the web the
same ratio is expected (the bench's browser rows track the desktop's within a few microseconds at 40 bodies); nothing
of the stance is sent but the command's bit, and the cosmetic placeholder pose is set on the model in `_process`.

- **Approach:** Derive a prone camera's look-up limit from the follow distance and the target height (`target +
  offset - distance * sin(limit)` stays over the floor by more than the spring arm's margin) and test the lens height
  in the real map with the stick held up. **Watch out for:** a limit taken from aim comfort alone (20 degrees) put the
  lens 7 cm over the floor, 2 cm from the near plane; the spring arm meets the floor at a grazing angle, so its margin
  is along the arm, not up. **Seen:** gdstudio #1012, 2026-11-10 (`test_prone_camera.gd`; 12 degrees keeps 0.3 m).
- **Approach:** Lay a placeholder on the ground with a pose offset on the model inside its slot, applied by how far
  down the body is and nothing at all while it is zero, and look at the capture before picking the clip. **Watch out
  for:** the crouch clips tipped forward still knelt, and the library's swim stroke is horizontal but floats under a
  water line (0.42 m low) with a treading idle; the stroke held on its first pose (`prone_idle_pace` 0) is the idle.
  **Seen:** gdstudio #1012, 2026-11-10 (captures of three tries).
- **Approach:** Keep a body's stance changes out of its state names when the capsule is what matters: getting up from
  prone passes the crouch height on the way (test the height the tick the stance reaches zero), and the state goes
  from `PRONE` to `IDLE` as a released crouch does. **Watch out for:** a test that expected a `CROUCH` state between
  them failed, though the capsule went through crouch. **Seen:** gdstudio #1012, 2026-11-10.
- **Approach:** When a body gains a stance, expose its reads as read-only properties (`var prone: bool: get:`) rather
  than methods, and split a suite at 18 tests. **Watch out for:** gdlint's twenty public methods counts every
  `func`, so three small getters took `Character` from 18 to 21 and failed the hook. **Seen:** gdstudio #1012,
  2026-11-10.

## Ragdoll {#ragdoll}

<!-- new section: the template gained death and a ragdoll (gdstudio #846) and nothing said how it is built or tuned -->

The character dies into a ragdoll and gets up again (`Character.die()`, `revive()`, the `CharacterRagdoll` component and
its inspector). What the template does with it, every export, and why the bones are generated and the engine is Jolt are
in [Ragdoll in 3D Third Person](../ragdoll.md#template), beside how the engine behaves.

## Touch controls {#touch-controls}

<!-- new section: ui-controls.md has the Deadnight lessons; this is the reusable component and how it was proved -->

`TouchControls` is in the base (`ui/touch/`): instance `touch_controls.tscn`, add or move its `TouchButton` nodes under
`SafeArea/Buttons` (an action and a word each; the Jump and Use buttons are there) and connect `look_turned` to whatever
turns the view. It presses the game's actions, so no gameplay code changes. Everything you see is a node you arrange in
the 2D editor: `TouchStick` (drag it to move where the stick waits), the `MoveZone` and `LookZone` panels that decide
which finger does what, and the `SafeArea` box that keeps the controls off the device's notches. The script is `@tool`,
so the editor shows the controls even when `show_mode` hides them in the game.

- **Approach:** Prove a touch layer in the real web export in a mobile-emulated browser: `Input.dispatchTouchEvent`
  through a CDP session, a probe node that writes the state to `window.gdprobe` when the page has `?probe`, a look drag
  of N canvas pixels against `N * look_sensitivity` degrees, the stick moving the character along the camera heading and
  turning nothing, a tap jumping, and two fingers at once. **Watch out for:** a CDP `touchEnd` lifts the fingers it
  lists, so listing the fingers that stay down lifted the stick too and listing only the lifted one kept the other
  down; and a "keeps moving" check read 0.00 m with the character against the room's wall. **Seen:** gdstudio #821,
  2026-11-08 (`tools/web_smoke/touch_smoke.py`: 11 of 11 checks, no console error).
- Test the layer headless by calling its `_input` with canvas coordinates (a node receives canvas pixels) plus one test
  through `Input.parse_input_event` with the window pixels (`get_final_transform() * canvas`): two fingers, a drag
  whose `relative` is 1454 and wrong, mouse motion that must do nothing, a key that hides the layer, and the turn
  spread over frames (call `_turn_view(1/60)` by hand: a test run's frame time is not 1/60).
- The layer is hidden until the first touch (or when the device reports a touch screen), hides again for a key or a pad
  button, never for a mouse, and switches `Input.emulate_mouse_from_touch` off while it shows. Buttons are 170 canvas
  pixels (122 are 44 points on a 390-point-high phone); the export's `head_include` sets `viewport-fit=cover` and
  `touch-action: none`.
