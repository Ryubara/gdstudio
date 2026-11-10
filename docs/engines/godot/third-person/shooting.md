# Crouch, aim and shoot

<!-- new section: split out of the third-person template page when it reached the size limit (#983) -->

The 3D Third Person weapon: crouch, aim and shoot, the bullet impacts and the effects. Part of [the 3D Third Person template](../third-person-template.md).

## Crouch, aim and shoot {#crouch-aim-shoot}

<!-- new section: #836 added crouch, a pistol, a crosshair, sprint and aim views and the first sounds to the character
-->

Crouch lowers the capsule from the top (the feet stay on the ground) over `crouch_time` and the camera's target with it;
`Character.has_room_to_stand()` asks the physics space whether a capsule slightly smaller than the standing one fits
above, and a character that lets go under a ceiling stays crouched until it does. Aim (right mouse, left trigger, the
Aim button) turns the body to the camera's heading and raises the pistol; fire (left mouse, right trigger, the Fire
button) aims too and shoots once the arm is half up. The numbers are in the Crouch and Aim groups of the tuning and in
the `Weapon`'s inspector (a game's `docs/design/character.md` lists them).

The weapon and the aim pose read no camera (gdstudio #901). `Character.aim_ray()` is the ray a character aims along, from
the command of its last step: the command's shot block when it has one (the human's crosshair, written by
`PlayerInput`), else from the character's eye (its camera target) along the command's `yaw` and `pitch`, which is how
an AI or a test shoots. The body calls `Weapon.fire(origin, direction)`; `fire()` with no ray shoots straight out of
the muzzle. A `Weapon` with no `muzzle` and a `shooter` (a body with no model, as a server has) fires from
`no_muzzle_offset` beside the ray's point at the shooter (the default is where the pistol's muzzle is while aiming:
6 mm off in the test). The cooldown is counted in `Weapon.tick(delta)`: a weapon alone ticks itself (`self_ticking`),
a `Character` turns that off and ticks its weapon last in every `step`, and `CharacterState.weapon` holds the cooldown and
the spread's place for `restore()`.

- **Approach:** Stand a crouched `CharacterBody3D` up only after a shape query above it comes back empty, with a probe a
  little narrower than the capsule and starting a hand above the floor, and prove it with a ceiling slab that ends 2 m
  ahead (let go under it, stay crouched, walk out, stand) and a tunnel 1.25 m high the standing character cannot enter.
  **Watch out for:** a probe as wide as the capsule that starts at the floor touches the floor and the walls at the
  sides and never lets the character stand; a capsule cannot be shorter than two radii, so `crouch_height` is clamped
  to `2 * radius + 0.01`. **Seen:** gdstudio #836, 2026-11-08.
- **Approach:** Layer a held weapon on the upper body only: an `AnimationNodeBlend2` and a one-shot with
  `filter_enabled` and filter paths for `spine_01` and every bone under it (`Armature/Skeleton3D:<bone>`), the aim pose
  over it by the look's pitch in a blend space (`Pistol_Aim_Down` -45, `_Neutral` 0, `_Up` 45) and the recoil last;
  off aim and fire only the gripping hand (`hand_r` and what is under it) takes the grip pose, so the arms and spine
  follow the locomotion (`CharacterAnimation.carry`, `grip_clip`, `grip_bones`). **Watch out for:** the holding pose at
  weight 1 the whole time a weapon was held made the character walk, jog and sprint with the pistol held out like an
  aim; the pistol clips are whole-body poses, so without
  the filter the legs stop walking. **Seen:** gdstudio #836, 2026-11-08; gdstudio #877, 2026-11-10 (found by the
  maintainer).
