# The 3D Third Person template

<!-- new section: the new-game page lists the templates; nothing held how the character template is built -->

How the template's character is built and what Godot 4.7.2 did on the way (kit issue #821): a `CharacterBody3D`
controller, a Phantom Camera third-person view, touch controls for phones and a Quaternius mannequin animated with the
Universal Animation Library 1 and 2 (the female and the male one). What a game made from it holds is in its own
`docs/design/character.md`; the template list is [A new game from a template](new-game.md#the-templates). Measured on
Windows, an RTX 5080, Godot 4.7.2, and in headless Chromium on SwiftShader.

## What is in it {#what-is-in-it}

| Part | Where (in `templates/3d-third-person/game/`, the base in `templates/3d-blank/game/`) | Notes |
| --- | --- | --- |
| Controller | `gameplay/player/player.gd`, `player_tuning.gd` + `.tres`, `step_climber.gd`, `interactor.gd` | One resource holds every tuned number. Signals: `jumped`, `landed`, `took_hit`, `interacted`, `item_collected`, `state_changed`, `teleported`, `aim_changed`, `crouch_changed`. Crouch, aim and shoot: [below](#crouch-aim-shoot). |
| Model | `gameplay/player/player_model.gd` | `Model` is a slot (a `Node3D`) that holds the glb and the pistol seat; replace the glb under it: [Replacing the model](#replacing-the-model). |
| Animation | `gameplay/player/player_animation.gd`, `character_clips.gd` | An `AnimationTree` built in code (also in the editor, as a `@tool` script): a body state machine and a one-shot action layer. `CharacterClips.ALL` names all 86 clips. |
| Camera | `gameplay/player/player_camera.gd`, `gameplay/camera_zone/` | A thin wrapper on a Phantom Camera in Third Person follow mode, with a sprint zoom and shake, an aim view and a fire view blended on its framing; a zone that raises a second camera's priority. The distance is on `PlayerCamera`; the over-the-shoulder view is the `Camera` node's H and V Offset, set from `PlayerCamera`'s Shoulder group (left, center, right; Q swaps). |
| Weapon | `gameplay/weapon/`, `gameplay/projectile/`, `gameplay/target/` | A `Weapon` fires `Projectile` spheres from a muzzle marker toward the crosshair; a `Target` falls over when hit. The `Crosshair` is `ui/hud/crosshair.tscn`. |
| Impacts | `gameplay/impacts/` (`impacts.tscn` in `main.tscn`), `assets/shaders/impacts/`, `assets/materials/impacts/`, `assets/audio/impacts/` | Where a shot lands: a mark on what it hit (it rides a moved or pushed body and goes with a freed one), an effect and a sound, picked by the kind of surface. [Bullet impacts](#impacts). |
| Sound | `gameplay/player/footsteps.tscn`, `gameplay/pickup/pickup.tscn`, `main.tscn` | `Footsteps` follows the skeleton's feet (from the `Model` slot), a `Pickup` plays its coin, `Wind` plays the bed on `Ambient`; every player is on a bus ([Audio](audio.md#template-buses)). |
| Touch controls | `ui/touch/` (in 3D Blank, for every template) | Real `Control` nodes in `touch_controls.tscn` (a stick, two zones, buttons you drag in the 2D editor) that press the game's actions; the script only reads their places. 3D Third Person adds the Fire, Aim and Crouch buttons in `third_person_touch_controls.tscn`, a scene that inherits the base's. |
| Assets | `assets/characters/mannequin/` (`mannequin_female.glb`, the default, and `mannequin_male.glb`), `assets/animation/universal/` | CC0, each folder with a `LICENSE.md`; [the two mannequins](#mannequins). |
| Ragdoll | `gameplay/player/player_ragdoll.gd`, `Player.die()` / `revive()` | Death as a hybrid: an animated capsule while alive, physical bones generated on the model's skeleton on death, a blend back on getting up. Y or the `ragdoll` checkbox; runs on Jolt. [Ragdoll](#ragdoll). |
| Minimap | `ui/minimap/` (the widget, the full-screen map), `core/minimap/` (`MinimapMarker`, `MinimapSection`) | A round map that follows the character and a full-screen map on `M`; a marker component any node carries. [Minimap](#minimap). |
| Pistol | `assets/weapons/pistol/` | GDStudio's own (MIT, from Deadnight's build script), 692 triangles, one palette material; `pistol_held.tscn` seats it on `hand_r` for the six pistol clips ([Weapons](../../tools/blender/weapons.md#the-third-person-template-pistol)). |
| The map | `world/`, `gameplay/` (the six components) | The #788 prototype map, with a spawn point and a camera zone. Every component is a scene whose parts are nodes (`Panel`, `Shape`, `Sensor`...), and `ProtoBlock` (in 3D Blank) makes the solids. |

Measured in Compatibility on the desktop (vsync off, 300 frames after 150 of warm-up): the map alone from the overview
camera 0.34 ms CPU, 0.19 ms GPU, 145 draw calls, 84.4 MB of texture memory; with the character 0.38 / 0.21 ms, 149
draw calls, the same texture memory (the mannequin has two flat materials and no texture) and 1.9 MB more video memory.
The whole game from the third-person camera draws 64 calls. The trimmed 3D Blank (floor and walls) is 0.17 / 0.16 ms,
10 draw calls and 64.2 MB. Forward+ is 0.21 / 0.68 ms and 348 MB for the character in the map. The web export is a
0.92 MB `index.pck` for 3D Blank and 3.26 MB for 3D Third Person (the character and the two libraries are most of the
difference), and both load in headless Chromium with no console error, page error or failed request (a SwiftShader
frame is about 39 ms for 3D Blank and 67 ms for 3D Third Person, which only says it runs with no GPU).

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
- **Approach:** Film each model through the scene that holds it: point `player.tscn`'s model at the other glb (what
  the editor swap saves) and record `tools/capture/model_tour.tscn`; read the aim-pose frame, where the pistol sits in
  the hand. **Watch out for:** swapping the model in code at run time (`remove_child`, `free`, `add_child` on `Model`)
  left the pistol's `BoneAttachment3D` at the new skeleton's rest pose, 0.65 m from the hand, in `main.tscn` (the path
  was right; toggling `use_external_skeleton` off and on later fixed it, doing so in `_seat_attachments` did not),
  while GdUnit's swap and a scene saved with the male glb were right: the test passed and the capture showed the pistol
  on the floor. **Seen:** gdstudio #843, 2026-11-09 (follow-up issue opened).

## Replacing the model {#replacing-the-model}

<!-- new section: a swap of the player's glb in the editor broke the clips, the pistol and the game (gdstudio #844) -->

The player's model is a **slot**: `Model` is a plain `Node3D` with the `PlayerModel` script, and the glb sits under it
(`Model/Mannequin`) with the pistol (`Model/PistolHeld`, a `BoneAttachment3D` on `hand_r`). Nothing refers to the glb
by its name. To swap the character in the editor:

1. In the Scene dock, select the old model (`Mannequin`) and delete it. Leave `Model` and `PistolHeld`.
2. Drag the new `.glb` from the FileSystem dock onto `Model` (the other mannequin, or any name; a glb of the
   Quaternius universal rig, with `Armature/Skeleton3D` under its root and the bone names of the mannequin).
3. Save. The `AnimationPlayer`'s Root Node, the `AnimationTree`, the pistol's skeleton path and the footsteps follow
   the new model by themselves; nothing is set by hand. Turn the new model to face +Z if its file faces the other way.

`PlayerModel.rig()` and `skeleton()` give the model and its skeleton, `rig_changed` says when they change, and the
node warns when it holds no model or two. `PlayerAnimation` points the `AnimationPlayer` at the new model and builds the
tree again; `Footsteps` asks the slot for the skeleton; `PlayerModel` seats every `BoneAttachment3D` child on it. A
model without `Armature/Skeleton3D` gets one configuration warning on `Animation` and no root at all (the engine logs
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
  path: seat it with the steps of the next entry (`PlayerModel._seat_attachments`), and skip an attachment that
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
  crouch-walk after the swap, in `main.tscn` as well as in the test arena, and check that the bone moved. **Watch out
  for:** the first test compared the pistol (0.13 m from its seat) with the hand 4 ticks after the swap against 0.35
  m. A seat left behind sits where the old hand last was, near the new hand while the pose has not changed (1.3 cm
  while aiming, 0.62 m after a crouch in the capture), so the same bug failed locally (0.71 m) and passed in CI, which
  the pose at the sample would explain (the CI run was not reproduced). **Seen:** gdstudio #860, 2026-11-09 (the three
  tests fail on `main` with 0.68 to 0.79 m and pass with the fix).
- **Approach:** Keep every unique name (`%Name`) off the path from the scene's owner to the model, and reference the
  slot from the `Player` by an export (`model`). **Watch out for:** `AnimationTree` sets its `root_node` to
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
  opposite way and was invisible in a test that only held a key sideways. **Seen:** gdstudio #821, 2026-11-08.
- **Approach:** Move a moving body with `Player.teleport()` (or `respawn()`), which resets physics interpolation and
  tells the camera to cut. **Watch out for:** setting `global_position` directly sends a damped Phantom Camera flying
  across the map for about 0.9 s, so a test that waited 40 ticks saw the lens 5 m from where it belonged.
  **Seen:** gdstudio #821, 2026-11-08.
- **Approach:** Prove an interaction against the real physics world with a few ticks of a real key, pad button or touch
  event through `Input.parse_input_event` and the project's `InputMap`, in a small arena with a floor, and keep the
  sample map's own numbers (a jump a block high, steps lower than the step height) in a test of the tuning. **Watch out
  for:** GdUnit4 prints that input events do not work headless; an action key, a pad button and a pad axis do reach
  `Input.is_action_pressed` and `get_vector`, but the mouse cannot be captured (`Input.mouse_mode` stays visible), so
  the camera has `require_captured_mouse` and the test turns it off. **Seen:** gdstudio #821, 2026-11-08.
- A prop is pushed by giving it the share of the player's speed its mass allows, as an impulse along the contact normal;
  a test holds that a 5 kg crate moves more than twice as far as a 200 kg one in a second. A `TriggerZone` counts
  characters and props by default (`counts`) and a `Pickup` only characters (`characters_only`); a camera zone still
  says `player` in `required_group` so that a pushed crate does not take the view.

## Phantom Camera in a third-person follow {#phantom-camera}

<!-- new section: camera.md covers the hand-built camera; this is what the addon did in the template -->

- **Approach:** Make the player's camera a `PhantomCamera3D` in Third Person follow mode, with a wrapper that sets its
  follow target, `spring_length`, `collision_mask`, `margin` and offsets in its own `_enter_tree` (before the addon's
  `_ready` builds the spring arm), and turn it with `set_third_person_rotation_degrees(Vector3(-pitch, yaw, 0))` from
  the third `_process` on. **Watch out for:** the addon moves the camera under a `SpringArm3D` it makes, so its path at
  run time is `PlayerCamera/@SpringArm3D@N/FollowCamera` (ask the wrapper); the arm exists a frame or two after
  `_ready`; and a camera with a `tween_resource` tweens to its first view from the Camera3D's own transform unless
  `tween_on_load` is off (3D Blank's view camera had it on: a test read the lens too early and failed on the CI
  runner). **Seen:** gdstudio #821, 2026-11-08.
- **Approach:** Tune `PlayerCamera`, never `Camera`: `Camera` (a `Camera3D`) renders, `PhantomCameraHost` under it
  copies the active Phantom Camera onto it, `PlayerCamera` is the tuning wrapper and `FollowCamera` the
  `PhantomCamera3D` it drives (3D Blank has no wrapper: its `ViewCamera` is a plain `PhantomCamera3D`). The one
  exception is the shoulder: `PlayerCamera` writes the `Camera` node's own H and V Offset. **Watch out
  for:** the host overwrites the real `Camera`'s FOV, and the wrapper's exports now forward through setters
  ([Phantom Camera](camera.md#phantom-camera)); the addon moves `FollowCamera` under its spring arm, so the wrapper
  exports it as `follow_camera` (a path looked up after the move finds nothing). **Seen:** gdstudio #830, 2026-11-08;
  gdstudio #831 (the export, and the wrapper is a `@tool` script: [Phantom Camera](camera.md#phantom-camera)).
- **Approach:** A second view is a `PhantomCamera3D` with a lower priority that a trigger raises (`CameraZone`); the
  blend is the lower camera's `tween_resource` (duration, transition, ease). **Watch out for:** the camera is
  only raised and lowered by the zone's two signals, so a zone that never reports the player leaves the view where it
  was. The spring arm keeps the lens out of a wall (in the north wall test the arm hit at 0.76 m of its 4.4 m and the
  lens stayed inside).
  **Seen:** gdstudio #821, 2026-11-08.
- The addon's updater window and network request are off in the template (`phantom_camera/updater/updater_mode=0`); a
  game that takes a new release replaces the folder and edits its licence entry. The addon is committed without its
  `examples/` and C# scripts, and every hook of the game's `pre-commit` and the kit's skips it (the addon's files have
  no final newline in places and its own style).

## The map components as scenes {#map-components}

<!-- new section: the six components were first scripts that built their children in code; #831 made them scenes -->

`Door`, `MovingPlatform`, `PhysicsProp`, `Pickup`, `TriggerZone` and `SpawnPoint` each hold their visible parts as nodes
of their own scene (the door's `Panel`, `Shape` and `Sensor`; the platform's `Mesh`, `Shape` and `EndPreview`; the
pickup's `Visual` and `Shape`; the trigger's `Shape` and `Plate`; the spawn point's `Marker`; a prop's crate, barrel and
ball), as `@tool` scripts that size them from the inspector. The platform's `EndPreview` is a translucent copy of the
slab at the far end (hidden in the game) and the door's sensor sphere is `auto_open_range`, so the editor shows the
travel and the reach; the spawn point's blue arrow is its `-Z`.

- **Approach:** Give each node's mesh, shape and material `resource_local_to_scene = true` in the component's scene, set
  the sizes from setters (looking nodes up with `get_node_or_null("%Panel")`, which works from an instance's own root
  and before `_ready`), and apply them again in `_ready`. **Watch out for:** without `local_to_scene` two doors share
  one `BoxMesh` and a resize of one resizes all (a test makes two and resizes one); a `PhysicsProp` with `shape = BALL`
  would save a generated sphere mesh into the level, so its three shapes are nodes and `shape` shows one. **Seen:**
  gdstudio #831, 2026-11-08.
- **Approach:** Read an `AnimatableBody3D`'s new transform after a `physics_frame` or two in a test, and set its place
  before it enters the tree. **Watch out for:** with `sync_to_physics` on, `global_position = x` read straight back gave
  the old position until the next step, so a door's `slide_distance` change and a test that moved a door and asked the
  interactor for it both saw the old place. **Seen:** gdstudio #831, 2026-11-08.

## Crouch, aim and shoot {#crouch-aim-shoot}

<!-- new section: #836 added crouch, a pistol, a crosshair, sprint and aim views and the first sounds to the character
-->

Crouch lowers the capsule from the top (the feet stay on the ground) over `crouch_time` and the camera's target with it;
`Player.has_room_to_stand()` asks the physics space whether a capsule slightly smaller than the standing one fits
above, and a character that lets go under a ceiling stays crouched until it does. Aim (right mouse, left trigger, the
Aim button) turns the body to the camera's heading and raises the pistol; fire (left mouse, right trigger, the Fire
button) aims too and shoots once the arm is half up. The numbers are in the Crouch and Aim groups of the tuning and in
the `Weapon`'s inspector (a game's `docs/design/character.md` lists them).

- **Approach:** Stand a crouched `CharacterBody3D` up only after a shape query above it comes back empty, with a probe a
  little narrower than the capsule and starting a hand above the floor, and prove it with a ceiling slab that ends 2 m
  ahead (let go under it, stay crouched, walk out, stand) and a tunnel 1.25 m high the standing character cannot enter.
  **Watch out for:** a probe as wide as the capsule that starts at the floor touches the floor and the walls at the
  sides and never lets the character stand; a capsule cannot be shorter than two radii, so `crouch_height` is clamped
  to `2 * radius + 0.01`. **Seen:** gdstudio #836, 2026-11-08.
- **Approach:** Layer a held weapon on the upper body only: an `AnimationNodeBlend2` and a one-shot with
  `filter_enabled` and a filter path for `spine_01` and every bone under it (read from the skeleton,
  `Armature/Skeleton3D:<bone>`), the holding pose first, the aim pose over it by the camera's pitch in a blend space
  (`Pistol_Aim_Down` -45, `Pistol_Aim_Neutral` 0, `Pistol_Aim_Up` 45) and the recoil last. **Watch out for:** the aim
  clips are 0.17 s long and do not loop, so they hold their last pose, which is what an aim should do; the pistol clips
  are whole-body poses, so without the filter the legs stop walking. **Seen:** gdstudio #836, 2026-11-08.
- **Approach:** Time footsteps to the skeleton, not to a clock or a distance: a foot lands when its bone, moving toward
  the model's +Z, turns back (its forward speed goes from above `swing_speed` to below minus it, after a swing of at
  least `min_stride`), read from `Skeleton3D.get_bone_global_pose` each frame, with a minimum gap between steps and
  no step off the floor or under `min_speed`. **Watch out for:** the clips play at their own cadence, so a fixed
  stride length drifts from the feet, and foot height alone fails (the planted ankle is at 0.10 m in the walk and
  0.12 to 0.17 m in the jog); a jitter of the blended pose gave a second step 124 ms after the first with the same
  foot until `min_stride`. Landings: walk 0.0 and 0.67 s of 1.33 s, jog
  0.47 s of 0.93 s, sprint 0.28 s of 0.67 s, crouch walk 1.0 s of 2.0 s. **Seen:** gdstudio #836, 2026-11-08.
- **Approach:** Give a body its shapes as direct children, and move only a mesh with an animated pivot: a `Target`'s
  `Shape` is a child of the body and `Pivot` (which tips back) holds only the board. **Watch out for:** a
  `CollisionShape3D` under a plain `Node3D` that sits under the body is not a shape of the body, so the first target
  was solid to nothing: the aim ray passed through it and the shot flew by (no error). **Seen:** gdstudio #836,
  2026-11-08.
- **Approach:** Start the aim ray at the shooter's depth (the camera position moved along the ray to the plane of the
  character) with the character excluded, send the projectile from the muzzle toward that point, and shoot along the
  view when the point is behind the muzzle; make the projectile a `CharacterBody3D` that `move_and_collide`s, so it
  has a swept hit and a collision exception for the shooter. **Watch out for:** the pistol's muzzle is in
  `PistolHeld/Pistol/Pistol/Muzzle` (the glb's root and its mesh are both called `Pistol`), and a wrong path in a
  `NodePath` export leaves the weapon with no muzzle and one configuration warning. **Seen:** gdstudio #836,
  2026-11-08.
- **Approach:** Hang a node that belongs to the character (the pistol) on the model's slot, not on a part inside the
  glb's instance, and prove the web export, not only the tests. **Watch out for:** a node added inside an instanced
  scene is there in the editor and in a test and missing from the web export unless the instance is marked editable
  (`[editable path="Model"]`), and it is lost when the model is replaced; #836 shipped without the line
  (`Weapon.muzzle` null, the fire button did nothing, no error) and #844 moved the pistol under the slot, so the line is
  no longer needed ([Replacing the model](#replacing-the-model)); a null `muzzle` is still the sign of a path into a
  part that is gone. **Seen:** gdstudio #836, 2026-11-08; gdstudio #844.
- **Approach:** Size a `Control` that sits by its anchors (the `Crosshair`, at the middle of the screen) by setting its
  four offsets from the exports (`-half`, `half`), not `custom_minimum_size`. **Watch out for:** a minimum size only
  makes a control bigger: shrinking the radius left the rect at its old size, and the test that reads the rect's size
  and middle failed for a smaller circle. The weapon aims through the middle of the viewport, which is the middle of
  this control, so a test compares the two. **Seen:** gdstudio #836, 2026-11-08.
- **Approach:** Start every suite that reads the pistol's buttons (`fire`, `aim`, `crouch`) by letting go of them with
  `Input.action_release`, and run the suites in the CI's order before pushing (`-a` once per suite, as the log lists
  them). **Watch out for:** the file order differs between Windows and the Linux runner, and a base touch suite leaves the
  left mouse button and `fire` down (a mouse release event does not clear the action): the crosshair and touch suites
  passed in every local order and failed 8 tests on the runner, where one of them ran straight after it. **Seen:**
  gdstudio #836, 2026-11-08 (`InputSim.release_all()` lets go of the actions too).
- **Approach:** Add a template's own buttons to the base's touch layer with an inherited scene
  (`third_person_touch_controls.tscn`, root `instance=` the base's, new buttons under `SafeArea/Buttons`) and not by
  copying the base file. **Watch out for:** an extending template replaces a file of the base whole, so a copy of
  `touch_controls.tscn` with three more buttons made the base's own suite (two buttons) fail in the made game. **Seen:**
  gdstudio #836, 2026-11-08.
- **Approach:** Slow a push by what is pushed: a `PhysicsProp` has a `push_speed`, the character walks no faster than
  the slowest prop it pushes and gives the prop that speed, and a heavy, grippy cube (60 kg, friction 0.5) stops in a
  few centimetres when the character does, and is given the push speed while the character walks 15 percent faster, so
  the character stays against it and pushes it every tick (equal speeds let a gap open and the friction slow the cube
  between pushes: the push clip flickered in and out). **Watch out for:** the old push gave a prop 85 percent of the
  character's own run speed, so a cube left at 3.4 m/s and the push clip lasted a moment; a prop with a `push_speed` of
  0 is pushed as before (the spheres). **Seen:** gdstudio #836, 2026-11-08.

- **Approach:** Make an area that senses "something is near" count only what should trigger it: the door's `Sensor`
  counts a `CharacterBody3D` on `auto_open_mask`, never a wall, floor, prop or the door's own body. A type test, not
  named layers, so the player and a game's own layers stay as they are and the mask stays tunable. Closing the door
  with a character in range keeps it shut until they leave and come back. **Watch out for:** an `Area3D` reports
  every overlapping body, static ones too: the gate door opened at the start and again after each press of the
  interact button, because its sensor overlapped the gate's posts, the low wall, the floor and the door itself.
  **Seen:** gdstudio #845, 2026-11-08 (`test_door.gd` and `test_gate_in_the_map.gd`).
- **Approach:** Keep a door's sensor and its reach point where the closed door stands: the script moves the sensor back
  against the panel's motion, `close_after` counts from when the last character left, and `interact_point()` tells
  the `Interactor` where to measure from. **Watch out for:** a sensor that is a child of a sliding door rises with it
  and loses a character 2 m away; an open swinging gate's origin moves away from its hinge, so the 1.6 m reach no
  longer found it; a test body made at the origin and moved after `add_child` is sensed at the origin for a step, so
  set its `position` before. **Seen:** gdstudio #845, 2026-11-08.
- **Approach:** Make every area that reacts to bodies say which bodies: a `Pickup` is taken only by a
  `CharacterBody3D` (`characters_only`), a `TriggerZone` counts by `counts` (`CHARACTERS_AND_PROPS` by default, so a
  pushed crate presses a pad) and then `required_group`. Prove it with real bodies: a floor, a block and an
  `AnimatableBody3D` beside the area must not trigger it, a character must. **Watch out for:** the map's pressure
  pad was pressed at the start by the floor and the landing under it, so the room door opened at once and the pad
  never released; the coins were clean only because no block touched them. A frozen `RigidBody3D` did not press
  the zone in the test (use `gravity_scale = 0`). **Seen:** gdstudio #848, 2026-11-08 (`test_components_among_blocks.gd`).

- **Approach:** Drive the camera's zoom from the buttons (`Player.aim_held`, `fire_held`) and keep `Player.aiming` (the
  aim or fire button held) for the body and crosshair; give a shot without aiming its own zoom
  (`fire_distance`, `fire_fov`, speeds) with a `zoom_when_firing` toggle, and aiming an `aim_shifts_shoulder` toggle
  (off). Prove it by measuring the distance over the frames after letting go. **Watch out for:** the camera read
  `Player.aiming`, true for 0.8 s after the last shot, so the view stayed zoomed about a second after a shot (aim alone
  zoomed out at once), and a shot was the same zoom as the aim button, which the controller notes say never to couple
  ([Aim and hip fire](../../gamedev/controller.md#aim)). **Seen:** gdstudio #856, 2026-11-08 (`test_camera_fire.gd`).
- **Approach:** Let go of aim and fire and the character is back to normal on the next frame: `aiming` is
  `aim_held or fire_held`, with no hold after a shot, so the walk speed, the turn and the locomotion clips are the
  normal ones at once and only the arm lowers over `aim_pose_time`. Prove it with simulated input (aim, fire, release;
  fire alone; walk, aim, fire, release) by reading `aiming` and the speed on the frame after release. **Watch out
  for:** #856 moved the camera to the buttons, but `aiming` stayed true 0.8 s after a shot (a hold since removed) and
  drove `aim_move_scale` and the turn, so the slow aim walk lasted about a second; the animation tree had no latch of
  its own. List everything that reads a state that outlives its input. A tap under half the arm's raise time (about
  75 ms) now shoots nothing. **Seen:** gdstudio #868, 2026-11-09 (`test_aim_release.gd`).
- **Approach:** Sweep the camera's yaw with aim, fire and sprint held in a four-walled room built high above the map and
  in the open, and assert the lens never nears the arm's start by less than a bound no wall can force
  (`test_camera_walls.gd`: 12 yaws and three actions, about 40 s). **Watch out for:** a first sweep stood in the map and
  read 1.0 m "at rest" from its south wall 1 m behind the spot, and a case with a sideways arm offset measured from the
  head read 0.5 m for a lens 1.1 m from the arm's start. Cause and fix: [Walls](camera.md#walls). **Seen:** gdstudio
  #856, 2026-11-08.

## Bullet impacts {#impacts}

<!-- new section: the pistol's shots left nothing where they landed (gdstudio #875); the research and the route are in
     [Bullet impacts and marks](shot-feedback.md#impact-marks) -->

A shot that lands tells the level's `Impacts` node (`main.tscn`; the group `impacts`, so no path): it makes a mark on
the body, bursts the surface's effect and plays its sound. A mark is a flat quad on the body it hit, so it goes where a
pushed crate or a moving platform goes and is freed with it; there is no `Decal` (Compatibility, which the web build
uses, does not draw one). `Impacts.impact(collider, point, normal)` is the one call, so a game's own weapon, a grenade
or a ray gun reuses it.

- **The inspector, on `Impacts`.** Marks: `marks_enabled`, `max_marks` (64; the oldest goes first, a lower number
  trims at once), `mark_lifetime` (30 s, **0 keeps a mark**), `mark_fade_time` (4 s, the end of the life it fades
  over), `mark_material` (the material of every mark, a `ShaderMaterial` with a hole and a ring, or a texture: its
  `use_texture` and `mark_texture`), `mark_size` (0.12 m), `size_variation` (0.3), `random_rotation`,
  `surface_offset` (4 mm) and `random_seed`. Effects: `effects_enabled` and `sounds_enabled`. Surfaces:
  `default_surface`. Every one is read when used: a change shows in the next hit (marks already placed keep their
  look; `max_marks` and `mark_lifetime` also act on them at once).
- **One node a surface.** Under `Impacts/Surfaces` are `Default`, `Wood`, `Metal` and `Target`, each an
  `ImpactSurface` with `surface_name`, `leaves_mark` (off for the target's board, which tips over), `mark_material`
  (empty: the `Impacts`'), `mark_scale`, `effect` (a one-shot `CPUParticles3D` child: restyle it in the editor, swap
  it for a `GPUParticles3D`), `sound` (an `AudioStreamPlayer3D` child on `SFX` with an `AudioStreamRandomizer` of three
  variants) and `pool_size` (hits of the surface that can show and sound at once). Add a node and a name for a new
  surface (`glass`, `flesh`); the default is what a hit gets when the body says nothing or says a name no surface has.
- **Which surface a body is.** The metadata `surface` on the body or any node above it (Inspector, Node, Metadata,
  Add: a name), or a group of that name; the nearest wins. `physics_prop.tscn` says `wood`,
  `moving_platform.tscn` `metal`, `target.tscn` `target`; the map's floor and walls are untagged and so the default.
- **On or off per weapon or projectile.** `Weapon.impacts` (its shots land without a trace when off) and
  `Projectile.impact_effects` (the projectile scene's own, for a game with its own projectile); a shot leaves an
  impact when both are on.
- **What takes no mark.** A `CharacterBody3D` (the effect and sound still play) and the ragdoll's bones: they are on
  layer 16 and a projectile's mask is the level, so a shot passes through them and marks what is behind.
- **Tests and captures.** `tests/gameplay/test_impacts.gd`, `test_impact_marks.gd`, `test_impact_surfaces.gd`,
  `test_impact_effects.gd`, `test_impacts_exports.gd`, `test_impacts_in_the_map.gd` and `tests/audio/test_impact_sounds.gd`
  (real projectiles in a small arena, and in the map); `tools/capture/impacts_tour.tscn` plays the pistol through a
  wall, a pushed cube and the fade (`gds capture frames`, and `--rendering-method gl_compatibility` for the web look).
  The sounds are made by `tools/audio/impact_sounds.py` (synthesised, MIT).

## Minimap {#minimap}

<!-- new section: #884 added the minimap; how it is built and what it costs are on [Minimap](minimap.md) -->

`MinimapLayer` (`main.tscn`) holds the small `Minimap` (top right, follows the character, turns with the camera) and the
`MapScreen` (`M`, north up, the whole map). The player, every pickup, target and door carry a `MinimapMarker`; the
workshop is a `MinimapSection`. How it works, the sources it can draw from and the cost are in [Minimap](minimap.md).

- **The inspector, on `Minimap`.** Nodes: `target`, `target_group`. Shape: `shape`, `map_size`, `corner_ratio`. View:
  `range_m`, `range_min`, `range_max`, `zoom_step`, `zoom_smoothing`, `rotation_mode`, `turn_smoothing`,
  `follow_target`, `fixed_centre`, the two zoom actions. Map source: `source`, `image`, `image_world_rect`,
  `live_layers`, `live_height`, `live_depth`, `live_resolution_scale`, `live_unshaded`. Look: `background_color`,
  `border_color`, `border_width`, `edge_fade`, `opacity`, `tint_enabled`, `tint_dark`, `tint_light`, `marker_scale`,
  `show_north`, `show_self`. Markers: `default_icon`, `default_edge_icon`, `hidden_kinds`, `pool_prewarm`,
  `max_markers`. Update: `map_update_rate`, `marker_update_rate`, `still_refresh_seconds`.
- **On `MinimapMarker`.** Look: `icon`, `color`, `size`, `rotates_with_node`, `kind`, `draw_order`. Edge:
  `clamp_to_edge`, `edge_inset`, `edge_icon`. Show: `active`, `rule`, `near_distance`, `revealed`, `height_fade`.
- **On `MinimapSection`:** `title`, `size`, `level`, `map_texture`. **On `MapScreen`:** `toggle_action`, `fit_bounds`,
  `fit_to_sections`, `fit_margin`, `fade_time`.
- **Tests and captures.** `tests/core/test_minimap_marker.gd`, `test_minimap_section.gd`, and in `tests/ui/`
  `test_minimap_projector.gd`, `test_minimap_pool.gd`, `test_minimap_markers.gd`, `test_minimap_view.gd`,
  `test_minimap_sections.gd`, `test_minimap_look.gd`, `test_map_screen.gd`, `test_minimap_baker.gd` (windowed only) and
  `test_minimap_in_the_game.gd`; `tools/capture/minimap_tour.tscn` records the small map turning and zooming and the
  full-screen map, `tools/bench/minimap_bench.tscn` measures the cost.

## Ragdoll {#ragdoll}

<!-- new section: the template gained death and a ragdoll (gdstudio #846) and nothing said how it is built or tuned -->

The character dies into a ragdoll and gets up again, the usual hybrid: an animated `CharacterBody3D` with its capsule
while alive, a full ragdoll while dead, and a blend back to the animation on getting up. How the engine behaves is in
[Ragdolls with PhysicalBone3D](ragdoll.md); this section is what the template does with it.

- **What it is.** `Player.die()` and `revive()` (`is_dead()`, the `died` and `revived` signals, `State.DEAD`).
  Dying stops the animation tree, turns the capsule off, hands every gameplay input a no-op (movement, jump, sprint,
  crouch, aim, fire, interact and a hit are ignored in the state) and lets the `Ragdoll` component
  (`PlayerRagdoll`) take the skeleton from the pose on screen, each bone given the body's velocity times
  `carry_velocity` (a run keeps its momentum). The camera still orbits, and its target follows the hips. A ragdoll that
  falls below the tuning's `fall_limit` respawns; `teleport()` and `respawn()` get a dead character up at once.
  Getting up stands the body on the ground under the hips, facing the way the chest faces, restarts the animation at
  the ground state and fades the ragdoll's hold on the skeleton out over `get_up_time`. The Universal Animation
  Library has no get-up clip; a game with one plays it with `play_clip()` from `revived`.
- **The inspector.** On `Player`, the group Ragdoll: `ragdoll_body` (the component), `ragdoll` (a live bool: tick it in
  the inspector or the remote inspector to kill, untick to get up) and `ragdoll_key` (Y by default; None turns the key
  off). The key is added to the input action `ragdoll` when the game runs, next to anything a game binds there in the
  Project Settings; it is a testing aid, so a game that ships without it sets None. On `Ragdoll`: `mass` (the whole
  body, shared out by bone size), `thickness` (the capsules), `joint_range` (how far the joints swing, as a share of the
  measured range), `linear_damp`, `angular_damp`, `friction`, `bounce`, `carry_velocity`, `get_up_time`,
  `collision_layer` (16, the ragdoll's own) and `collision_mask` (1, the level only: the bones meet no player capsule,
  camera wall or shot, but also not each other, which #872 changes so limbs stop passing through the body). Every
  one applies live, has a pinned default and a test.
- **Why the bones are generated.** The 16 `PhysicalBone3D`s (pelvis, three spine bones, neck and head, arms, hands, legs,
  feet; no fingers) hang off a `PhysicalBoneSimulator3D` named `RagdollBones` under the skeleton of the `Model` slot.
  They are made from the table `PlayerRagdoll.BODIES` every time the slot's rig changes, and in the editor too (the
  capsules show with Debug, Visible Collision Shapes), but never saved: they would sit inside the glb that a model swap
  deletes. Any rig that has these 65 bones works, so both mannequins do, before and after a swap, at run time too.
- **How the limits are measured.** Each joint's limits come from the clips the player plays, on both mannequins, plus
  10 degrees: `tools/ragdoll/measure_joints.gd` (run headless from a game, header says how) prints the cone centres,
  swings and twists and the knees' and elbows' bend, roll and side ranges for the table. A character can die in any pose
  of any clip, and a joint that starts outside its limits throws the body. Run the tool again after a clip changes.
- **The engine is Jolt.** The template's `project.godot` sets `3d/physics_engine="Jolt Physics"`: on Godot Physics this
  ragdoll blew up in 10 to 20 percent of deaths. Every other suite of the template passes on Jolt. This is a change to
  every game made from the template, and the maintainer should know ([why](ragdoll.md#jolt)).
- **The map.** The prototype level has a `RagdollLedge` group (a ramp and a ledge, 3 m up, in the south, past the push
  cubes): run up it and off the east edge, or press Y at the top. The blocks are new and not in the baked lightmap, so
  they are lit by the sun and the sky until the level is baked again.

- **Approach:** Prove a ragdoll in the game's own camera on both models: run, press Y mid-run, orbit the body, press Y
  to get up, then run off the ledge; read the frames before the report. **Watch out for:** a stress test that passes
  says no bone flew, not that the body lies on the floor in a believable pose, which only the clip shows (the
  frames are from `tools/capture/ragdoll_tour.tscn`, run through `gds capture` as in
  [A route for a clip](#walkthrough)). **Seen:** gdstudio #846, 2026-11-09.

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

## A route for a clip {#walkthrough}

<!-- new section: nothing said how a character is filmed through a map without a person -->

- **Approach:** Film a character with an autopilot that presses the same input actions a player would and turns the
  camera with the same `orbit()` the mouse uses, over a list of waypoints with a jump distance, and give each waypoint a
  "stuck for 2 s" exit. **Watch out for:** the first route went through a 1 m wall (the low wall by the gate) and the
  clip was 25 s of a character running into it; read a contact sheet of the clip before calling it done. The movie is
  the same every run (the mp4 had the same size twice). **Seen:** gdstudio #821, 2026-11-08
  (`tools/capture/walkthrough.tscn`: gate, four coins up the jump blocks, the props, the room's door).
