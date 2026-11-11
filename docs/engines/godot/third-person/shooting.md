# Crouch, aim and shoot

<!-- new section: split out of the third-person template page when it reached the size limit (#983) -->

The 3D Third Person weapon: crouch, aim and shoot, ammunition, reloading and switching, the bullet impacts and the
effects. Part of [the 3D Third Person template](../third-person-template.md).

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
  the door's `Interactable` back against the panel's motion ([Using things](interact.md#interactable)), and
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

## Ammo, reloading and switching {#weapons}

<!-- new section: the template had one weapon with its numbers on the node; nothing said how a weapon is data, how
     ammunition and a reload count, or how a character switches (gdstudio #887) -->

A weapon is data: a `WeaponDef` resource (`gameplay/weapon/weapon_def.gd`; the template's are `pistol.tres` and
`fists.tres` beside it) holds its name and icon, its kind (`PROJECTILE`, `HITSCAN` or `MELEE`), rate, spread, recoil
(its share of the camera's `shot_kick_amplitude`, cosmetic; 0 for the fists), damage, range and push, the magazine, the
reserve and its largest, the ammunition's `Pickup.item_id`, the reload's time, the switch's times, the projectile's
numbers, the model in the hand (`view`, `muzzle`: paths under the `Model` slot), the clips (grip, aim level, up and
down, the shots, the reload) and the sounds (shot, empty click, the reload's steps at their shares, the draw). A new
weapon is a new `.tres`; nothing else changes.

- **`Weapon`** (one node of the character) fires the definition it holds: `pull(origin, direction)` fires, clicks on
  an empty magazine (`dry_fired`) or does nothing (cooling down, reloading, put away), and `fire()` is the same with
  the projectile back. `reload()` puts the reserve's rounds in at the end of `reload_time`, never at its start, and an
  empty magazine with a reserve reloads by itself (`auto_reload`, for a phone that holds fire). The HUD reads `ammo`,
  `magazine_size` and `reserve` (null for a weapon with no magazine, so the ammo part hides for the fists) and the
  signals `ammo_changed`, `reloaded`, `definition_changed`. A projectile comes from the weapon's pool
  (`projectile_cap`, 24): a finished one parks hidden out of the physics and is fired again, and every projectile of
  a size shares one mesh and shape and every one of a colour one material, so a hundred shots make no resource. A
  hitscan shot is one ray and a hit record (`hit_scanned`: collider, position, normal, from, damage and, on a
  character, the `HitRecord` its `HitZones` delivered, as a projectile's hit does); a blow is a ray of `melee_reach`
  from the chest.
- **`WeaponLoadout`** (`Loadout`, a child of `character.tscn`, so a server's body has it too) holds the `slots` and
  `unarmed`, gives the weapon the definition in the hands, keeps each slot's magazine and reserve while it is put
  away, shows the model of the one in the hands, and fills a reserve from a pickup of its `ammo_item`. A switch takes
  the old weapon's `holster_time` (it cannot fire or reload; a reload under way is cut short and gives nothing), then
  the new one's `draw_time`; asking again during a switch goes there instead. `next()`, `previous()` (the slots, then
  the empty hands) and `toggle_unarmed()`.
- **The command** carries the presses (`reload_pressed`, `next_weapon_pressed`, `previous_weapon_pressed`,
  `unarmed_pressed`: flag bits 11 to 14, `NetWire.VERSION` 3; bit 15 is prone's), from the actions `reload` (R, pad Y,
  the touch Reload), `next_weapon` (wheel down, d-pad right, the touch Swap), `previous_weapon` (wheel up, d-pad left) and
  `toggle_unarmed` (H, d-pad up); the HUD's weapon slots' keys `weapon_1` and `weapon_2` (1, 2, a finger on the slot)
  and a screen that picks a weapon (the inventory) call
  `PlayerInput.request_weapon(slot)`, which sends the same presses one a tick (`WeaponChooser`,
  [Inventory](../inventory.md#template-screen)). The character steps the loadout and then the weapon at the end of
  each `step`, and both are in its step state (`CharacterState.weapon`: cooldown, spread, magazine, reserve, reload;
  `.loadout`), so a server and a predicting client reload and switch on the same tick. What is in the hands is
  gameplay; the clips, the sounds and the flash are cosmetic and never sent.
- **The animation** builds its weapon layer from the held definition (`CharacterAnimation.held_definition()`): a clip
  left empty has no weight, so the fists take no grip and no aim pose, and their two clips alternate (jab, cross). The
  reload is a one-shot on the upper body stretched to `reload_time`; a switch lowers the grip and the aim by
  `WeaponLoadout.lowered_amount()`. A change to a definition's clip rebuilds the tree (`changed`).

Tests: `test_weapon_ammo.gd` (the weapon alone, ticked by hand), `test_weapon_switching.gd` (keys, wheel and mouse in
the physics world), `test_net_command_codec.gd` (the four bits). Captures: `tools/capture/weapons_tour.tscn` (fire to
empty, the click, the reload, the fists and back; `WEAPONS_SIDE=1` from the side) and
`tools/capture/reload_closeups.tscn` (the player's own scene with the clip seeked: the grip, the aim and five moments
of the reload, from the side, above and behind the shoulder; it plays no reload, so the left hand there is the clip's
own) and `tools/capture/pistol_hold_study.tscn` with `HOLD_ONLY=reload` (the hold told of the reload: fourteen shares
of the clip measured and filmed from the gun's two sides, above, under the grip's foot and the player's camera;
`HOLD_RELOAD_STEP=0.01` measures every hundredth instead and `HOLD_SHARES=0.0525,0.7875` the shares given).

Cost, measured headless on the desktop (`tools/bench/weapon_cost.tscn`, 1,000 shots each): a pooled projectile shot 39
µs of script without its sound, a weapon's and its loadout's tick 1.5 to 2 µs, and a thousand shots leave no new
resource (the pool's 24 bodies, one mesh, one shape, one material). The weapons add 4 nodes to a living character (the
`Loadout` and three idle sound players); `NODES_ALIVE` in `test_parts_budget.gd` holds the living character's budget
(56 on 2026-11-11) and lists what each change added. The shot's sound is most of a shot: with the
`ShotSound` playing, a projectile shot measured 400 µs, a hitscan shot 310 to 360 µs and a blow 290 to 350 µs, nearly
all of it `AudioStreamPlayer3D.play()` on headless Godot's dummy audio driver; measure it on the web before taking the
number as a budget.

Hands on the pistol through the reload: the `WeaponHold` follows the reload clip by
`CharacterAnimation.reload_progress()` (how much of the upper body the one-shot holds, and the share of the clip
played, whatever `reload_time` is), so the left hand is on the gun, away for the new magazine, under the magazine while
it goes in and on the gun again, and the trigger finger is off the trigger
([the hold and its numbers](../../../tools/blender/weapons.md#the-third-person-template-pistol)). The hand goes on
and off the gun one way (its fingers open where it holds, then the opened hand leaves along a solved clear line,
`WeaponHold.support_way`), and `SupportHandPlan` (`gameplay/weapon/hold/support_hand_plan.gd`) names the reload's
phases for whatever moves with the hand: `WeaponHold.left_hand().phase` is `HELD`, `LET_GO`, `AWAY`, `REACH`,
`INSERT`, `SEATED` or `RETURN`. It is cosmetic: the rounds go in at the end of `reload_time` whatever the hands do.

- **Approach:** Count a press of an action that can come as an event too short for a physics tick (a wheel notch) as
  the action going down between two commands, or an event seen while the action is up again, never both: keep the
  action's state from the last command and a latch set in `_unhandled_input`. **Watch out for:** a latch from the event
  ORed with `is_action_just_pressed` counted one tap of H twice, so the toggle went to the fists and straight back and
  the switch never ended (four switching cases failed). **Seen:** gdstudio #887, 2026-11-10 (`PlayerInput`'s weapon
  presses).
- **Approach:** Give a weapon in a test its own copy of the definition (`weapon.definition =
  weapon.definition.duplicate()`) before changing a number. **Watch out for:** a `.tres` is loaded once and shared by
  every weapon that holds it, so a suite that sets the fire rate on the shared pistol changes it for every later suite
  of the run; the numbers moved off the node with the definitions, and fourteen suites that set `weapon.fire_rate`
  and the rest now go through a copy. **Seen:** gdstudio #887, 2026-11-10.

- **Approach:** When you add an export to `WeaponDef`, pin its default for the pistol in `test_weapon.gd`'s list in
  the same commit. **Watch out for:** `ExportPins.differences` fails on any export it has no pin for, so the new
  `view_scene` passed every suite run during the work and failed only in the full run. **Seen:** gdstudio #889,
  2026-11-10.

## Weapon pickups and a two-handed hold {#weapon-pickups}

<!-- new section: the weapons section covers a loadout fixed in the scene; nothing said how a game hands a character a
     new weapon, or how a long gun is held when the animation library has no clip for it (gdstudio #889) -->

A weapon lying in the level is a `WeaponPickup` (`gameplay/pickup/weapon_pickup.gd` + `weapon_pickup.tscn`, a
`Pickup` that gives a weapon): its `weapon` (a `WeaponDef`) and `rounds`, the spin, bob, sound and `respawn_time` of
`Pickup`, and the nodes `Visual` (the model goes under it), `Shape` (a 1.2 m wide cylinder), `Glow` (an unshaded
additive ring on the ground in `tint`), `Light` (a 2.2 m omni light in `tint`, no shadow) and `Sound`. A weapon's own
pickup is a scene that inherits it and puts the model under `Visual`: the template's `rifle_pickup.tscn` (the rifle,
60 rounds, 20 s) stands in the prototype map between the spawn and the range.

- **What it gives** goes through the character's loadout, `WeaponLoadout.give(definition, rounds)`: a weapon not
  carried goes in a new slot with a full magazine and `rounds` in the reserve and is brought out
  (`switch_to_new`, on), one already carried takes only the rounds up to `max_reserve` (`Given.AMMO`), and one with
  a full reserve takes nothing (`Given.NOTHING`), so the pickup stays. A body with no `WeaponLoadout` leaves it. The
  pickup says `weapon_taken(collector, definition, given)` and `collected`. Any `Pickup` can give something else by
  overriding `_give(body) -> bool` and `_set_shown(shown)`; `Visual` can be any `Node3D` and bobs about its height in
  the scene.
- **Gameplay and cosmetics.** The carried list is in the loadout's step state (`CharacterState.loadout[6]`), so a
  server and a predicting client agree on what a pickup gave, and a restore takes a given weapon back. The spin, the
  glow, the light and the sound are cosmetic. Adding to `slots` at run time is additive: a screen that lists the
  weapons (an inventory) reads `slots` and redraws on `slots_changed` (a weapon given, or taken back by a restore).
- **The two-handed hold** is `TwoHandHold` (`gameplay/weapon/two_hand_hold.gd` + `two_hand_hold.tscn`; the rifle's
  `rifle_held.tscn` inherits it and adds the gun, the hands' places and the finger poses), the definition's `view`. It
  is not in the character's scene: the loadout makes the definition's `view_scene` under the `Model` slot the first time
  the character carries the weapon, so a character without a rifle carries none of its nodes. Its parts are below:
  [the rifle in both hands](#rifle-hands).
- **The rifle**: hitscan, automatic, 10 shots a second, spread 1.2 degrees, recoil 0.6, damage 22, a magazine of 30,
  60 to 180 in reserve (`rifle_ammo`), reload 2.2 s, holster 0.3 s, draw 0.4 s; Deadnight's synthesised M4A1 sounds
  (`assets/audio/rifle/`, MIT), the shot at -27 dB.

Tests: `test_weapon_pickup.gd` (walking into it gives the rifle and its rounds, it comes back after its time, with the
rifle carried it gives only rounds, with a full reserve it stays, the rifle fires while the button is held, a body with
no loadout leaves it, both hands reach their places and let go when it is put away, the step state takes a given
weapon back) and `test_rifle_hold.gd` ([the rifle in both hands](#rifle-hands)). Captures:
`tools/capture/rifle_tour.tscn` from the game camera (the floating rifle, taking it, the low ready, a walk, the aim, a
burst, the aim up and down, the reload, hip fire, a crouch, a switch to the pistol and back) and
`tools/capture/rifle_hands.tscn` (six close-ups at once in every state).

Cost, measured on the desktop: a pickup's spin and bob 0.8 to 0.9 microseconds a frame; ten rifle pickups drew 35 draw
calls on the Compatibility renderer and 14 on Forward+, the same with their lights as without (each rifle is its near
level's three meshes and the ring). The hold's cost is with [its section](#rifle-hands).

- **Approach:** In a test that walks a character through a pickup with a respawn time, make the respawn longer than
  the whole walk in and out, then wait for it. **Watch out for:** with a 0.5 s respawn the rifle pickup came back
  while the character was still walking out over it and gave its rounds twice (180 in reserve, not 120). **Seen:**
  gdstudio #889, 2026-11-10.
- **Approach:** When a part moves from the scene to being made on demand (the held rifle under `Model`, made by the
  loadout when it is first carried), grep `tools/` for every `get_node` of it too and run each capture scene once: the
  export leaves `tools/` out and no suite loads it. Look such a node up when it is needed (`get_node_or_null`), never in
  `_ready`. **Watch out for:** `rifle_tour.gd` took `RifleHeld` in `_ready`, so after the change every frame of the tour
  printed a `SCRIPT ERROR` and nothing measured the hold, found only when the tour was run for the next round.
  **Seen:** gdstudio #889, 2026-11-10 (fix: `_rifle_out()` looks it up when the rifle is out).

### The rifle in both hands {#rifle-hands}

<!-- new section: the weapons page's hand rules are written for a weapon that rides a hand bone in a clip; a long gun
     with no clip is placed in the model's space with both arms reaching it, and its switch and reload are built in
     code (gdstudio #889, after the maintainer's review of 2026-11-11) -->

How a carbine is held, which the hold copies. The firing hand is high on the pistol grip, with no space left under
the receiver, and the support hand is forward on the hand guard with its thumb along the rail's side, pulling the
rifle back into the shoulder ([Guns & Ammo](https://www.gunsandammo.com/editorial/tactical-shooting-get-ahold-of-that-carbine/248479)).
The trigger finger is taught straight along the lower receiver until the shot
([Soldier Systems](https://soldiersystems.net/2023/07/15/blast-from-the-past-follow-through-consulting-weapon-grip-for-rapid-movement/)).
At the low ready the butt stays in the shoulder's pocket and only the muzzle goes down, about 45 degrees
([The Armory Life](https://www.thearmorylife.com/ready-up-three-ar-rifle-presentation-techniques/),
[Safariland](https://inside.safariland.com/?p=31063)). In a reload the support hand fetches the new magazine from its
pouch and seats it ([Pew Pew Tactical](https://www.pewpewtactical.com/how-to-reload-ar-15/)). Ours beyond those
pages: three fingers round the grip's front with the thumb round its far side, the support palm under the hand
guard with four fingers up its right side and the thumb up its left, the firing hand on the grip through the reload
and the old magazine taken out by hand (the model's magazine is one node, so it leaves and comes back).

- **The stance.** The butt sits in the right shoulder's pocket, a place from `spine_03` in the clip (`low_pocket`,
  `low_pitch` 35, `low_yaw` 20 at rest; `aim_pocket` along `view_pitch` when the character aims or for
  `shot_hold_time` after a shot; `raise_time` 0.15 s, `pitch_limit` 60), so a crouch carries the gun. The chest stands
  turned `chest_turn` (-30 degrees) from the model's front: `two_hand_stance.gd` takes the clip's own turn of the chest
  off first, so a walk or a run that swings the shoulders keeps the left shoulder forward. When the hand guard is
  still farther from the left shoulder than `arm_stretch` (0.97) of the arm, the gun comes back along its barrel until
  the hand reaches (`pull_limit`).
- **The arms** are a `HoldArm` each (the pistol's own reach, given the hand's place in the skeleton's space by the
  stance in the same update), toward `RightHandTarget` and `LeftHandTarget` on the rifle, the elbows toward
  `RightPole` and `LeftPole`. Both are on their places in every update of every state (0.0 mm in 110 poses of both
  mannequins; the engine's `TwoBoneIK3D` aimed at a node is a frame late,
  [the pistol's hold](../../../tools/blender/weapons.md#the-third-person-template-pistol)).
- **The fingers** are a `HandPoseModifier` per hand: `rifle_grip_pose` (three fingers round the grip, the thumb round
  its left side, the index finger straight along the right side over the trigger guard), `rifle_trigger_pose` blended
  over it as the gun comes up (`raised_amount()`: the finger is on the trigger only while aiming or firing, and off it
  through a reload), `rifle_support_pose` (the palm under the hand guard, four fingers up its right side, the thumb up
  its left), `rifle_open_pose` and `rifle_magazine_pose` for the reload. The places and the poses are written by
  `tools/hold/solve_rifle_hold.py` from the rifle's own triangles and both mannequins' skins (`dump_hold_rig.gd`, then
  `write_hold.gd -- <file> rifle`), so no number of them is typed.
- **A switch** is one sequence on the loadout's own times. Going away, the gun goes down to its stow place
  (`stow_pocket`, `stow_pitch`, `stow_yaw`) with both hands on it through the `holster_time`, is hidden in the tick
  the next weapon appears in the right hand, and the arms go from the gun's places to that weapon's pose while it
  comes up (`reach_amount()` falls with `WeaponLoadout.lowered_amount()`). Coming out, the arms go to the stow place
  while the weapon before it goes down, the gun appears in the hands there and comes up through its `draw_time`.
- **The reload** takes only the left hand, by `Weapon.reload_progress()`: its knuckles open first and the rest of
  each finger after them while the hand drops 6 mm (`HandPoseModifier.open_first`), then it goes down and out to the
  thumb's side off the hand guard (`reload_clearance`), across to beside the magazine and onto `MagazineHand`
  (`reload_leave`), closes on the magazine, takes it straight down out of the well (`magazine_well`) and to the belt
  at the left hip (`reload_belt`, a place on the body; `reload_out`), where the magazine is out of sight and changed,
  comes back up and straight in (`reload_in`), and goes back under the hand guard the way it came (`reload_return`).
  The `magazine` node rides the hand.

Measured on the skinned mesh against the rifle (`HandContact`, the same in every clip, since the fingers are absolute
and the arms reach their places):

| Hand | Deepest in | Holding part farthest off |
| --- | --- | --- |
| Female, right | 1.3 mm (1.2 on the trigger) | the palm 4.4 mm, the fingers 2.4 |
| Male, right | 1.4 mm (the palm) | a finger 4.6 mm, the thumb's tip 4.4 |
| Female, left | 1.0 mm | 2.2 mm |
| Male, left | 0.9 mm | 3.4 mm |

Before the rework the clip's fist stood 22 mm inside the grip with its fingers 8 to 17 mm in and the index finger off
the trigger, the left hand 14 to 45 mm inside the hand guard, and the left arm 5 to 98 mm short of its place in the
walk, jog and sprint clips. On the way between its places in the reload the left hand passes at most 4.4 mm
through the hand guard (measured every half hundredth; the test caps it at 6 mm, as the pistol's).

Tests, `tests/gameplay/test_rifle_hold.gd` with `tests/fixtures/rifle_stage.gd` (a mannequin and the hold posed by
hand): both hands within the 2 mm and 5 mm in six locomotion clips at the low ready and aimed, and with the view 30
degrees up and down, on both mannequins, the right palm and thumb among the holding parts; the index finger within
12 mm of `Trigger` only while the rifle is up; the reload every 2 hundredths; and on
the live player with simulated input, every update of idle, walk, sprint, aim, fire, crouch and crouched walk, the
reload by its key, and a switch to the pistol and back (never two weapons, never none, the rifle never shown without
both hands on it, the arms on its places before it shows and leaving after it hides).

Cost, headless on the desktop (`tools/bench/hold_cost.tscn -- rifle`, 40 mannequins, the least of five runs each on
a machine other agents were loading): the rifle's hold 77 microseconds a character a frame against 35 for the
pistol's aimed hold in the same session, so about 2.2 times it (the pistol's figure on a quiet machine is 12.6). It
is five modifiers and the hold's own `_process`; it is worked out on each machine from `aim_amount`, `view_pitch`,
the shots, the reload and the loadout's switch, never sent. Not measured in a browser yet.

Open: the mannequin's arm is short for this rifle's stock. For the left hand to reach the hand guard the butt sits
5 to 9 cm inside the front of the shoulder (the stock's deepest point against the torso's skin, both mannequins, low,
aimed and stowed; `pull_limit` takes it further in a sprint). From the game camera it is hidden; from the side the
stock's end is in the chest. A shorter stock on the model or a support place further back would cure it.

- **Approach:** Judge a hold from both sides of each hand, from above and from the game camera, in every state the
  weapon has, and test each thing a person would call wrong: a palm off the grip, a finger beside the trigger, a
  support hand under the gun and not round it, a hand that leaves the gun where the state does not ask for it, a frame
  of a switch with two weapons or with a weapon and no hands. **Watch out for:** the rifle's first hold put each
  hand's bone on its target and was reported as held, on captures from the right side only: the right hand was a fist
  beside the grip, the left lay palm-up under the hand guard and let go at idle, the fingers were put off to another
  issue, and in a switch the rifle hid after the arms had left it. **Seen:** gdstudio #1040, 2026-11-11 (the
  maintainer's review; fix: the solved places and poses, `reach_amount()` and the tests above).
- **Approach:** Count a fingertip's leaf bone with the finger's last bone wherever skin is sorted by bone, in the
  solver and the test alike, and check a solver's candidate points against the pose it then sets. **Watch out for:**
  the female mannequin's fingertips are weighted up to half to `index_04_leaf_r` and its like, the male's are not:
  `hold_hand.py` moved only the chain's three bones in a candidate, so half of each female fingertip stayed where the
  last pose had it (up to 28 mm off), and the solver and `HandContact` both left out the vertices a leaf carries most
  of (15 on an index finger). The trigger finger then measured 3.8 mm inside the trigger or 15.6 mm from it, read as
  a trigger guard too short for a finger; with the leaf counted it sits 9 mm from `Trigger`, 1.2 mm in. **Seen:**
  gdstudio #889, 2026-11-11 (fix: `Hand.tips`, `hold_rig.py`'s owner rule, `HandContact._owners()`).
- **Approach:** Open fingers that are hooked over a part at the knuckles first, with the hand backing off a little,
  then straighten them, and measure the way between two places at a finer step than the test's. **Watch out for:**
  every finger bone blended to the open pose at one rate swung the left hand's fingertips 22 mm through the hand
  guard for a hundredth of the reload, each joint opened alone was worse (30 mm), a hand moving aside under closed
  fingers pushed the far side's 12 mm in, and one dropping straight down dragged the thumb 11 mm through it.
  **Seen:** gdstudio #889, 2026-11-11 (fix: `open_first`, a 6 mm drop while the knuckles open, then down and aside
  together; 4.4 mm at most).
- **Approach:** Turn the chest to an absolute angle (take the clip's own chest turn off first) and pull the gun back
  along its barrel when the support arm would be over 0.97 of its length. **Watch out for:** a chest turn added on top
  of the clip left the left arm 5 to 98 mm short of the hand guard in the walk, jog and sprint clips, whose shoulders
  swing; idle and aim, which the first captures showed, were fine. **Seen:** gdstudio #889, 2026-11-11 (fix:
  `two_hand_stance.gd`, `arm_stretch`, `pull_limit`; 0.0 mm in 110 poses).
- **Approach:** Seat a palm by the skin the hand bone carries at least half of and the forearm less than 3 % of, and
  solve on both mannequins at once. **Watch out for:** the game's IK bends the wrist 40 to 50 degrees on the rifle's
  grip and the skin at the heel of the palm follows the forearm, so a palm seated by all of its skin stood 5 to 7 mm
  off the grip in the game; the two mannequins' palms differ by 5.8 mm on this grip (the female's is the hollower),
  which leaves one place of the bone 1.2 mm of play between 2 mm in and 5 mm off. **Seen:** gdstudio #889,
  2026-11-11 (the male's palm is pressed 1.4 mm in, the female's is 4.4 mm off).
- **Approach:** Build a solver's distance grid exact only in a band round the surface (`BandField`, 3 cm) with a
  coarse grid beyond it, when the weapon is long. **Watch out for:** the pistol's grid at 1.5 mm over the rifle's
  0.64 m asks a million samples for the nearest triangle at about 90 microseconds each: over 35 minutes against 24 s.
  **Seen:** gdstudio #889, 2026-11-11.
- **Approach:** Give `HandContact.set_weapon()` the weapon after it is shown, and run a new modifier script through
  `--check-only` before a probe or a stage awaits it. **Watch out for:** `set_weapon()` skips meshes that are not
  visible in the tree, so a rifle still hidden by the loadout measured as no weapon at all (every part 30 mm off); a
  parse error in a modifier's script leaves the skeleton with nothing that dirties it, `skeleton_updated` never comes
  and `HoldStage.settle()` waits for ever with no error after the first line. **Seen:** gdstudio #889, 2026-11-11.

## Bullet impacts {#impacts}

A shot that lands tells the level's `Impacts` node (`world/world.tscn`, the group `impacts`): a mark on the body it hit
(a flat quad, no `Decal`: the web build's Compatibility renderer draws none), an effect and a sound by the kind of
surface. `Impacts.impact(collider, point, normal)` is the one call. Its inspector list, the surfaces, the metadata a
body names its surface with and the tests are on [Bullet impacts in 3D Third Person](../third-person-impacts.md). A
shot on a character finds the body part in its path and the body answers it: [Hit zones](../third-person-hits.md).

## Effects and the muzzle flash {#effects}

<!-- new section: the pistol had no flash; impacts kept their own pools (gdstudio #888) -->

One `EffectEmitter` (`Effects` in `world/world.tscn`) plays the flash, each impact and other one-shot effects from one
pool ([every inspector value](../effect-emitter.md#using-it)); the `Weapon`'s switch is `muzzle_flash_enabled`, and the
flash and its size are the definition's (`WeaponDef.muzzle_flash`, `muzzle_flash_size`). Its warm-up visits every
reflection probe of the map (`warm_up_every_probe`) and draws the materials of the groups `warm_up_groups` names there
(`player`), so the room's first visit and first shot build nothing ([the warm-up](../effect-emitter.md#warm-up)).