- **Approach:** Prove a carry by reading, per bone, the blend amount of the layer that filters it (0 on the arm and
  spine walking, jogging, sprinting, crouch walking and jumping, 1 on the hand) and the pistol's clearance on the
  skinned body in every clip on both mannequins (`test_pistol_carry.gd`, `test_pistol_clearance.gd`); keep the arm up
  `shot_hold_time` after a shot. **Watch out for:** with aim released at once (#868) a tap of the fire button raised the
  arm to half and lowered it before a shot showed; the tree is driven from `_process`, a render frame behind the physics
  ticks a test awaits (a rebuild makes the physics catch up with no render frame), so wait for `process_frame` before
  reading a rebuilt tree. **Seen:** gdstudio #877, 2026-11-10.
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
  2026-11-08; since gdstudio #901 the ray is an argument (`Weapon.fire(origin, direction)`) and the weapon reads no
  camera.
- **Approach:** Hand a weapon the ray it aims along and let the body make it from its command; prove it with a second
  character whose target is behind the local camera's back, with a world that has no camera, and with the old
  camera formula kept as a test fixture (`tests/fixtures/camera_aim.gd`) over a sweep of poses. **Watch out for:**
  while `Weapon` read `get_viewport().get_camera_3d()`, a second character driven by commands dropped the human's
  target and not its own, and with no camera every shot left along the muzzle marker, which the animation poses.
  **Seen:** gdstudio #901, 2026-11-10 (`test_command_aim.gd`; 35 poses equal to 0.1 mm in `test_weapon_ray.gd`).
- **Approach:** Count a cooldown in a `tick(delta)` its owner calls from the step, with an export (`self_ticking`) for
  the weapon that stands alone, and keep it with the spread generator's state in the character's snapshot. **Watch out
  for:** a weapon that cools in its own `_physics_process` cools once a frame however often its body is stepped (a
  server stepping two commands, a body nobody steps), and a time stamp from a clock differs between machines; a press
  made while more of the cooldown is left than `fire_buffer_time` (0.3 s) is dropped, which a test with two shots a
  second read as a missing shot. **Seen:** gdstudio #901, 2026-11-10 (`test_weapon_ray.gd`,
  `test_character_state.gd`).
- **Approach:** Drive a pose from the value the step stored (`Character.view_pitch`) and blend the last two ticks' values
  by `Engine.get_physics_interpolation_fraction()`; test the blend with a made-up frame rate by calling the sampling
  and the blend by hand. **Watch out for:** read from the step alone the aim pose stands still for a frame or two and
  then jumps (1.5 degrees at 90 degrees a second and 144 frames a second, against 0.625 blended, the same as the old
  read of the camera on every frame); the blended pose is one tick behind the view, as the body's picture is.
  **Seen:** gdstudio #901, 2026-11-10 (`test_aim_pose_view.gd`).
- **Approach:** In a test that steps commands by hand, clear a press (`fire_pressed = false`) before the same command
  is run again, assert that the body still stands on the floor before the part that matters, and compare a shot's
  direction with a tolerance. **Watch out for:** `CommandDriver.run` clears the presses of its own copy, so the next
  run of the same command pressed fire again (two shots); the stream of `test_command_stream.gd` walked 35 m on a 30 m
  floor, so its shot was fired falling and nothing noticed until a target was put in front of it; and a shot starts at
  the muzzle, which the animation holds a few millimetres apart from run to run. **Seen:** gdstudio #901, 2026-11-10.
