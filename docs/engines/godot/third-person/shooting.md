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

The weapon and the aim pose read no camera (gdstudio #901). `Character.aim_ray()` is the ray a character aims along,
from the command of its last step: the command's shot block when it has one (the human's crosshair, written by
`PlayerInput`), else from the character's eye (its camera target) along the command's `yaw` and `pitch`, which is how an
AI or a test shoots. The body calls `Weapon.fire(origin, direction)`; `fire()` with no ray shoots straight out of the
muzzle. A `Weapon` with no `muzzle` and a `shooter` (a body with no model, as a server has) fires from
`no_muzzle_offset` beside the ray's point at the shooter (the default is where the pistol's muzzle is while aiming
standing on the template's idle, which `AimStance` holds still: under 0.3 mm off on the player's body in
`test_weapon_ray.gd`). The cooldown is counted in `Weapon.tick(delta)`: a weapon alone ticks itself (`self_ticking`), a
`Character` turns that off and ticks its weapon last in every `step`, and `CharacterState.weapon` holds the cooldown and
the spread's place for `restore()`.

- **Approach:** Stand a crouched `CharacterBody3D` up only after a shape query above it comes back empty, with a probe a
  little narrower than the capsule and starting a hand above the floor, and prove it with a ceiling slab that ends 2 m
  ahead (let go under it, stay crouched, walk out, stand) and a tunnel 1.25 m high the standing character cannot enter.
  **Watch out for:** a probe as wide as the capsule that starts at the floor touches the floor and the walls at the
  sides and never lets the character stand; a capsule cannot be shorter than two radii, so `crouch_height` is clamped
  to `2 * radius + 0.01`. **Seen:** gdstudio #836, 2026-11-08.
- **Approach:** Hold the upper body's turn under an aim pose that is layered from the spine up: a
  `SkeletonModifier3D` before the hands' modifiers puts the first upper-body bone on the turn its parent has in the
  aim clip (`AimBrace`, weighed by the aim blend, on the ground state only). Test the barrel's angle to the aim ray
  standing through the idle's whole loop and walking, with the modifier off as the failing case.
  **Watch out for:** a filtered layer rides the pelvis of the clip under it, and the library's pistol poses were
  made on a pelvis turned 13.3 degrees: over our own idle, which stands square, the pistol pointed 14 to 18.5
  degrees off the view, and over the library's own walk 13 to 17. The brace holds the turn only: the muzzle still
  moves with the pelvis (34 mm each way with our idle's weight shift). **Seen:** gdstudio #1154, 2026-11-11
  (`tests/gameplay/test_aim_brace.gd`).
- **Approach:** Stand a standing aim on a still pose: the ground blend space's idle point is a blend tree of the idle
  playing and the same clip held on one frame (`AnimationNodeAnimation`, `use_custom_timeline` on, `timeline_length` 0,
  `stretch_time_scale` off, no loop, `start_offset` the frame), blended by the aim weight (`AimStance`). Find the frame
  in the clip (its pelvis nearest its mean place) each time the tree is built, and measure the muzzle through the idle's
  whole loop (`test_aim_stance.gd`). **Watch out for:** a test that read point 0 as a clip (`.animation`) broke; a fixed
  time suits one idle only; the settle to the middle takes the aim's rise (40 mm of pelvis in 0.15 s) and moves the feet
  2.2 mm. **Seen:** gdstudio #1206, 2026-11-11 (34.6 mm each way without it, 0.0 with it); #1256 (the `form`
  bodies: 33.2 mm without, 0.0 with on both).
- **Approach:** When a clip is replaced, measure every layer that plays over it, in every state it plays in, and
  take a test's reference point from a bone of the pose. **Watch out for:** the aim's only measure was taken
  standing on the library idle, so the walk's fault went unseen and the swap of the idle was the first to fail it;
  a point fixed in the model's space (the middle of the library idle's torso) was outside the body of an idle that
  stands 65 mm further forward. **Seen:** gdstudio #1154, 2026-11-11 (`test_weapon_ray.gd`,
  `test_pistol_clearance.gd`).
