# Crouch, aim and shoot

<!-- new section: split out of the third-person template page when it reached the size limit (#983) -->

The 3D Third Person weapon: crouch, aim and shoot, the bullet impacts and the effects. Part of [the 3D Third Person template](../third-person-template.md).

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
  `filter_enabled` and filter paths for `spine_01` and every bone under it (`Armature/Skeleton3D:<bone>`), the aim pose
  over it by the camera's pitch in a blend space (`Pistol_Aim_Down` -45, `_Neutral` 0, `_Up` 45) and the recoil last;
  off aim and fire only the gripping hand (`hand_r` and what is under it) takes the grip pose, so the arms and spine
  follow the locomotion (`PlayerAnimation.carry`, `grip_clip`, `grip_bones`). **Watch out for:** the holding pose at
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
  2026-11-08.
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
- **Approach:** Keep a door's sensor and its reach point where the closed door stands: the script moves the sensor back
  against the panel's motion, `close_after` counts from when the last character left, and `interact_point()` tells
  the `Interactor` where to measure from. **Watch out for:** a sensor that is a child of a sliding door rises with it
  and loses a character 2 m away; an open swinging gate's origin moves away from its hinge, so the 1.6 m reach no
  longer found it; a test body made at the origin and moved after `add_child` is sensed at the origin for a step, so
  set its `position` before. **Seen:** gdstudio #845, 2026-11-08.
- **Approach:** Make every area that reacts to bodies say which bodies, by its mask first (a `Pickup` Characters, a
  `TriggerZone` Characters and Props: [Physics layers](../physics-layers.md#template-layers)) and a class test behind
  it: `characters_only`, then `counts` (`CHARACTERS_AND_PROPS` by default) and `required_group`. Prove it with real bodies
  on their layers: a floor, a block and an `AnimatableBody3D` beside the area must not trigger it, a character must.
  **Watch out for:** the map's pressure pad was pressed at the start by the floor and the landing under it, so the room
  door opened at once and the pad never released; the coins were clean only because no block touched them. A frozen
  `RigidBody3D` did not press the zone in the test (use `gravity_scale = 0`). **Seen:** gdstudio #848, 2026-11-08
  (`test_components_among_blocks.gd`).

- **Approach:** Drive the camera's zoom from the buttons (`Player.aim_held`, `fire_held`) and keep `Player.aiming` (the
  aim or fire button held) for the body and crosshair; give a shot without aiming its own zoom
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
body names its surface with and the tests are on [Bullet impacts in 3D Third Person](../third-person-impacts.md).

## Effects and the muzzle flash {#effects}

<!-- new section: the pistol had no flash; impacts kept their own pools (gdstudio #888) -->

One `EffectEmitter` (`Effects` in `world/world.tscn`) plays the flash, each impact and other one-shot effects from one
pool ([every inspector value](../effect-emitter.md#using-it)); the `Weapon`'s are `muzzle_flash_enabled`, `muzzle_flash`
and `muzzle_flash_size`.