- **Approach:** Hang a node that belongs to the character (the pistol) on the model's slot, not on a part inside the
  glb's instance, and prove the web export, not only the tests. **Watch out for:** a node added inside an instanced
  scene is there in the editor and in a test and missing from the web export unless the instance is marked editable
  (`[editable path="Model"]`), and it is lost when the model is replaced; #836 shipped without the line
  (`Weapon.muzzle` null, the fire button did nothing, no error) and #844 moved the pistol under the slot, so the line is
  no longer needed ([Replacing the model](character.md#replacing-the-model)); a null `muzzle` is still the sign of a path
  into a part that is gone. **Seen:** gdstudio #836, 2026-11-08; gdstudio #844.
- **Approach:** Size a `Control` that sits by its anchors (the `Crosshair`, at the middle of the screen) by setting its
  four offsets from the exports (`-half`, `half`), not `custom_minimum_size`. **Watch out for:** a minimum size only
  makes a control bigger: shrinking the radius left the rect at its old size, and the test that reads the rect's size
  and middle failed for a smaller circle. The weapon aims through the middle of the viewport, which is the middle of
  this control, so a test compares the two. **Seen:** gdstudio #836, 2026-11-08.
- **Approach:** Start every suite that reads the pistol's buttons (`fire`, `aim`, `crouch`) by letting go of them with
  `Input.action_release`, and run the suites in the CI's order before pushing (`-a` once per suite, as the log lists
  them). **Watch out for:** the file order differs between Windows and the Linux runner, and a base touch suite leaves
  the left mouse button and `fire` down (a mouse release event does not clear the action): the crosshair and touch
  suites passed in every local order and failed 8 tests on the runner, where one of them ran straight after it.
  **Seen:** gdstudio #836, 2026-11-08 (`InputSim.release_all()` lets go of the actions too).
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
  counts a `CharacterBody3D` on `auto_open_mask` (Characters since #924, so the walls never reach it), never a wall,
  floor, prop or the door's own body; the type test stays behind the mask for a game with its own layers. Closing the
  door with a character in range keeps it shut until they leave and come back. **Watch out for:** an `Area3D` reports
  every overlapping body, static ones too: the gate door opened at the start and again after each press of the
  interact button, because its sensor overlapped the gate's posts, the low wall, the floor and the door itself.
  **Seen:** gdstudio #845, 2026-11-08 (`test_door.gd` and `test_gate_in_the_map.gd`).
- **Approach:** Keep a door's sensor and its reach point where the closed door stands: the script moves the sensor and
  the door's `Interactable` back against the panel's motion ([Using things](character.md#interactable)), and
  `close_after` counts from when the last character left. **Watch out for:** a sensor that is a child of a sliding door
  rises with it and loses a character 2 m away; an open swinging gate's origin moves away from its hinge, so the 1.6 m
  reach no longer found it; a test body made at the origin and moved after `add_child` is sensed at the origin for a
  step, so set its `position` before. **Seen:** gdstudio #845, 2026-11-08; gdstudio #925, 2026-11-10 (`interact_point()`
  became the `Interactable` kept at the closed door's place).
- **Approach:** Make every area that reacts to bodies say which bodies, by its mask first (a `Pickup` Characters, a
  `TriggerZone` Characters and Props: [Physics layers](../physics-layers.md#template-layers)) and a class test behind
  it: `characters_only`, then `counts` (`CHARACTERS_AND_PROPS` by default) and `required_group`. Prove it with real bodies
  on their layers: a floor, a block and an `AnimatableBody3D` beside the area must not trigger it, a character must.
  **Watch out for:** the map's pressure pad was pressed at the start by the floor and the landing under it, so the room
  door opened at once and the pad never released; the coins were clean only because no block touched them. A frozen
  `RigidBody3D` did not press the zone in the test (use `gravity_scale = 0`). **Seen:** gdstudio #848, 2026-11-08
  (`test_components_among_blocks.gd`).

- **Approach:** Drive the camera's zoom from the buttons (`Character.aim_held`, `fire_held`) and keep `Character.aiming`
  (the aim or fire button held) for the body and crosshair; give a shot without aiming its own zoom
  (`fire_distance`, `fire_fov`, speeds) with a `zoom_when_firing` toggle, and aiming an `aim_shifts_shoulder` toggle
  (off). Prove it by measuring the distance over the frames after letting go. **Watch out for:** the camera read
  `Player.aiming`, true for 0.8 s after the last shot, so the view stayed zoomed about a second after a shot (aim alone
  zoomed out at once), and a shot was the same zoom as the aim button, which the controller notes say never to couple
  ([Aim and hip fire](../../../gamedev/controller.md#aim)). **Seen:** gdstudio #856, 2026-11-08 (`test_camera_fire.gd`).
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
  head read 0.5 m for a lens 1.1 m from the arm's start. Cause and fix: [Walls](../camera.md#walls). **Seen:** gdstudio
  #856, 2026-11-08.

## Bullet impacts {#impacts}

A shot that lands tells the level's `Impacts` node (`world/world.tscn`, the group `impacts`): a mark on the body it hit
(a flat quad, no `Decal`: the web build's Compatibility renderer draws none), an effect and a sound by the kind of
surface. `Impacts.impact(collider, point, normal)` is the one call. Its inspector list, the surfaces, the metadata a
body names its surface with and the tests are on [Bullet impacts in 3D Third Person](../third-person-impacts.md). A
shot on a character finds the body part in its path and the body answers it: [Hit zones](../third-person-hits.md).

## Effects and the muzzle flash {#effects}

<!-- new section: the pistol had no flash; impacts kept their own pools (gdstudio #888) -->

One `EffectEmitter` (`Effects` in `world/world.tscn`) plays the flash, each impact and other one-shot effects from one
pool ([every inspector value](../effect-emitter.md#using-it)); the `Weapon`'s are `muzzle_flash_enabled`, `muzzle_flash`
and `muzzle_flash_size`. Its warm-up visits every reflection probe of the map (`warm_up_every_probe`) and draws the
materials of the groups `warm_up_groups` names there (`player`), so the room's first visit and first shot build nothing
([the warm-up](../effect-emitter.md#warm-up)).