- **Approach:** Layer a held weapon on the upper body only: an `AnimationNodeBlend2` and a one-shot with
  `filter_enabled` and filter paths for `spine_01` and every bone under it (`Armature/Skeleton3D:<bone>`), the aim pose
  over it by the look's pitch in a blend space (`Pistol_Aim_Down` -45, `_Neutral` 0, `_Up` 45) and the recoil last;
  off aim and fire only the gripping hand (`hand_r` and what is under it) takes the grip pose, so the arms and spine
  follow the locomotion (`CharacterAnimation.carry`, `grip_clip`, `grip_bones`). **Watch out for:** the holding pose at
  weight 1 the whole time a weapon was held made the character walk, jog and sprint with the pistol held out like an
  aim; the pistol clips are whole-body poses, so without
  the filter the legs stop walking. **Seen:** gdstudio #836, 2026-11-08; gdstudio #877, 2026-11-10 (found by the
  maintainer).
- **Approach:** Add a shot's recoil to the aim pose: the one-shot in `MIX_MODE_ADD` with the clip less its own first
  frame (`ShotLayer`, `WeaponDef.shoot_additive`), proved by the muzzle's pitch through a shot at every aim pitch from
  45 down to 45 up, standing and crouched (`test_shot_kick.gd`). **Watch out for:** a recoil clip made at the level
  aim replaced the aim pose, so every shot swung the pistol to about 16 degrees above level: 100 degrees up from a look
  45 down (the gun at the sky between shots at a crouched target), 80 down from a look 45 up. A dozen shots in a row
  empty the magazine and a reload plays over the last (`Weapon.make_ready()` first). **Seen:** gdstudio #1280,
  2026-11-11 (from the maintainer's play-test in #1251).
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
- **Approach:** On a character, aim at the body part the crosshair's ray meets, not at the capsule it meets first
  (`HitZones.aimed_point`; a ray between the parts goes on past the body), and prove it with the player's rig and
  pistol at 2 to 4 m, the crosshair on the edge of the head and beside it (`tests/gameplay/test_close_shot.gd`).
  **Watch out for:** the muzzle sits about 0.4 m left of and below the shoulder camera's line, so a shot sent at the
  capsule's front (0.25 m before the head) crossed the crosshair's line there and went on up and to the right, past
  the head's edge to the wall, while the gun pointed at the target; a test at 12 m or on the head's middle passes
  either way. **Seen:** gdstudio #1251, 2026-11-11 (found by the maintainer).
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
- **Approach:** In a test that makes the player shoot through its input, hold `aim` until the arm is up (about 20
  ticks) and then press `fire`. **Watch out for:** a shot needs `aim_amount` to reach `shot_aim_amount` within
  `fire_buffer_time` of the press, so a tap of fire from a standing player fired nothing and the section's "one shot
  is heard" test saw no noise. **Seen:** kit #969, 2026-11-11 (`test_ai_section.gd`).
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

## Aim layer {#aim-layer}

<!-- new section: the crouch-aim-shoot section covers the aim clips and the weapon layer; nothing said how a weapon is
     pointed at the aim in a move whose pose the clips were not made for (a slide pointed the pistol at the sky) -->

The weapon layer's aim clips are posed for a body standing upright: the upper body takes the aim pose relative to the
hips. A move that leans the hips (the slide lies back nearly flat, a crouch or a lying body bends them) carries the
whole aim with it, so sliding pointed the pistol at the sky (the layer has to bend the chest about 88 degrees to level
it), and a slide that keeps the body along its line cannot aim to its side at all. The aim layer is an aim offset over
the move's pose: the `AimLayer` node of the character makes an `AimOffsetModifier` (a `SkeletonModifier3D`) on the
model's skeleton that, after the clips, turns `spine_01` to `spine_03` by the pitch and yaw that put the muzzle on the
aim. The arms, hands and weapon ride the spine, so they follow.

What engines offer for the same job: Unreal's Aim Offset is a blend space of additive aim poses by yaw and pitch
([Aim Offset](https://dev.epicgames.com/documentation/en-us/unreal-engine/aim-offset-in-unreal-engine)), which needs a
pose set per move; Unity's Multi-Aim Constraint turns a chain of bones toward a target, each by a weight
([Animation Rigging](https://docs.unity3d.com/Packages/com.unity.animation.rigging@1.3/manual/constraints/MultiAimConstraint.html)).
The layer is the second kind: it needs no clips (no custom aim poses were made) and works for any weapon with a muzzle
and any move, measured on the pose of that very frame. Godot's own modifiers aim one bone at a node
([SkeletonModifier3D](https://docs.godotengine.org/en/stable/classes/class_skeletonmodifier3d.html)), not a point on
something a chain carries, so it is a modifier of its own, in the shape of `HoldArm`.

**The solve.** The muzzle's pose is worked out from the bones' local poses (the chain's parent, the chain, then the
bones from the last spine bone down to the hand the `BoneAttachment3D` rides, times the muzzle's fixed place on it, read
once). The aimed direction runs from the muzzle to a point `converge_distance` (15 m) along the character's aim ray
(`Character.aim_ray()`, the last two steps blended by the physics interpolation fraction, as the aim clips' pitch is),
with its heading off the model's +Z and its elevation held within the move's limits. The pitch is solved first, about
the model's side axis (the chest bending forward or back), so the muzzle reaches the aim's elevation; then the yaw about
up, to its heading. Both are exact for the direction. The whole turn is one rotation, and each bone turns by its share
of it (`slerp` from identity) about the same axis, so the shares add up to it exactly; a second pass takes in the
muzzle's own swing round the spine (1.3 to 1.8 degrees off with one pass, 0.1 to 0.5 with two, in `test_aim_layer.gd`).

**Order and weight.** Modifiers run in the order of the skeleton's children, so the layer sits right after the
`WeaponHold`'s grip (whose wrist turn moves the muzzle) and before its support arm, which reaches for the weapon where
the turn left it: the left hand, the fingers and the trigger finger stay on the gun with no change to the hold.
`WeaponHold` says `built` when it makes its modifiers again, and the layer puts itself back after the grip. The layer is
on by the aim's weight (`CharacterAnimation.pistol_weights().y`) less the reload's; a weapon with no muzzle (the fists)
turns nothing.

**Recoil.** While the shot's one-shot plays (`CharacterAnimation.is_shooting()`), the turn found before the shot is kept
and moved only with the aim, so the recoil the clip shows is not turned away; after it the turn eases back over
`release_time` (0.12 s). The pistol's shot clip is added to the aim (`WeaponDef.shoot_additive`, `ShotLayer`), so the kick
is about 16 degrees up from whatever pitch the aim has (`test_shot_kick.gd`, gdstudio #1280).

**Moves and limits.** Each move's tuning holds an `AimLimits` (on or off, the most left and right of the way the body
faces, the most up and down): `CharacterTuning.aim_limits` standing and `crouch_aim_limits` crouched (70, 70, 45, 45),
`SlideTuning.aim_limits` (75 each side, 50 up, 70 down), `ProneTuning.aim_limits`; `Character.aim_limits` is the one of
the move it is in. Standing, crouched and lying the body still turns to the view while aiming, so the layer covers the
turn's lag and the clips' own error. Sliding, the body keeps along the slide (`CharacterSlide.aim_facing`) while the aim
is within the side limits; past them it turns just enough to bring the aim back in reach, or, for a weapon whose
`WeaponDef.past_aim_limit` is `REFUSE_SHOT`, keeps its line and the trigger does nothing until the aim is in reach
(`AimLimits.REACH_MARGIN`, 2 degrees, keeps the edge from flickering). The facing and the refusal are in the step, so a
server and a predicting client agree; nothing new is sent.

**Online.** The layer is a pose on each machine. A puppet is placed with `facing` and `view_pitch` from the snapshot
and, while aiming, the aim's heading off the body (one signed byte in the player entry, gdstudio #1277), so on another
screen a sliding player's upper body turns and the pistol points to the side as on the player's own screen
([puppets](online-client.md#puppets)).

**How it goes with the other aim work.** A steadier stance under the aim (#1206) and a one-handed pistol hold (#1085)
change the clips and the hold that the layer reads; the layer measures the muzzle on whatever pose they leave, so they
need nothing from it and it needs nothing from them: a steadier clip only makes its turn smaller. A one-handed hold
whose support arm is off leaves the layer as it is.

**What it costs** (`tools/bench/aim_layer_cost.tscn`, 40 dressed players aiming 30 degrees off their facing, the
modifier timed alone on a shared machine under load): about 31 to 37 microseconds a character a frame with two passes,
25 with one (`passes`), against 9 for the hold's support arm in the same run. Only an aiming character pays it (the
modifier is off at weight 0). The web export was not measured.

The tests are `tests/gameplay/test_aim_layer.gd` (sliding ahead, 50 degrees left and right, 20 up and 25 down within 3
degrees with the body along the slide; without the layer the slide misses by more than 10; past the reach the body turns
by the overshoot; a refusing weapon keeps the body and fires nothing until the aim is back; standing and crouched; the
limits are the move's; a zero limit holds the aim along the body). The capture is `tools/capture/slide_aim_tour.tscn`
(`AIM_LAYER_OFF=1` shows the clips alone, `CLOSE=1` and `CLOSE_SIDE=left` film the hands).

- **Approach:** Solve an aim offset as a pitch about the body's side axis first, then a yaw about up, and hold the
  *aimed direction* within the limits, not the turn. **Watch out for:** a yaw about up first, then a pitch, with the
  turn clamped, is ill-conditioned when the clip points the muzzle near vertical (the slide: the heading of a direction
  almost straight up is noise): the first draft hit its limits and missed by 15 to 90 degrees while standing passed.
  **Seen:** gdstudio #1253, 2026-11-11 (`test_aim_layer.gd`).
- **Approach:** Turn a chain of bones toward a goal by one rotation shared out by `slerp` from identity, each part about
  the same axis, walk the chain's global poses forward from its parent, and read the muzzle's place on its attachment
  once. **Watch out for:** two rotations (pitch and yaw) each shared over the chain double the bone writes, and
  `HandPoseModifier.global_pose` called for every bone and every muzzle read walks to the root each time. **Seen:**
  gdstudio #1253, 2026-11-11 (`aim_layer_cost.tscn`).

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

**Hitscan, a toggle on any weapon** (gdstudio #1252). `WeaponDef.hitscan` (the Hitscan group, with `hitscan_range`,
100 m, and `hitscan_mask`, `PhysicsLayers.SHOT_MASK`) turns a projectile weapon into an instant ray from the aim:
nothing is made for the shot, the muzzle flash, the shot sound and the impact where the ray hits are all there is, and
a tracer only when the definition names one (`WeaponDef.tracer`, below). It is read at each shot
(`WeaponDef.shot_kind()`: `MELEE` stays a blow, `hitscan` or a `HITSCAN` kind is a ray, else a projectile), so it
switches live; the range and the mask are greyed out while it is off. The
ray goes through the same aim as a projectile (`Weapon.aim_point()`: the muzzle toward what the aim ray meets) and
the same hit (`HitZones.shot` and `deliver`, so the part, its multiplier and a refused friend's shot are the same, or a
`Health`). Online it costs only its `SHOT` and `HIT` (15 bytes each, in the same TICK), and the server meets it with
the AI where the shooter drew it at once ([shots online](online-shots.md#template-shots)). `tools/capture/hit_tour.tscn`
with `HIT_HITSCAN=1` films the pistol hitscan from the player's camera.

What one pistol shot costs in all (`tools/bench/shot_cost.tscn`: a shot a tick at a wall 20 m out, so a tick holds one
launch and one whole flight; a tick's time less an idle tick's, the median of 7 blocks of 300 ticks, two runs; Windows,
Godot 4.7.2, headless, 2026-11-11, other agents on the machine; the headless run draws nothing, so a client's round
costs its drawing on top):

| | Projectile | Hitscan |
| --- | ---: | ---: |
| Server: the shot in all (the call, then 26 to 27 ticks of flight) | 432 to 711 µs | 20 to 35 µs |
| Server: the call that fires | 84 to 114 µs | 20 to 31 µs |
| Client: a puppet's shot in all, with its sound / without | 404 to 637 / 392 to 649 µs | 11 / 6 to 10 µs |
| Rounds in the air at a shot a tick | 26 | 0 |
| Bytes down each other player (`SHOT` + `HIT`) | 30 | 30 |
| Bytes of state while it flies | 0 | 0 |

On the wire the two are the same: the template never sent a projectile's state, so a shot was always its two events;
what hitscan saves is the server's and every client's flight work (and, against the AI, the per-tick rewind meet of a
projectile's first `ai_rewind_flight_seconds`, 2.1 µs a character near its path a tick, [the rewind](ai-online.md#rewind)).
`tools/net/bandwidth.py --shoot` (the bots fire at each other) with and without `--hitscan` measured (seven bots
and one predicting client, 30 s each, the same machine; a run's deaths change the players' rows, so the down rate moves
a few per cent either way between runs):

| `bandwidth.py --shoot` | Projectile | Hitscan |
| --- | ---: | ---: |
| 8 players: shots, hits (server) | 336, 208 | 336, 336 |
| 8 players: down a client, B/s (mean / most) | 3510 / 3523 | 3554 / 3569 |
| 8 players: server step p50 | 1.70 ms | 1.29 ms |
| 4 players: shots, hits; down a client; step p50 | 144, 143; 2208 B/s; 1.15 ms | 144, 137; 2294 B/s; 1.00 ms |

The bytes are the same within a run's noise (each shot is its two events either way). The step p50 followed the
machine's load more than the weapon (a second hitscan run at 8 players read 2.52 ms, its down rate 3208 B/s), so the
bench above, where the modes take turns, is the server's cost of a shot: a hitscan shot about a twentieth of a
projectile's. A `--shoot` bot puts a shot block on every command, so its up rate (about 1.9 KB/s) is not a client's
and the run does not judge it.

**A tracer, optional on a hitscan weapon** (gdstudio #1270). `WeaponDef.tracer` (the Hitscan group, empty by default,
greyed out while the shot is not hitscan) names a `TracerDef` (`gameplay/effects/tracer_def.gd`; a ready-made one is
`gameplay/weapon/pistol_tracer.tres`, which no weapon holds): `color` and `energy` (additive, so it never darkens),
`width` (0.03 m, turned to the camera), `speed` (320 m/s, 0 shows the whole line at once), `length` (3 m),
`fade_time` (0.1 s) and `start_offset` (0.1 m out of the flash). A hitscan shot then draws a streak from the muzzle
to where its ray ended (`Weapon._scan` answers the point, or the reach): it leaves the muzzle at its full length, so
the frame of the shot shows it, runs to the end and its last `length` metres fade there. The level's `TracerPool`
(`Tracers` in `world/world.tscn`, `gameplay/effects/tracer_pool.tscn`, the shader
`assets/shaders/effects/tracer.gdshader`) draws every streak of the map with one `MultiMesh`: one draw call however
many show, no node per shot, a cap of 32 (16 on the web) that cuts the oldest, hidden with its `_process` off when
nothing shows. It is cosmetic and costs nothing on the wire: the server's weapon has `effects` off and draws none,
the shooter's screen draws its own from its ray, and a puppet's is drawn from the puppet's muzzle along the SHOT's
heading and ended at the HIT on the server's ray ([shots online](online-shots.md#template-shots)). Its warm-up draws
one unseen streak through the `EffectEmitter`'s warm-up, so the first streak links no program in the web build.
`tests/gameplay/test_tracer.gd` and `test_tracer_online.gd` hold it; `tools/capture/hit_tour.tscn` with
`HIT_HITSCAN=1 HIT_TRACER=1` films it.

What it costs (`tools/bench/tracer_cost.tscn`: the pistol hitscan with its flash, light and impacts, a run of 5 s after
1 s, 1280 x 720, vsync off; Windows, Godot 4.7.2, an RTX 5080, other agents on the machine; the web build in headless
Chrome on the GPU through `tracer_cost.py`, whose frames are held near 4.17 ms, so its means cannot show a change):

| Run | Compatibility: frame ms, draw calls | Forward+: frame ms, draw calls | Web: frame ms, draw calls, programs linked |
| --- | ---: | ---: | ---: |
| hitscan, 4 shots a second | 1.98, 274.7 | 1.67, 417.3 | 4.17, 275.2, 7 (the first shot's, without a tracer) |
| hitscan and tracer, 4 a second | 2.04, 275.3 | 1.70, 417.7 | 4.17, 275.5, 0 (2 and a 37 ms frame before the warm-up waited for the emitter's) |
| hitscan, 30 a second | 2.49, 533.5 | 2.05, 624.8 | 4.17, 549.1, 0 |
| hitscan and tracer, 30 a second | 2.66, 534.2 | 1.74, 622.8 | 4.17, 547.7, 0 (most streaks at once: 4) |

| Script cost (µs) | Desktop | Web |
| --- | ---: | ---: |
| `TracerPool.draw` (the write waits for the frame's step) | 1.1 | 1.05 to 1.45 |
| a step with 4 streaks (what 30 shots a second keep) | 14.3 | 14.2 to 15.1 |
| a step with the pool full (32 desktop, 16 web) | 104 | 53 to 55 |
| a step with none (its `_process` is off then) | 1.0 | 1.2 |

A streak is a draw call while it shows (the means moved by less than the machine's noise); the frame pays its step,
about 3.5 µs a streak, and nothing while none shows. The web build linked 3 programs more while the level started
(150 to 153), the streak's.

- **Approach:** Keep a fast streak on screen for whole frames: start it at its full length and let its last stretch
  fade at the end for 0.1 s or more. **Watch out for:** a streak whose tail ran on past the end before it faded lived
  0.02 s on a 7 m shot, less than a frame at 30 fps, and the first capture from the game camera showed no tracer in any
  frame although every test passed. **Seen:** gdstudio #1270, 2026-11-11 (`hit_tour.tscn`, 30 fps).
- **Approach:** Write a pool's `MultiMesh` once a frame from one `PackedFloat32Array`
  (`RenderingServer.multimesh_set_buffer`), marking it dirty on a draw. **Watch out for:** `set_instance_transform`,
  `_color` and `_custom_data` for each streak, rewritten on every draw, cost 87 to 96 µs a call with the pool full; the
  buffer and the deferred write took a draw to 1.1 µs. **Seen:** gdstudio #1270, 2026-11-11 (`tracer_cost.tscn`).
- **Approach:** Warm a `MultiMesh` effect's program by keeping an unseen instance drawn until the `EffectEmitter`'s
  warm-up (and its probe tour) is over (`warmed`), then a few frames more. **Watch out for:** three frames of an
  unseen streak at the level's start still left the first streak 2 programs and a 37 ms frame in Chrome: it had been
  drawn before the probes the camera sees had their first faces. **Seen:** gdstudio #1270, 2026-11-11
  (`tracer_cost.py`).

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
- **`WeaponLoadout`** (`Loadout`, a child of `character.tscn`, so a server's body has it too) holds the `slots` (`WeaponDef`s,
  typed `Array[Resource]` with a `WeaponDef` hint: [why](../test-exit-leaks.md#typed-array-export-and-self-cast)) and
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
- **What aim and fire do** is the weapon's too (`WeaponDef`'s Aim and zoom group, gdstudio #1255): `can_aim` (off:
  the aim button does nothing), `fire_needs_aim` (on: fire shoots only with the aim button held, and never with
  `can_aim` off; `WeaponDef.fire_allowed()`), `fire_zooms` (off: holding fire leaves the camera's framing alone; the
  camera's own `zoom_when_firing` must be on too) and `show_crosshair` (off: the `Crosshair` stays hidden). With
  `override_zoom` on, the weapon's `aim_fov`, `aim_distance`, `fire_fov`, `fire_distance` and `zoom_offset` (further to
  the chosen shoulder and up, blended in with the zoom) replace the camera's. The defaults keep the pistol as it was; the
  fists have `fire_zooms` off, so a punch does not zoom. The character reads `can_aim` and `fire_needs_aim` every step
  from the definition its server body holds too (gameplay); `PlayerCamera.held_definition()` and the `Crosshair` read
  the rest every frame (local, never sent), so every toggle applies while the game runs. Tests:
  `test_weapon_aim_toggles.gd`; capture: `tools/capture/fire_zoom_tour.tscn` (pistol fire zooms, fist fire does not).

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
and lists what each change added. The shot's sound is
most of a shot: with the `ShotSound` playing, a projectile shot measured 400 µs, a hitscan shot 310 to 360 µs and a blow
290 to 350 µs, nearly all of it `AudioStreamPlayer3D.play()` on headless Godot's dummy audio driver; measure it on the
web before taking the number as a budget.

Hands on the pistol through the reload: the `WeaponHold` follows the reload clip by
`CharacterAnimation.reload_progress()` (how much of the upper body the one-shot holds, and the share of the clip
played, whatever `reload_time` is), so the left hand is on the gun, away for the new magazine, under the magazine while
it goes in and on the gun again, and the trigger finger is off the trigger
([the hold and its numbers](../../../tools/blender/weapons.md#the-third-person-template-pistol)). The hand goes on
and off the gun one way (its fingers open where it holds, then the opened hand leaves along a solved clear line,
`WeaponHold.support_way`), and `SupportHandPlan` (`gameplay/weapon/hold/support_hand_plan.gd`) names the reload's
phases for whatever moves with the hand: `WeaponHold.left_hand().phase` is `HELD`, `LET_GO`, `AWAY`, `REACH`,
`INSERT`, `SEATED` or `RETURN`. The magazines follow it: the old one drops at the reload's first sound, a new one rides
the left hand from the belt into the grip, a reload cut short leaves the pistol whole, and the slide locked open on an
empty pistol runs forward at the last sound
([the magazine and the slide](../../../tools/blender/weapon-hands/two-handed-pistol-grip.md#the-magazine-through-the-reload)).
It is cosmetic: the rounds go in at the end of `reload_time` whatever the hands do.
How the two hands hold the pistol together, the trigger finger's way to the trigger and the hand's retreat when the
arm is short are on [The two-handed pistol grip](../../../tools/blender/weapon-hands/two-handed-pistol-grip.md#between-the-poses).

The slide's rack is a clip of the template's own, `pistol/Pistol_Rack` (`assets/animation/pistol/`, kit #1081): it
starts and ends on the pose the reload ends on, and its `SlideRack` resource
(`gameplay/weapon/hold/pistol_slide_rack.tres`, with the male body's `pistol_slide_rack_male.tres` in its `fits`:
`SlideRack.fit()` gives the one solved on the model's body) gives the left hand's place on the slide, its fingers
closed on the slide and opened over it, the slide's travel and the shares at which it is gripped, pulled and let
go. The reload does not play it yet (kit #1052); the test
`test_pistol_rack.gd` and the capture `tools/capture/rack_closeups.tscn` play it on a stage
([the clip and its numbers](../../../tools/blender/weapons.md#the-third-person-template-pistol)).

- **Approach:** Count a press of an action that can come as an event too short for a physics tick (a wheel notch) as
  the action going down between two commands, or an event seen while the action is up again, never both: keep the
  action's state from the last command and a latch set in `_unhandled_input`. **Watch out for:** a latch from the event
  ORed with `is_action_just_pressed` counted one tap of H twice, so the toggle went to the fists and straight back and
  the switch never ended (four switching cases failed). **Seen:** gdstudio #887, 2026-11-10 (`PlayerInput`'s weapon
  presses).
- **Approach:** Clear a weapon's answer for the shot (`_last_projectile`) at the start of every shot, in the one
  function every way of firing goes through (`_shoot`), not in one caller. **Watch out for:** `pull()` cleared it and
  `fire()` did not, so `fire()` of a hitscan shot after a projectile handed back the old round as if it had just left.
  **Seen:** gdstudio #1252, 2026-11-11 (`test_the_toggle_fires_a_ray_with_no_projectile_and_switches_back_live`).
- **Approach:** In a test that shoots one character several times, stand it back where it was (`teleport`) and let
  the flinch end before each shot. **Watch out for:** a hit pushes the body back; the fourth shot of a suite comparing
  a projectile and a hitscan head shot met nothing, the body a step further on, and read as a hitscan fault.
  **Seen:** gdstudio #1252, 2026-11-11 (`test_a_hitscan_shot_takes_the_part_and_damage_a_projectile_takes`).
- **Approach:** Give a weapon in a test its own copy of the definition (`weapon.definition =
  weapon.definition.duplicate()`) before changing a number. **Watch out for:** a `.tres` is loaded once and shared by
  every weapon that holds it, so a suite that sets the fire rate on the shared pistol changes it for every later suite
  of the run; the numbers moved off the node with the definitions, and fourteen suites that set `weapon.fire_rate`
  and the rest now go through a copy. **Seen:** gdstudio #887, 2026-11-10.

- **Approach:** When you add an export to `WeaponDef`, pin its default for the pistol in `test_weapon.gd`'s list in
  the same commit. **Watch out for:** `ExportPins.differences` fails on any export it has no pin for, so the new
  `view_scene` passed every suite run during the work and failed only in the full run. **Seen:** gdstudio #889,
  2026-11-10.

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
