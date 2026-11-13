# The character and its model

<!-- new section: split out of the third-person template page when it reached the size limit (#983) -->

The 3D Third Person character: the animation libraries, the mannequins, replacing the model, the controller, the
slide, the ragdoll and touch controls. Part of [the 3D Third Person template](../third-person-template.md).

## The animation libraries {#animation-libraries}

<!-- new section: a pointer left when the section moved to its own page at the size limit (#1016) -->

Moved to [The character's clips](clips.md#animation-libraries).

## The vault clips {#vault-clips}

<!-- new section: a pointer left when the section moved to its own page at the size limit (#1016) -->

Moved to [The character's clips](clips.md#vault-clips).

## The bodies {#mannequins}

<!-- new section: the template shipped one mannequin under a neutral name; #843 added the other and named both -->

**The template's characters wear GDStudio's own prototype mannequins in the `form` look** (kit #1187, the look the
maintainer chose on #1172): the player, the friendlies (ally, civilian) and the online puppets `form_female.glb`,
held by `character_dressed.tscn`; the enemies (grunt, shooter) `form_male.glb`, set as `CharacterModel.variant` in
their scenes. `CharacterBodies` (`gameplay/character/character_bodies.gd`) names the two paths once; the fixtures,
benches and captures that pose "the template's body" read them there. The bodies are in `assets/characters/prototype/`
(`<look>_<body>.glb` for the looks `form`, `joint` and `facet` and the bodies `male`, `female` and `chibi`), generated
by `build_mannequins.py` on the library's 65 bones plus 17 leaves (twist bones, sockets, IK targets), so both
libraries play on them with no conversion ([Prototype mannequins](../../../tools/blender/prototype-mannequins.md),
[the rig](../../../tools/blender/mannequin-rig.md)). Their import script (`mannequin_import.gd`) sets the skeleton's
`motion_scale` (0.545 on the chibi), adds the `MannequinTwist` modifier and shows the three levels of detail by
distance. The `joint` and `facet` looks and the chibi stay in the folder as variants a game can swap in.

What was measured on the Quaternius skins is measured again on the two `form` bodies:

- **The pistol's hold is solved per body.** The prototype hands are a person's size and differ (0.181 m and 0.195 m
  from wrist to fingertip against the library rig's 0.232 m), so one pose cannot close both; the solver works on one
  body at a time (`solve_pistol_hold.py --body=female|male`). The female's hold is the hold scene's own (the eight
  `pistol_*_pose.tres`, the pistol's seat and markers in `pistol_held.tscn`, `support_way`); the male's is one
  `HoldFit` file (`gameplay/weapon/hold/pistol_fit_male.tres`) listed in `WeaponHold.fits`, which the hold puts on
  whenever the model is a `form_male.glb` ([the hold](../../../tools/blender/weapons.md#the-third-person-template-pistol)).
- **The rifle's hold is solved per body too** (kit #1040): `solve_rifle_hold.py --body=female|male`, the female's in
  `rifle_held.tscn` and the five `rifle_*_pose.tres`, the male's in `rifle_fit_male.tres`, listed in
  `TwoHandHold.fits`. The smaller hands also needed a place of their own on the grip
  ([the rifle in both hands](weapon-pickups.md#rifle-hands)).
- **The hit zones** (`character_dressed.tscn`'s `HitZones`) are sized from `tools/mannequin/measure_segments.gd`: the
  arms are longer and thinner than the Quaternius female's (upper arm 0.26 to 0.28 m long and 0.047 to 0.057 m
  round, against 0.22 and 0.068) and the calves thinner, so the arm zones are longer and narrower, the thigh and pelvis
  zones a little wider, the head sphere smaller and lower.
- **The ragdoll's capsules** (`RagdollBodies`) were within both bodies' skin already; only the calves are thinner
  (0.055 m). Its joints and limits read rotations from the clips, which the bodies share with the library rig, so
  they stand ([Ragdoll](../ragdoll.md#template)).
- **The prone clips are solved per body** (kit #1293): `prone_form_female.glb` is the dressed character's
  library `prone` and `prone_libraries` names `prone_form_male.glb` for `form_male.glb` and the Quaternius files
  for the Quaternius mannequins ([prone and the crawl](moves.md#prone)). In the Quaternius female's file the `form`
  bodies lay 3.3 to 5.5 cm in the floor at the forearms.
- **The pistol stays on `hand_r`**, not the rig's `socket_hand_r`: the hold is solved in the hand bone's space and
  the Quaternius mannequins, which a game can still swap in, have no sockets.

**The Quaternius mannequins stay** in `assets/characters/mannequin/`, CC0, on the same rig: `mannequin_female.glb`
(the pack's `Mannequin_F.glb`, 1.4 MB) and `mannequin_male.glb` (0.6 MB). The clip checks that were made on them
(vault, prone, limb overlap) still pose them. The pack has no model-only file for the male: he is the `Mannequin` mesh
inside `UAL1_Standard.glb` and `UAL2_Standard.glb` (byte for byte the same mesh, skin and skeleton in both), so
`mannequin_male.glb` is `UAL1_Standard.glb` with its 43 clips removed, by `tools/models/strip_glb_animations.py` (it
copies the nodes, mesh, skin and materials as they are and drops only the animation data; no Blender round trip,
which would have renamed and re-ordered things). The sha256 of the source and of the result are in the folder's
`LICENSE.md`.

**To use another body**, swap the model ([the editor steps below](#replacing-the-model)) in `character_dressed.tscn`
(everyone) or set `variant` in a character's scene, point `CharacterBodies` at it, and solve the hold for it: dump
the rig, run `solve_pistol_hold.py --body=<name> --search-seat --search-left` and `write_hold.gd -- <hold.json>
<name>` (`tools/hold/`). A body with no fit keeps the hold scene's own, which closes a hand of another size badly.
Give it prone clips of its own as well (`build_prone_clips.py --body <name>` with its numbers in `BODIES`, the file
named in `prone_libraries`), or the file of the body whose upper arm is nearest in length.
Then run `measure_segments.gd` and size the hit zones, and run the hold, ragdoll and hit zone suites.
`tests/assets/test_prototype_mannequins.gd` proves the bodies and `tools/capture/mannequin_parade.tscn` films them on a
0.25 m grid: `PARADE_LOOK` chooses the look, `PARADE_VIEW` the front, quarter, side or close view, `PARADE_CLIP` loops
one clip and `PARADE_REFERENCE=1` adds the Quaternius male.

**GDStudio's own prototype bodies** are beside them in `assets/characters/prototype/` (kit #1149): `<look>_<body>.glb`
for the looks `form`, `joint` and `facet` and the bodies `male`, `female` and `chibi`, generated by
`build_mannequins.py` on the same 65 bones plus 17 leaves (twist bones, sockets, IK targets), so both libraries play
on them with no conversion ([Prototype mannequins](../../../tools/blender/prototype-mannequins.md),
[the rig](../../../tools/blender/mannequin-rig.md)). Their import script (`mannequin_import.gd`) sets the skeleton's
`motion_scale` (0.545 on the chibi, so the hips' keys fit its legs), adds the `MannequinTwist` modifier and shows the
three levels of detail by distance. The Quaternius female stays the default until the maintainer has chosen a look:
the pistol's solved hold, the ragdoll's joints and the hit zones are measured on the Quaternius skins and are solved
again for the body that replaces them. `tests/assets/test_prototype_mannequins.gd` proves the bodies and
`tools/capture/mannequin_parade.tscn` films them on a 0.25 m grid: `PARADE_LOOK` chooses the look, `PARADE_VIEW` the
front, quarter, side or close view (the close one follows the hands through a hand roll, the pistol clips and a
reach), `PARADE_CLIP` loops one clip for whole cycles and `PARADE_REFERENCE=1` adds the Quaternius male.

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

- **Approach:** When the template's body changes, solve each body's hold on its own and give each body its own
  `HoldFit` (chosen by the model's file), then run the whole template suite, not only the hold, ragdoll and hit
  suites. **Watch out for:** the old solver asserted that the two skeletons match from the hands down; the reload's
  carry swing put the gun 9 and 29 mm past the left hand's reach on the new bodies, which the solver's aim-only reach
  table missed (the swing now fades with the reload); and three numbers measured on the old body sat in suites that
  never name it: the node count, `Weapon.no_muzzle_offset` and the crawl's planted elbows (1.5 to 2.6 cm of slide on
  the longer upper arms, gdstudio #1286). **Seen:** gdstudio #1187, 2026-11-11.

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

**A second look without deleting** (kit #969): an inherited character scene cannot delete its base's model, so
`CharacterModel.variant` takes another model of the same rig. When the game runs the slot frees the scene's model and
puts the variant in its place at `_ready` (the seats and clips follow as for a swap); in the editor it draws the
variant as an internal child and hides the scene's model through `RenderingServer` alone, so the scene saves nothing.
The enemies of [the AI section](ai-characters.md#parts) set the male body (`form_male.glb`) on the female base this way.

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
- **Approach:** Before seating an attachment, drop any `skeleton_updated` connection the skeleton still holds to it
  (`CharacterModel._drop_connection`). **Watch out for:** a pooled character whose model was swapped at run time (a
  `variant`) re-entered the tree, the attachment connected itself on entering, and the seat's setters then logged
  "already connected" for each spawn. **Seen:** kit #969, 2026-11-11 (`test_ai_spawner.gd`, a spawn of a parked male).
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
  server could not move one. **Seen:** gdstudio #901, 2026-11-10 (`test_two_characters.gd`, bit-equal in
  `test_command_stream.gd`); gdstudio #1138 and #1258, 2026-11-11 (a throttle,
  then a rifle hold).
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
- **The body's modules.** `Character` (`gameplay/character/character.gd`) keeps the public API (the signals, the
  exports, `step`, `die`, `revive`, `take_hit`, `teleport`, the reads), the step's order in `_move` and the moves every
  stance shares (steer, jump and gravity, crouch, aim, the state); each other part is a file of its own beside it,
  which the body calls once from that order:

  | Part | Module | Its step state |
  | --- | --- | --- |
  | Lying down and the crawl ([its page](moves.md#prone)) | `CharacterProne` (`character_prone.gd`), an instance `_prone` | `CharacterState.prone` |
  | Sliding ([its page](moves.md#slide)) | `CharacterSlide` (`character_slide.gd`), an instance `_slide` | `CharacterState.slide` |
  | Vaulting and mantling ([its page](traversal.md#how)) | `CharacterVault` (`character_vault.gd`), the instance `vault_motion` | `CharacterState.vault` |
  | Pushing a prop | `CharacterPush.push_props(body, before, delta)` (`character_push.gd`), static | the body's `_push_cap`, `_push_hold` |
  | Dying and getting up | `CharacterDeath` (`character_death.gd`), static: `die`, `revive`, the dead tick | none (death is an event) |
  | The capsule and the eye point | `CharacterCapsule` (`character_capsule.gd`), static: `height`, `fit`, the room to stand | none |
  | An AI's lean tick (#1059; the aim and the trigger since #1104) | `CharacterLean` (`character_lean.gd`), static, when `lean_step` is on | none |
  | Taking and putting back a snapshot | `CharacterState.take(body)`, `put_back(body)` (`character_state.gd`) | it is the step state |
  | Health, using things, steps | the `Health` child ([Health](../third-person-hits.md#health)), `Interactor` ([Interact](interact.md#interactable)), `StepClimber` | none |

  A new move goes in a module of its own the same way: a `RefCounted` with a `drive`/`step` function the body calls
  once in `_move` (a static one when it keeps nothing between ticks), its numbers in a tuning resource of its own, and
  any step state it keeps in an array of `CharacterState` written in `take()` and read in `put_back()`. A new
  variable on the body itself goes in `CharacterState.FIELDS` or on `test_character_state.gd`'s `NOT_STATE` list; a
  static module adds none. A module that can have work on a tick an AI only walks (a timer, a probe, a held bit) also
  goes in `CharacterLean.can_take()`, which sends that tick to the full `_move`; `test_character_lean.gd` steps a lean
  and a full body side by side and fails on the first tick their snapshots differ.
  Keep `character.gd` well under gdlint's 1000 lines
  ([project conventions](../project-conventions.md#rules)): #1041 moved the push, the death, the capsule and the
  snapshot out when it reached 1000. It is also at gdlint's twenty public methods (19 on 2026-11-11), so a new public
  function goes on a module, not on the body; and `test_ragdoll.gd`
  (`test_the_character_the_player_and_the_ragdoll_pin_their_exports`) pins every export of `Character` and `Player`,
  so a new export adds its line there in the same change (#1011, #1013).

## A second kind of controller {#second-controller}

<!-- new section: the controller section says how the human's body moves; nothing said how anything else (an AI, a
     server, a recording) drives the same body, which #904 and #963 build on -->

A character is driven by whatever gives it a `PlayerCommand` each physics tick. Three ways, all through `step`:

| Who | How |
| --- | --- |
| A node of its own (an AI) | The template's is `AiController` on `gameplay/ai/ai_character.tscn` ([AI characters](ai.md)). For another kind, start from `gameplay/character/character_dressed.tscn` (the body with its model; `character.tscn` is the body alone, for a server), add the controller as a child, extend `CharacterController`, override `sample() -> PlayerCommand`, and set it as the body's `controller`. Keep the world directions (where to walk, where to look) and build the command once in `sample()` with `set_from_world(walk_direction, look_direction, strength)`: a zero look leaves the view level along -Z and a body that is not aiming faces where it walks; with `aim` or `fire` the body turns to the look. |
| An owner that steps (a server, a director with a budget) | `body.set_physics_process(false)`, then `body.step(command, delta)` inside the physics frame, with the physics step, or a whole number of them for a body stepped less often (the `AiDirector` steps a far character every 4th tick with four ticks' time, and the move goes as far: [AI characters](ai.md#schedule)). Connect `fell` to decide where the body starts again, and turn `ragdoll_by_command` off for commands from a network. |
| A test | `tests/fixtures/command_driver.gd`: `CommandDriver.take(player)` and `run(tree, players, command, ticks)`, which steps the presses once; `tests/fixtures/route_controller.gd` is a scripted controller that walks a list of points. |

`Character` (`gameplay/character/character.gd`) is the body and joins no group; `Player` extends it with what only the
human has: the group `player`, which the HUD, the minimap and a camera zone's trigger look for (so an AI's character is
never taken for the player), the start at a `SpawnPoint` of that group and again on `fell`, and `input_enabled` and
`ragdoll_key`. The scenes inherit one another at the same node paths: `character.tscn` (capsule, `CameraTarget`,
`Interactor`, a `Weapon` with no muzzle, its `Health`: [Hit zones](../third-person-hits.md#health)) <-
`character_dressed.tscn` (the `Model` slot, `AnimationPlayer`, `AnimationTree`, `Animation`, `Footsteps`, `Ragdoll`, the
weapon's muzzle) <- `player.tscn` (`PlayerInput`). `character.tscn` and `character_dressed.tscn` step one stream of
commands to the same positions, velocities and states on every tick, and their shots fly the same way from starts within
`no_muzzle_offset` (`test_character_split.gd`). The character's code reads no `Input`, camera or viewport:
`test_player_step.gd` reads every script of `gameplay/character/` and `gameplay/weapon/`.

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

## What the parts cost {#parts-cost}

<!-- new section: the step bench timed the body alone; nothing said what a dressed character's other parts or the world
     parts cost a frame, which an AI crowd and the web build multiply -->

`tools/bench/parts_cost_bench.tscn` (gdstudio #926) prints what the parts cost a frame: a crowd of
`character_dressed.tscn` with a walking stand-in controller (an AI's body), each character part timed apart with its own
processing off and called by hand, a first death, and 100 of each world part against an empty arena. The web numbers
come from its export in headless Chrome (`tools/bench/parts_cost_bench.py`, under `gds quiet`). A frame's "work" is from
its first physics tick to its last node processed (the scripts, the animation and the physics step, not the drawing).
`tests/gameplay/test_parts_budget.gd` holds the counts tight in CI and ten walking characters' frame loosely, as a
multiple of a calibration loop.

| Median frame work, ms | 1 | 10 | 25 | 50 walking |
| --- | ---: | ---: | ---: | ---: |
| Desktop, before #926 | 0.22 | 0.99 to 1.01 | 2.24 to 2.39 | 5.16 to 5.59 |
| Desktop, after | 0.21 | 0.74 to 0.84 | 1.47 to 1.54 | 3.23 to 3.28 |
| Chrome, before | 0.3 | 1.1 to 1.2 | 2.6 to 3.2 | 6.5 to 9.4 |
| Chrome, after | 0.3 | 0.8 to 1.0 | 1.9 | 3.8 to 4.1 |

| µs a character a frame (25 walking) | Step | Animation script | Tree | Footsteps | Ragdoll |
| --- | ---: | ---: | ---: | ---: | ---: |
| Desktop, before | 29 to 30 | 5.7 | 22.6 to 23.0 | 14 to 16 | 14.5 |
| Desktop, after | 23 to 26 | 2.6 to 3.1 | 21.4 to 23.2 | 14 to 15 | 3.4 to 3.9 |
| Chrome, before | 35 | 6.7 to 7.0 | 20 to 22 | 22 | 18 to 19 |
| Chrome, after | 30 | 4.5 to 4.8 | 21 | 23 | 4.6 to 5.2 |

What changed: the ragdoll's bones are made on the first death ([Ragdoll: cost](../ragdoll.md#cost)), so a living
character is 29 nodes and one physics body instead of 62 and 17 (53 and 2 with the hit zones of #876, the weapons
of #887, the pistol hold of #1001 and the `Health` of #925; the body's own step is cheaper with 16 fewer bodies in the
space); the pose the death needs is sampled into arrays made once; the animation tree's parameter paths are constants
and the blend spaces follow the tuning's `changed` (the four speeds say it) instead of comparing an array every frame. A
first death costs 0.45 ms on the desktop and 1 ms in Chrome (bones from a pool, #1022). A standing `Target` is no longer
processed (1 µs each before, 0 after); a `Door` keeps the characters in its range from its sensor's signals instead of a
query a tick (1.9 to 2.1 µs each, 1.4 to 1.6 after); a `Pickup` finds its `Visual` once (2.2 to 2.4 µs, 1.8 to 2.0
after); a lone `Weapon` costs 0.2 to 0.3 µs (a character's is ticked by its step). The level holds 11 pickups, 4 targets
and 2 doors, under 40 µs together.

What is left: the step and the tree. The footsteps' 14 µs was almost all starting a sound: a walking character starts
about two steps a second, and `AudioStreamPlayer3D.play()` of an Ogg Vorbis step cost about 250 µs on the desktop (the
decoder is set up for every play; with the step list emptied the part costs 1.6 µs). Since gdstudio #1023 the steps
play decoded to PCM once (`DecodedSounds` of `gds_game`, [Audio: starting sounds](../audio.md#starting-sounds)), and a
WAV starts in about 1 µs:

| Footsteps, µs a character a frame (25 walking) | Before #1023 | After |
| --- | ---: | ---: |
| Desktop | 12.9 to 13.7 | 2.25 to 2.30 |
| Chrome | 22.1 to 22.3 | 7.0 to 7.9 |

The four steps decode once for every character (shared), when the first `Footsteps` is ready: about 2 ms on the
desktop and 7 to 16 ms in Chrome, inside the first character's spawn (65 to 68 ms before, 72 to 84 after, in Chrome).
The samples are the decoder's own (16-bit), so the steps sound as before: Movie Maker mixes before and after differ by
-65 dB (25 walkers) and -70 to -83 dB (the action tour's walking), 16-bit rounding; only the tour's shooting stretch
differs, from run to run. What Chrome still pays is the WAV's own start.

The desktop rows are three interleaved runs of each build (before, after, before, ...), the browser rows two, headless,
on a machine other agents were using; a range is the lowest and the highest run.

**What the gaits of 2026-11-11 to 13 added** (gdstudio #1360). The budget case's ten walkers went from 0.92 to 1.07
times the calibration (db19fdc0) to 1.50 to 1.80 (main at dc9dc2fb, 1.79 to 2.99 ms median), eight interleaved runs
each on a desktop at 97 to 100 % load. Read by the bench's parts, as a share of the body's step (which no change
touched, so it cancels the load), the animation script and the tree rose at three commits, a game made at each:

| Animation script and tree, share of the step (25 walking) | Script | Tree |
| --- | ---: | ---: |
| Before (db19fdc0) | 0.31 | 0.66 |
| Our walk, jog and sprint (#1275) | 0.40 | 0.70 |
| Gait speed matching, momentum and lean (#1368) | 0.90 | 0.87 |
| The starts and stops exist (#1375), and main | 1.18 to 1.37 | 0.85 to 0.91 |
| After #1360 | 0.99 | 0.80 |

At the step's 72 µs that is a script of 22 µs before and 99 on main. Of main's, the gait's blend took 16 to 25 µs (the
speed matching of both spaces), the lean 1, the momentum blend 6.5 in the skeleton's update, and the transitions 19 to
33: once #1375 gave the player its starts and stops, every moving body looked up its main gait, its phase in the tree
and its next foot each frame before asking whether it wanted a stop, a reversal or a pivot, and each look at a clip's
record built its library's name and its contact list again. #1360 asks the controller's numbers first and keeps each
record's lookup and contacts once (`GaitClips`): 7 to 9 µs, the same transitions picked. Our clips key the four `ik_`
targets (8 of 61 tracks), which the tree blends too. What #1360 left is
[gdstudio #1438](https://github.com/Ryubara/gdstudio/issues/1438).

- **Approach:** Empty the `RagdollPool` (`clear()`) before counting a living character's nodes, so it makes the pool's
  sets whatever ran first; leave out the controller the test added and hold the count equal. The count includes the
  empty `PhysicalBoneSimulator3D` every `Skeleton3D` adds as an internal child on entering the tree (4.7.2's
  `setup_simulator`): `find_children` lists it. **Watch out for:** handing a set to the pool left its `RagdollDrawing`
  on the skeleton that made it: 57 nodes alone, 56 in the full run, where earlier suites had filled the pool;
  `_release` now drops it. **Seen:** gdstudio #1210, 2026-11-11.
- **Approach:** When a change adds a node or a skeleton modifier to every character (a modifier the `AimLayer` makes,
  however inactive), raise `NODES_ALIVE` in `test_parts_budget.gd` by as many, with a line on what it is, in the same
  commit; grep the suites for `NODES_ALIVE` before the full run. **Watch out for:** the aim suites pass and only the
  full run counts the body, so the extra node shows up as an off-by-one in a suite that looks unrelated. **Seen:**
  gdstudio #1351, 2026-11-12 (`AimUprightModifier`, 65 to 66).

## Prone and the crawl {#prone}

Moved to [Prone and sliding](moves.md#prone) (gdstudio #1029: this page reached the size limit).

## Sliding {#slide}

Moved to [Prone and sliding](moves.md#slide) (gdstudio #1029).

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
