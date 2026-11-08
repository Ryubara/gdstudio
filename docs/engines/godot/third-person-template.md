# The 3D Third Person template

<!-- new section: the new-game page lists the templates; nothing held how the character template is built -->

How the template's character is built and what Godot 4.7.2 did on the way (kit issue #821): a `CharacterBody3D`
controller, a Phantom Camera third-person view, touch controls for phones and a Quaternius mannequin animated with the
Universal Animation Library 1 and 2. What a game made from it holds is in its own `docs/design/character.md`; the
template list is [A new game from a template](new-game.md#the-templates). Measured on Windows, an RTX 5080, Godot
4.7.2, and in headless Chromium on SwiftShader.

## What is in it {#what-is-in-it}

| Part | Where (in `templates/3d-third-person/game/`, the base in `templates/3d-blank/game/`) | Notes |
| --- | --- | --- |
| Controller | `gameplay/player/player.gd`, `player_tuning.gd` + `.tres`, `step_climber.gd`, `interactor.gd` | One resource holds every tuned number. Signals: `jumped`, `landed`, `took_hit`, `interacted`, `item_collected`, `state_changed`, `teleported`, `aim_changed`, `crouch_changed`. Crouch, aim and shoot: [below](#crouch-aim-shoot). |
| Animation | `gameplay/player/player_animation.gd`, `character_clips.gd` | An `AnimationTree` built in code (also in the editor, as a `@tool` script): a body state machine and a one-shot action layer. `CharacterClips.ALL` names all 86 clips. |
| Camera | `gameplay/player/player_camera.gd`, `gameplay/camera_zone/` | A thin wrapper on a Phantom Camera in Third Person follow mode, with a sprint zoom and shake and an aim view blended on its framing; a zone that raises a second camera's priority. |
| Weapon | `gameplay/weapon/`, `gameplay/projectile/`, `gameplay/target/` | A `Weapon` fires `Projectile` spheres from a muzzle marker toward the crosshair; a `Target` falls over when hit. The `Crosshair` is `ui/hud/crosshair.tscn`. |
| Sound | `gameplay/player/footsteps.tscn`, `gameplay/pickup/pickup.tscn`, `main.tscn` | `Footsteps` follows the skeleton's feet, a `Pickup` plays its coin, `Wind` plays the bed on `Ambient`; every player is on a bus ([Audio](audio.md#template-buses)). |
| Touch controls | `ui/touch/` (in 3D Blank, for every template) | Real `Control` nodes in `touch_controls.tscn` (a stick, two zones, buttons you drag in the 2D editor) that press the game's actions; the script only reads their places. 3D Third Person adds the Fire, Aim and Crouch buttons in `third_person_touch_controls.tscn`, a scene that inherits the base's. |
| Assets | `assets/characters/mannequin/`, `assets/animation/universal/` | CC0, each folder with a `LICENSE.md`. |
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
  `PhantomCamera3D` it drives (3D Blank has no wrapper: its `ViewCamera` is a plain `PhantomCamera3D`). **Watch out
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
- **Approach:** When a scene hangs a node on a part inside an instanced scene (the pistol on the mannequin's
  `Skeleton3D`), mark that instance editable (`[editable path="Model"]` at the end of the `.tscn`, which the editor
  writes when you tick "Editable Children"), and prove the web export, not only the tests. **Watch out for:** without
  the line the pistol was there in the editor, in every GdUnit test and in a windowed capture, and missing from the web
  export: `Weapon.muzzle` was null, the fire button did nothing and no error was printed; the touch smoke found it
  ("the fire button shoots", shots 0 to 0) by reading `player.weapon`'s muzzle in the page. **Seen:** gdstudio #836,
  2026-11-08 (fix: the line, a test that reads the scene's text, and the smoke's three new checks).
  The pistol's muzzle and the footsteps' skeleton are `NodePath` exports into the instance, so a null there is the sign.
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
