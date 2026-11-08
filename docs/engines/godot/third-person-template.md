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
| Controller | `gameplay/player/player.gd`, `player_tuning.gd` + `.tres`, `step_climber.gd`, `interactor.gd` | One resource holds every tuned number. Signals: `jumped`, `landed`, `took_hit`, `interacted`, `item_collected`, `state_changed`, `teleported`. |
| Animation | `gameplay/player/player_animation.gd`, `character_clips.gd` | An `AnimationTree` built in code: a body state machine and a one-shot action layer. `CharacterClips.ALL` names all 86 clips. |
| Camera | `gameplay/player/player_camera.gd`, `gameplay/camera_zone/` | A thin wrapper on a Phantom Camera in Third Person follow mode; a zone that raises a second camera's priority. |
| Touch controls | `ui/touch/` (in 3D Blank, for every template) | A floating stick, a look drag and buttons that press the game's actions. |
| Assets | `assets/characters/mannequin/`, `assets/animation/universal/` | CC0, each folder with a `LICENSE.md`. |
| The map | `world/`, `gameplay/` (the six components) | The #788 prototype map, with a spawn point and a camera zone. |

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
- **Approach:** Name every point of an `AnimationNodeBlendSpace1D` (`add_blend_point(node, pos, -1, &"walk")`) and travel
  a state machine between states that all have transitions to each other. **Watch out for:** Godot 4.7 warns "No name
  provided" for an unnamed point, once per point and per player. **Seen:** gdstudio #821, 2026-11-08.
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
  a test holds that a 5 kg crate moves more than twice as far as a 200 kg one in a second. A `TriggerZone` with no
  `required_group` counts every body, a block of the map included (the camera zone took the view at the start for a
  static block in it): a camera zone must say `player`.

## Phantom Camera in a third-person follow {#phantom-camera}

<!-- new section: camera.md covers the hand-built camera; this is what the addon did in the template -->

- **Approach:** Make the player's camera a `PhantomCamera3D` in Third Person follow mode with a wrapper node that sets
  its follow target, `spring_length`, `collision_mask`, `margin` and offsets in its own `_enter_tree` (before the
  addon's `_ready` builds the spring arm), and turn it with `set_third_person_rotation_degrees(Vector3(-pitch, yaw, 0))`
  from the third `_process` on. **Watch out for:** the addon puts a `SpringArm3D` in its parent and moves itself under
  it, so the node is at `PlayerCamera/@SpringArm3D@N/FollowCamera` at run time: ask the wrapper for it. The arm exists
  a frame or two after `_ready`, and rotating the camera before then errors.
  A camera with a `tween_resource` also tweens to its first view (1.2 s from the Camera3D's own transform) unless
  `tween_on_load` is off. **Seen:** gdstudio #821, 2026-11-08.
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

## Touch controls {#touch-controls}

<!-- new section: ui-controls.md has the Deadnight lessons; this is the reusable component and how it was proved -->

`TouchControls` is in the base (`ui/touch/`): instance it, list its `TouchButton` resources (an action, a word, a slot)
and connect `look_turned` to whatever turns the view. It presses the game's actions, so no gameplay code changes.

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
