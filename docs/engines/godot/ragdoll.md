# Ragdolls with PhysicalBone3D

<!-- new section: the 3D Third Person ragdoll (gdstudio #846) was the first use of PhysicalBone3D; nothing held how
Godot 4.7.2 builds the joints, which engine to run them on or how to test a body that is thrown by a bad start -->

How `PhysicalBone3D`, `PhysicalBoneSimulator3D` and their joints behave in Godot 4.7.2, found while giving the
Quaternius mannequins a ragdoll (the template's own section is
[Ragdoll in 3D Third Person](#template)). Measured headless on Windows with the pinned
Godot 4.7.2, Godot Physics and Jolt, on both mannequins.

## Building the bones {#building}

<!-- new section: a joint is built at one moment from the bodies' places then, and a later offset does not rebuild it -->

A ragdoll is a `PhysicalBoneSimulator3D` under the `Skeleton3D` with one `PhysicalBone3D` per bone that moves. The
simulator is the only node that needs to exist while the character lives: with `active` off it costs nothing, and
`physical_bones_start_simulation()` hands the skeleton to the bodies. A bone that has never simulated keeps the
collision layer it was made with in the physics server (the engine zeroes it only when a bone stops), so it sits in
the world as a static body: zero the layer and mask of every bone not simulating
([Shots meet ragdoll bones](physics-layers.md#shots-meet-bones), gdstudio #876).

- **Approach:** Make every bone's `joint_offset` first, then put every body where its joint is to rest (a cone's centre,
  the middle of a hinge's range) in global space, and set the `joint_type` last, bone by bone. **Watch out for:** in
  4.7.2 `PhysicalBone3D` builds its joint in `set_joint_type` (and again on entering the tree when it already has a
  type) from the two bodies' current global transforms and the joint offset; `set_joint_offset` does not rebuild the
  joint, it only moves the body back onto its bone, and the engine forces the joint's origin onto the bone's own
  origin. A joint typed before its neighbours were posed measured its limits from the wrong frame, so the body started
  outside them and was thrown. Source: `scene/3d/physics/physical_bone_3d.cpp`. **Seen:** gdstudio #846, 2026-11-09
  (fix: `CharacterRagdoll._build` sets offsets, poses, then types).
- **Approach:** Free a server joint made between two bones (`PhysicsServer3D.joint_create`) before the bones go: on the
  simulator's `tree_exiting`, and make it again on `tree_entered`. **Watch out for:** a model swap deletes the skeleton
  with the bones in it, and freeing the joint after that crashed the engine (signal 11 in `free_rid`, in the swap
  test). **Seen:** gdstudio #940, 2026-11-10 (`CharacterRagdoll._free_braces`).
- **Approach:** Generate the bones from the skeleton each time the model changes (the slot's `rig_changed`), name the
  simulator, give nothing an owner, and rebuild live when an export changes. **Watch out for:** bones saved in a scene
  live inside the model's glb, which a swap deletes, and the two mannequins' rests differ by up to 9 cm; Create
  Physical Skeleton makes joints at the rest pose (a T-pose) with the twist axis across the bone, and a skeleton left
  open in the editor drifts (godot issue 112007). A standalone saved scene instanced on `rig_changed` works on both
  mannequins but has the rest-pose centre. **Seen:** gdstudio #846, 2026-11-09 (`test_ragdoll.gd`: 16 bones after a
  run-time swap); gdstudio #872, 2026-11-10 (editor-saved against generated, measured in a throwaway game).
- **Approach:** Read the ragdoll's pose from the `PhysicalBone3D` bodies (`global_position`, `global_basis`,
  `linear_velocity`), never from `Skeleton3D.get_bone_global_pose`. **Watch out for:** the simulator is a skeleton
  modifier, whose pose is applied after the skin update and discarded, so the bone poses of the skeleton show the
  animation while the body is limp and a test that read them found the ragdoll standing. **Seen:** gdstudio #846,
  2026-11-09.
- **Approach:** Let the bones collide with each other: put the ragdoll's own layer (5) in its `collision_mask`
  (`PhysicsLayers.RAGDOLL_MASK`), keep the bones off layer 1, and keep each body apart from the one it hangs from with
  `PhysicsServer3D.body_add_collision_exception(a, b)` both ways, once, when the bones are built. **Watch out for:** a
  mask of the level only let limbs through the trunk (13 to 17 cm, in 80 to 90 percent of the frames of a death); the
  "fighting" was a body and its parent overlapping at their joint, and 4.7.2 gives `PhysicalBone3D` no exclusion for
  them on either engine (godot PR 70945 is open). Layer 1 would put the bones in the way of the camera's spring arm and
  the ground probes ([Physics layers](physics-layers.md#template-layers)). **Seen:** gdstudio #872, 2026-11-10 (found by
  the maintainer; `test_ragdoll_natural.gd`: non-adjacent capsules overlap under 6 cm).
- **Approach:** Start each bone with its own linear and angular velocity, read from where the animation moved it over
  the last physics frame (sample the 16 bodies' animated poses every tick while alive, then
  `(now - before) / dt` and the axis-angle of `now * before.inverse()` over `dt`, and drop a sample that moved over
  40 m/s: it was a teleport), so a swinging limb keeps swinging when the body goes limp. **Watch out for:** every bone
  given the character's velocity and no spin keeps the pose in free fall, since gravity moves all of them alike: a
  body killed at the top of a jump stayed in its jump pose until it hit the floor, and a clip that holds a pose has no
  velocity to give (see [Going limp](#going-limp)). **Seen:** gdstudio #872, 2026-11-10 (found by the maintainer on the
  #846 ragdoll, `CharacterRagdoll` `pose_velocity`).
- **Approach:** Make the bones on the first death, sample the animated pose from the skeleton while alive
  (`RagdollPose`: indices found once, two arrays swapped, the body offset put on at the death), keep the samples when
  the bones are made, and prove the first death with a test that needs the per-bone velocity. **Watch out for:** the
  build clears the old bones first, and clearing the samples there too gave every first death the character's
  velocity alone: the one-pass control of `test_ragdoll_cones.gd` read 2 degrees past a shoulder's range instead of
  over 25, while every other ragdoll suite passed. Bodies made at the death give the death of bodies made at the spawn
  to within Jolt's rounding (0.2 mm after half a second). **Seen:** gdstudio #926, 2026-11-10 (fix: `_clear` keeps
  the sampler).

## Joint limits {#limits}

<!-- new section: a joint's limits are read in a frame that is not the obvious one, and wrong limits throw the body -->

A ragdoll that dies in a pose its joints do not allow is snapped into range in one step, and the solver turns that
into speed.

- **Approach:** Take the limits from a body's range of motion: elbows -5 to 150 and knees -5 to 140 degrees as hinges,
  the others cones (spine 20 and 12, then 30 and 20; head 45 and 60; shoulder 100 and 60; hip 70 and 35; wrist 60 and
  60; ankle 35 and 15, swing then twist), the same left and right, and push the animated pose inside them when the body
  goes limp (`CharacterRagdoll._clamped_world`; `tools/ragdoll/measure_joints.gd` shows how far the clips go past).
  **Watch out for:** limits widened to hold every clip pose plus 10 degrees let an elbow lean 73 degrees and a knee 39
  in a run's death (hinges: 8, 17); a limit narrower than the death pose throws the body unless the pose is
  clamped. Sources: NASA-STD-3000, Luttgens and Hamilton; Unity, Jolt, Godot. **Seen:**
  gdstudio #846, 2026-11-09; gdstudio #872, 2026-11-10 (`test_ragdoll_natural.gd`: no hinge off its axis by 25).
- **Approach:** Know the sign: a hinge or 6DOF limit angle has the opposite sign to the turn of the child body about the
  axis, on Godot Physics and on Jolt; make the joint at the middle of its range with the same limit each way
  (`CharacterRagdoll` does) and the sign stops mattering, or test it with a probe that places a body at a known angle
  first. **Watch out for:** a limit written with the sign of the turn you measured limits the other way, and the body
  is then outside it from the first step. **Seen:** gdstudio #846, 2026-11-09 (probed on both engines).
- **Approach:** Make a knee or an elbow a `HINGE` joint, not a 6DOF: Z on the bend axis, X along the bone
  (`CharacterRagdoll.hinge_frame()`), `angular_limit_upper` and `lower` in degrees. **Watch out for:** Jolt reads a 6DOF's
  angular limits as swing-twist with a Pyramid swing (`jolt_generic_6dof_joint_3d.cpp`), so a big bend with a lean and
  a roll in it is a box, which is how #846's elbows went sideways; a hinge is exact over the whole range. Jolt ignores
  `bias`, `softness` and `relaxation` of a cone or a hinge (a warning if not default); a cone's `swing_span` is the
  half-angle on both axes, its twist symmetric, and it is a cone in 4.7.2 (issue 119926). Shoulders and hips stay
  cones. **Seen:** gdstudio #846, 2026-11-09 (6DOF); gdstudio #872, 2026-11-10 (4.7.2 Jolt source, lab runs).
- **Approach:** Leave about 25 degrees of slack when a test asserts a joint is in its limits at rest. **Watch out
  for:** a limit is a soft stop against a load: an arm pinned under the torso rested up to 17 degrees past its twist
  and side limits on both elbows, run after run, with an 8 degree tolerance failing 4 runs in 6. A joint started
  outside its limits is a different thing and is caught by the speed test below. **Seen:** gdstudio #846, 2026-11-09
  (`LIMIT_SLACK` in `test_ragdoll.gd`).
- **Approach:** Hold elbows and knees with several hinges between the same two bones (`hinge_passes`, 6: the bone's
  own joint and `PhysicsServer3D.joint_make_hinge` copies with its frames and limits), and judge it over many
  deaths: over 70 lab deaths, with 4, the mean worst overrun went from 12.9 to 4.1 degrees, the worst from 51 to 17,
  the deaths past the 25 degree slack from 10 to 0. **Watch out for:** a limb the trunk lands on gives way (an elbow
  at 178, or 50 backwards) under Jolt's project-wide 10 velocity and 2 position steps; 4.7.2 gives scripts no
  per-joint step override. Projecting the joint back before each step, heavier forearms, more damping and less
  `relax_gravity` did not help. **Seen:** gdstudio
  #872, 2026-11-10 (four solver settings); gdstudio #940, 2026-11-10 (`test_ragdoll_hinges.gd`; 3 hinges: 5.1 and
  22, 6: 2.4 and 12).
- **Approach:** Hold the cones the same way (`cone_passes`, 6: `joint_make_cone_twist` copies, frames as the bone's own,
  spans in radians) and take the shoulder's twist to 45 where a person turns 60. Over 70 lab deaths, against a person's
  range: the shoulders' mean worst overrun went from 25.5 to 2.8 degrees, the worst from 114 to 24, the deaths past the
  25 degree slack from 16 to 0; the other cones from 36.2, 70 and 55 deaths to 13.1, 31 and 3; the hinges, 6 each, 5.1
  and 20 (none past). **Watch out for:** every cone gives way under the body, not only the shoulder (a hip or a wrist 20
  past standing), and Jolt's steps do not reach it: 20 velocity steps left the shoulders at 25.4 and 109, 30 and 4
  position steps at 18.5 and 78, 4 copies at 9.1 and 38. A narrower twist alone missed the worst death (40: 105).
  **Seen:** gdstudio #975, 2026-11-10 (`test_ragdoll_cones.gd`; 27 settings).
- **Approach:** Make the copies round by round over the whole body (`RagdollBraces`), not joint after joint, and
  judge every count over the 70 deaths. **Watch out for:** Jolt solves joints in the order they were made and the
  last one wins: all hinges then all cones moved the give onto the elbows (11.0 and 34, 4 deaths past), cones first
  onto the shoulders (11.6 and 47); and the numbers are not monotone in the count (cones 8: shoulders 2.9 and 38;
  cones 6, hinges 8: 4.2 and 34). **Seen:** gdstudio #975, 2026-11-10.
- **Approach:** When bodies change skeleton (a set of bones moved by the pool), free the joint copies before the move
  and make them again after the bones' own joints, as a new body's are. **Watch out for:** Jolt keeps a server joint
  whose bodies leave the world and makes it again as they return, body by body, so a kept set held its copies limb
  after limb, and the staged shoulder death twisted 44 degrees past a person's; setting each copy's limit again to
  remake it in order did not mend it (Jolt takes a removed joint's place with its last one), and changing a joint's
  limit or a body's shape makes the joint again too. **Seen:** gdstudio #1022, 2026-11-10
  (`test_a_pooled_set_holds_a_shoulder_the_body_rolls_over`).

## Godot Physics or Jolt {#jolt}

<!-- new section: the ragdoll blew up on the default engine and not on the other; the choice belongs to the project -->

- **Approach:** Run a ragdoll on Jolt (`3d/physics_engine="Jolt Physics"` in the project's `[physics]` section) and
  measure it with the stress test: many deaths at random moments of the animation, the fastest bone after the fall
  below 12 m/s. **Watch out for:** on Godot Physics (4.7.2's default) this ragdoll blew up in 10 to 20 percent of
  deaths, bones at about 300 m/s, even when every joint started inside its limits and with more solver iterations; on
  Jolt 180 random deaths on both mannequins gave none, and every other suite of the template still passes on Jolt. The
  engine is a project setting, so a template that needs a ragdoll sets it: the choice is the maintainer's to know
  about (the template list and the pull request say so). **Seen:** gdstudio #846, 2026-11-09 (180 deaths per engine in
  a throwaway game; the same stress as a test now).
- **Approach:** Keep Jolt for the ragdoll, and read the engine's sleeping as part of the cost: Jolt puts every bone of a
  lying body to sleep a few seconds after the fall (64 of 64 asleep, the physics time back to an empty world's
  0.03 to 0.07 ms), Godot Physics keeps jointed bodies awake. **Watch out for:** with the anatomical table and the
  clamped pose Godot Physics still threw bones in 6 of 12 lab deaths (230 to 500 m/s, a pelvis 12 to 30 m up;
  the old table and the new alike, 3 of 4 scenarios for the old), Jolt in none of 40 (fastest 12.8 m/s); and on Godot
  Physics a lying body cost 0.15 to 0.5 ms a tick for as long as it lay there (0 of 160 bodies asleep after 9 s).
  **Seen:** gdstudio #872, 2026-11-10 (lab: standing, running, ledge, side push, jump, both mannequins).

## Going limp in the air {#going-limp}

<!-- new section: a body killed in the air kept its pose until it landed; a free-falling ragdoll does that by itself -->

Gravity moves every bone alike, so a ragdoll in free fall with the same velocity on every bone keeps its pose, whatever
the joints. That is physics, and not what a death looks like.

- **Approach:** Give each bone its own velocity from the animated pose (above), and for about a third of a second pull
  the limbs down (`relax_gravity`, 12 m/s squared: forearms, calves, hands and feet fully, upper arms and thighs
  half, the head 0.6, by `apply_central_impulse(mass * g * share * delta)` each tick), so the legs straighten and the
  arms hang as muscles let go. **Watch out for:** a pose velocity does nothing for a clip that holds a pose (the
  jump's hold has no limb speed), a jog's hips rise 1.5 m/s at push-off so the body leaps a little (that is the
  clip), and 18 m/s squared for 0.4 s folded the body into a crouch on landing. Jolt ignores joint softness, which
  would do it too. **Seen:** gdstudio #872, 2026-11-10 (`test_ragdoll_natural.gd`: a hand or foot moves 0.2 m
  against the pelvis within 0.23 s of a death at the top of a jump).

## Drawing between ticks {#drawing}

<!-- new section: the ragdoll's sections covered the bodies and their joints; nothing said how its skin is drawn on a
screen faster than the physics, which physics interpolation does not do for it -->

With `physics/common/physics_interpolation` on, every `PhysicalBone3D` node is drawn between the last two ticks like
any body (`get_global_transform_interpolated()` glides), but the skin is not: the `PhysicalBoneSimulator3D` writes each
bone's pose once a tick (`PhysicalBone3D::_body_state_changed` sets the bone to the body's tick transform), and the
skin follows the bones. At 144 frames a second over 60 ticks a moving body holds for two or three frames and jumps
while the camera, a pusher and the bodies themselves glide: the judder of an un-blended camera, on the body instead.

- **What draws it.** `RagdollDrawing`, a `SkeletonModifier3D` the `CharacterRagdoll` puts on the skeleton right after
  its simulator, sets every simulated bone to `skeleton_drawn⁻¹ × body.get_global_transform_interpolated() ×
  body_offset⁻¹` (the skeleton's own interpolated transform, so a flinch on a running body is right too); under an
  `influence` below 1 (the get-up fade, a flinch) it moves the simulator's pose by that share of the way from the
  tick's body to the drawn one. It is off while nothing is simulated and while the pelvis sleeps (Jolt sleeps and wakes
  a jointed body as one island), so a body lying still costs one check a tick. `draw_between_ticks` on the Ragdoll
  node turns it off.
- **Bodies placed by hand.** Every bone whose transform a script sets before it is simulated (the start pose, a flinch
  set, a body kept lying through a rebuild) calls `reset_physics_interpolation()`, or it is drawn sliding in from where
  it was parked or held.
- **Proof.** `test_ragdoll_drawing.gd` runs `main.tscn` at 25 ticks a second under the suite's 60 frames (2.4 frames
  a tick, as 144 over 60) and lets the map's moving block push the body; a modifier last on the skeleton
  (`DrawnPoseProbe`) reads the drawn pose each frame. The scene runner sets the project's tick rate when it is made:
  set the test's rate after `scene_runner()`. `tools/capture/ragdoll_push.tscn` is the clip; `tools/bench/
  ragdoll_drawing_bench` the cost.

- **Approach:** Draw a ragdoll's skin from the bodies' interpolated transforms (a modifier after the simulator), and
  measure it at 144 frames over 60 ticks against the camera, the pusher and the body nodes, one column each. **Watch
  out for:** physics interpolation glides the `PhysicalBone3D` nodes and not the bones they write, so a body pushed
  along by the moving block read a sawtooth on screen, 13.2 px RMS second difference at 1280 by 720 (peak 18.9) while
  the body nodes read 0.10, the block 0.13 and the camera was smooth; the drawing took the skin to 0.12 px, and the
  same push read 7.3 cm between skin and body on `main` against 0.0 with it. **Seen:** gdstudio #1126, 2026-11-11
  (found by the maintainer playing; the probe's frame-by-frame table is in the pull request).

## What a ragdoll costs {#cost}

<!-- new section: the template targets the web, and nothing said what a ragdoll costs there or how to bound it -->

Measured with the engine's physics-process time (`Performance.TIME_PHYSICS_PROCESS`) per 60 Hz tick, headless on the
desktop and in a single-threaded web export (Chromium, SwiftShader; the browser quantises the timer to 0.1 ms).

- **Approach:** Budget about 0.1 to 0.2 ms per limp ragdoll per tick on the desktop in the first second, half that after;
  cap how many lie limp at once (`max_active`, 4: the extra deaths play the death clip) and let Jolt put the rest to
  sleep. **Watch out for:** 10 ragdolls cost 2 ms in the first second on the desktop (4: 0.9, 1: 0.5) and about 2 ms at
  seconds 2 to 3 in the web export (4: 0.5), with one tick of about 8 ms in the browser's first second; self
  collision and 11 bodies instead of 16 changed nothing beyond the 10 to 20 percent spread, so neither is a lever;
  Godot Physics never sleeps a jointed body. The export is single-threaded and contains Jolt. **Seen:** gdstudio #872,
  2026-11-10 (`LABPERF` runs, N = 1, 4 and 10, both engines, and the web runs).
- **Approach:** Measure the web cost in the real game: a probe scene loads `main.tscn`, adds players, kills them in one
  tick and prints the physics time per second; export it as the main scene, read it in headless Chromium through `gds
  quiet`, and keep runs whose time before the deaths is the usual 0.5 to 1 ms. **Watch out for:** on a
  shared machine two runs in three were noise. Clean runs: one death 1.7 to 2.4 ms in the first second, 0.4 to 0.9
  after; four 3.1 to 3.4, then 0.7 to 1.3; ten (four limp) 4.3, then 1.1 to 1.4; asleep by about 10 s. Jolt's steps
  30 and 4 made four deaths 5.0 ms. **Seen:** gdstudio #872, 2026-11-10 (the probe `game_perf.gd`).
- **Approach:** Price extra joint copies (`hinge_passes`, `cone_passes`) with the same probe, alternating the settings
  run by run. **Watch out for:** four hinges per elbow and knee cost nothing measurable (4.7 ms over the first two
  seconds with one and with four, 0.9 then 0.8 after); six copies of every joint (90 extra joints a body) cost about
  a sixth more in the first two seconds (6.6 to 7.6 ms, mean 7.2, against 5.9 to 6.5, mean 6.2, on a busy machine)
  and 0.9 to 1.3 against 0.8 to 1.2 after; every body still sleeps. **Seen:** gdstudio #940, 2026-11-10 (`passes=1`
  against `passes=4`); gdstudio #975, 2026-11-10.
- **Approach:** Take a settled body out of the budget: after `settle_time` seconds with every bone asleep the node says
  `settled`, stops counting toward the cap and a game frees the body there; beyond `ragdoll_range` metres from the
  camera a death is the clip. **Watch out for:** how long a body takes to lie still depends on the pose it died in
  (3 to 6 s in the lab, the animation clock being real time), so a test waits up to 15 s and asserts the event, and
  the bones of a body that is never settled (Godot Physics) keep the cap's slot until it gets up. **Seen:**
  gdstudio #872, 2026-11-10.

- **Approach:** Count what a ragdoll costs while its character lives, not only limp: make the bones on the first
  death and keep the per-tick pose sample free of allocation. **Watch out for:** 16 static `PhysicalBone3D`s with
  their shapes and simulator (33 nodes) made at the spawn cost 14 to 16 µs a character a frame with no bone moving (25
  walking: 1.94 ms with them, 1.55 ms without), and the sample (16 `find_bone` calls and a new dictionary a tick) 11 to
  14 µs more: a third of a walking character's frame. Made on the first death they cost it about 1 ms on the desktop
  and 4.5 ms in the web export, once a character. **Seen:** gdstudio #926, 2026-11-10
  ([What the parts cost](third-person/character.md#parts-cost)).
- **Approach:** Hand a dying character a set of bones made earlier (`RagdollPool`: `max_active` sets made one a frame
  after the first character arrives, parked under a disabled node, given back when a character is freed). For the
  same rig and settings keep the bodies' offsets, materials and joint poses, and make the joint copies again from a
  plan (`RagdollBraces.remake`); warm the first set (limp for no time, moved once) behind the loading. **Watch out
  for:** a moved set still makes every joint again ([Joint limits](#limits)): a first death costs 0.45 ms on the
  desktop and 1.0 ms in Chrome (0.9 and 2.6 to 2.8 made at the death), a later one 0.15 and 0.3 to 0.4; about 0.4 ms
  of a browser's first death in a run is that death's own first-time work, not the bones. **Seen:** gdstudio #1022,
  2026-11-10 (`parts_cost_bench.tscn`, `test_ragdoll_pool.gd`).

- **Approach:** Count the drawing between ticks per frame, not per tick ([Drawing between ticks](#drawing)): it runs
  each drawn frame while a body moves and stops when the pelvis sleeps. **Watch out for:** a frame rate over the tick
  rate multiplies a per-frame cost: 4 falling ragdolls cost 9 to 10 µs a ragdoll a frame on the desktop (p95 11 to
  13) and 14 to 16 in Chrome (p95 25 to 50, the browser's 0.1 ms clock), 138 at a 4x CPU throttle, with a check of
  1.4 to 1.8 µs (web 4 to 5) a ragdoll a tick; under a tenth of the limp body's own physics. **Seen:** gdstudio
  #1126, 2026-11-11 (`tools/bench/ragdoll_drawing_bench`).

## Ragdoll in 3D Third Person {#template}

<!-- new section: the template page reached its 50 KB limit, so the template's ragdoll moved here, beside the engine -->

The template's character dies into a ragdoll and gets up again, the usual hybrid: an animated `CharacterBody3D` with
its capsule while alive, a full ragdoll while dead, and a blend back to the animation on getting up.

- **What it is.** `Character.die()` and `revive()` (`is_dead()`, the `died` and `revived` signals, `State.DEAD`). Dying
  stops the animation tree, turns the capsule off, ignores every gameplay input and lets the `Ragdoll` component
  (`CharacterRagdoll`) take the pose on screen, pushed inside the joints' limits, each bone keeping the velocity the
  animation gave it and the limbs let drop for a third of a second (a death in the air goes limp there). When the
  ragdoll declines (over `max_active`, or past `ragdoll_range` from the one who watches) the character plays
  `ual1/Death01` (`Character.died_by_clip`). The ragdoll reads no camera: `can_start(viewer)` and `start(velocity,
  viewer)` take where the watcher is, which the character asks of its controller (`viewer_position()`: the drawn
  camera for `PlayerInput`, `Vector3.INF` for nobody, so a body on a server or under an AI with no camera always gets
  its ragdoll). The camera orbits and follows the hips. A ragdoll below the tuning's `fall_limit` says `fell` (the
  `Player` starts again at its spawn point); `teleport()` and the player's `respawn()` get a dead character up at
  once. Getting up stands the body under the hips, facing the
  chest's way, restarts the animation and fades the ragdoll's hold out over `get_up_time`; `revive_at(spot)` does the
  same with the body standing at `spot` (online, where the server says), so the pose blends there from where the bones
  lie. The library has no get-up
  clip; a game with one plays it with `play_clip()` from `revived`.
- **The inspector.** On `Character`, the group Ragdoll: `ragdoll_body` (the component), `ragdoll` (a live bool: tick
  it in the inspector or the remote inspector to kill, untick to get up) and `ragdoll_by_command`; on `Player`,
  `ragdoll_key` (Y by default; None turns the key off). The key is added to the input action `ragdoll` when the game
  runs, next to anything a game binds there in the Project Settings; it is a testing aid, so a game that ships without
  it sets None. On `Ragdoll`: `mass` (the whole body, shared out by the segment masses of a person), `thickness` (the
  capsules), `joint_range` (how far the joints swing, as a share of a person's range), `hinge_passes` (how many hinges
  hold each elbow and knee, 6: one lets a limb the body lands on fold past its range, [why](#limits)), `cone_passes`
  (the same for every cone, 6: one lets a shoulder twist 50 to 115 degrees past a person's range), `linear_damp`,
  `angular_damp`, `friction`, `bounce`; Editor: `editor_preview` (the bones shown in the editor, on); Death and
  getting up:
  `carry_velocity`, `pose_velocity` (each bone's own velocity, on), `relax_gravity` and `relax_time` (the limbs let
  drop, 12 m/s squared for 0.35 s), `get_up_time`; Cost: `draw_between_ticks` (the skin drawn between physics
  ticks, on, [why](#drawing)), `max_active` (4 limp at once in the game), `settle_time` (8 s, then `settled` and the
  cap's slot is free) and `ragdoll_range` (0, any distance); Collision: `collision_layer`
  (`PhysicsLayers.RAGDOLL`, the ragdoll's own, layer 5) and `collision_mask` (`RAGDOLL_MASK`: the level, props and its
  own layer, so limbs rest on the floor, a crate, the body and each other, never on the bone they hang from; no player
  capsule, camera wall, ground probe or trigger area sees a bone, and a shot does: it stops at the bone, pushes it and
  leaves a mark on it, [Physics layers](physics-layers.md#shots-meet-bones); hit zones are layer 6). A shot that kills
  throws the bone it hit, and one that does not makes the hit part flinch, a partial ragdoll on the same bones
  ([Hit zones](third-person-hits.md)).
  Every one applies live, has a pinned default and a test.
- **Why the bones are generated.** The 16 `PhysicalBone3D`s (no fingers) hang off a `PhysicalBoneSimulator3D` named
  `RagdollBones` under the `Model` slot's skeleton, made from `CharacterRagdoll.BODIES` (or taken from the
  `RagdollPool`, which makes a few sets after the level loads and takes back those of a character that is freed,
  [cost](#cost)) on the character's first death
  (or when a script asks for one: `body()`, `body_count()`, `simulator()`, which a living character's first
  flinch (`HitReaction`) asks for; `has_bones()` asks nothing) and again whenever the rig
  changes after that, in the editor at once while `editor_preview` is on (Debug, Visible Collision Shapes), never
  saved: the glb a swap deletes would hold them. A character that never dies never carries them
  ([cost](#cost)). Any rig with these
  65 bones works: the Quaternius mannequins and the prototype bodies the template's characters wear (kit #1187; the
  capsules were measured against the `form` bodies' skin with `tools/mannequin/measure_segments.gd` and fit it but
  for the calves, now 0.055 m; thinner arms and legs let the jogging male's shoulder twist 28 to 35 degrees past a
  person's range in `test_ragdoll_cones.gd`, so the rest stay). Generated, not the editor's Create Physical
  Skeleton: a joint's zero is the pose it is made in (here a neutral pose, there the T-pose), the swap needs code
  anyway, and the mannequins differ by up to 9 cm ([why](#building)).
- **How the limits are set.** A person's: hinges for elbows and knees (each held by `hinge_passes` hinges), cones for
  the rest (each held by `cone_passes` cones; the copies are `RagdollBraces`), the same both sides, the shoulder's
  twist 45 where a person's is 60 ([numbers](#limits)); a cone's centre is the clips' mean direction
  (`tools/ragdoll/measure_joints.gd`). The pose is pushed inside the limits as the body goes limp: a joint that starts
  outside throws it.
- **The engine is Jolt.** The template's `project.godot` sets `3d/physics_engine="Jolt Physics"`: on Godot Physics this
  ragdoll blew up in 10 to 20 percent of deaths and a lying body never sleeps. Every game made from the template gets
  it, and the maintainer should know ([why](#jolt), [cost](#cost)).
- **The map.** The prototype level has a `RagdollLedge` group (a ramp and a ledge, 3 m up, in the south, past the push
  cubes): run up it and off the east edge, or press Y at the top. The blocks are new and not in the baked lightmap, so
  they are lit by the sun and the sky until the level is baked again.

- **Approach:** Prove a ragdoll in the game's own camera on both models: run, press Y mid-run, orbit the body, press Y
  to get up, then run off the ledge; read the frames before the report. **Watch out for:** a stress test that passes
  says no bone flew, not that the body lies on the floor in a believable pose, which only the clip shows (the
  frames are from `tools/capture/ragdoll_tour.tscn`, run through `gds capture` as in
  [A route for a clip](third-person-template.md#walkthrough)). **Seen:** gdstudio #846, 2026-11-09.

## A partial ragdoll: the flinch {#partial}

<!-- new section: the page covered the whole body going limp; nothing covered a few bones simulated while the clip
     keeps the rest, which the template's flinch does and which threw arms to NaN in the AI soak (gdstudio #1326) -->

`physical_bones_start_simulation(bones)` makes the listed bones rigid and every other bone **kinematic, on the
ragdoll's layers**, moved to the clip's pose each tick. Measured in the AI soak with Godot 4.7.2 and Jolt (16 bodies,
the template's `HitReaction` flinch); four things threw a flinching arm, each fixed in `hit_reaction.gd`:

- **Approach:** Before a partial simulation starts, put every body at the clip's pose through the server
  (`body_set_state(BODY_STATE_TRANSFORM)` with the body made static for the move) and zero every body's velocities
  there, again after the start. **Watch out for:** while the simulator rests a body's node transform does not reach the
  server, so a body waits where the last death or flinch left it, and its first kinematic move covers that whole way
  in a tick: 64 m/s after a get-up 1 m away (1.1 m in the first tick in the test). A kinematic body also keeps a
  speed the server had (481 m/s from an arm thrown by the flinch before). **Seen:** gdstudio #1326, 2026-11-12
  (`test_a_flinch_after_getting_up_starts_from_the_clip_pose`); gdstudio #1338, 2026-11-12 (from the game camera: an arm
  drawn as a rod for two to five frames).
- **Approach:** Take the bodies a partial simulation leaves out off every layer while it runs. **Watch out for:** the
  engine leaves them kinematic on the ragdoll's layers, so a flinching arm pressed against the trunk was squeezed
  between a body the clip moves and its own joint, both immovable to it; shots and aim rays also met a living body's
  bones instead of its hit zones. **Seen:** gdstudio #1326, 2026-11-12
  (`test_the_bodies_a_flinch_leaves_out_touch_nothing`).
- **Approach:** Push a flinching body at its middle (`apply_central_impulse`) and cap the speed the push gives it
  (`flinch_most_speed`, 3 m/s). **Watch out for:** a shot's impulse (40 N·s times 0.6) at the hit point spun a forearm,
  a thin capsule of a kilogram, at Jolt's angular limit (47 rad/s) and gave it 12 m/s. **Seen:** gdstudio #1326,
  2026-11-12 (`test_a_flinch_push_moves_a_light_limb_and_does_not_spin_it`).
- **Approach:** Free the extra joints of [the limits](#limits) (`RagdollBraces`) while a few bones simulate and
  remake them when the flinch ends, after the bones' own joints. **Watch out for:** six copies of a joint whose
  parent the clip moves (a kinematic body, as heavy as the world to the solver) turned a light arm at 47 rad/s within
  two ticks and sent it off at 500 m/s (Jolt's linear limit), then to NaN; with one joint, every soak seed ran clean.
  A limp body lying wedged against two blocks with its braces still goes the same way (gdstudio #1372).
  **Seen:** gdstudio #1326, 2026-11-12 (`test_a_flinch_lifts_the_extra_joints_and_gives_them_back`).

- **Approach:** Hold every simulated bone of a flinch, and of the get-up blend, at its rest distance from its parent
  with a modifier right after the simulator (`RagdollLengths`: `set_bone_pose_position(bone, rest.origin)`), keeping
  the turn the body gives it. **Watch out for:** the bones between two bodies that have no body of their own (the
  clavicles, the neck) keep moving with the clip, and the joint holds the next body where the rest pose had it, so the
  skin stretched 10 to 15 cm in a hit clip on a walking or crouched body; starting the bodies inside their joint
  limits made no difference. A limp body needs none of it: the clip stops and its joints keep the bones within 1 cm.
  **Seen:** gdstudio #1338, 2026-11-12 (`test_hit_bone_lengths.gd`, both bodies).

A flinching body farther than 0.6 m from the clip or faster than 15 m/s ends the flinch at once (`FLINCH_STRAY`,
`FLINCH_TOO_FAST`); a flinch at its strongest reads 0.36 m and 5 m/s.

- **Approach:** Cast a basis read off an animated pose to a quaternion with `get_rotation_quaternion()`, not
  `Quaternion(basis)`. **Watch out for:** a pose is a rotation only to a few thousandths, and `Quaternion(basis)`
  logs `get_quaternion: !is_rotation()` and returns the identity, so a death's pose pushed inside the joint limits
  (`inside_limits`) read 67 degrees off and the AI soak's error gate broke. **Seen:** gdstudio #1326, 2026-11-12
  (`test_a_turn_a_little_off_square_is_held_with_no_error`).

## Testing a body that the engine throws {#testing}

<!-- new section: a single death proves nothing and the animation clock is real time -->

**The lab is not in the template.** The "lab deaths" above come from a ragdoll lab (several variants dying at one
moment in one pose, a viewport tile each, numbers printed: limb overlap, joints past anatomy, fastest bone) that was
never committed: its scenes and scripts (`lab.tscn`, `lab.gd`, `game_perf.tscn`) are kept in the workspace's scratch
folder of gdstudio #940 (`lab-src/`). Only `tools/ragdoll/measure_joints.gd` is in the template's tools. Copy the lab
into a game made from the template to run it (`scenario=`, `variants=`, `model=` and `seconds=` after `--`).

- **Approach:** Test a ragdoll with many deaths at random waits in every pose the player can be in (standing, run,
  sprint, crouch, aim) on both models, and assert the fastest bone stays under 12 m/s after landing; put the player
  back in the middle of the floor with `teleport()` between deaths. **Watch out for:** the `AnimationTree` advances on
  real idle time, so the pose at death differs from run to run even in a headless suite and one death passed while one
  in ten blew up; and reviving in place after a run let the player run off the test floor by the thirteenth death,
  so the bones fell for ever and the test reported a 32 m/s "blow-up" that was only the void. Thirty deaths take about
  50 s on the clock (the physics runs at 60 a second), so they are one test of the suite, not one per pose.
  **Seen:** gdstudio #846, 2026-11-09 (`test_deaths_in_every_pose_never_throw_a_bone`).
- **Approach:** Prove a body is a body with numbers from the real run: the deepest overlap of two capsules that are not
  parent and child (`Geometry3D.get_closest_points_between_segments` on each bone's `Shape` axis, radius added)
  under 6 cm, an elbow's or a knee's sideways lean and roll under 25 degrees, a hand moving against the pelvis after a
  death at the top of a jump, and a ray on layer 1 passing through the lying body. Write the test, run it on the old
  code (a throwaway game made from `main`), and keep that log. **Watch out for:** a stress test that passes says no
  bone flew, not that arms stay out of the chest; the old code gave 16.1 and 13.1 cm of overlap, 0.002 m of limb
  motion in the air and a mask of 1 in the same four tests. **Seen:** gdstudio #872, 2026-11-10
  (`test_ragdoll_natural.gd`).
- **Approach:** Test a joint that gives way only in some deaths on a death staged on the physics clock: the test
  fixture `RagdollStage` plays a clip on an `AnimationPlayer` in physics callback mode while it moves the mannequin,
  and goes limp on a chosen tick, so the same death gives the same numbers every run; add a control test that the
  same death with the fix turned off still fails, so the death keeps loading the joint. **Watch out for:** the
  character's `AnimationTree` runs on real time, so a death through `Character.die()` is a different pose each run; and
  editing a script the lab runs while sweeps run in the background breaks their runs (175 errors a run): copy it, or
  wait. **Seen:** gdstudio #940, 2026-11-10 (`test_ragdoll_hinges.gd`); gdstudio #975, 2026-11-10
  (`test_ragdoll_cones.gd`).
- **Approach:** Before a test asserts that a dead body lies still, wait until the ragdoll reports it
  (`is_settled()` with a short `settle_time`, under a cap of ticks), never a fixed number of ticks; and when a case
  fails only in the whole suite, run it once more with its input taken out before blaming the change under test.
  **Watch out for:** `test_a_dead_body_ignores_every_gameplay_input` waited 180 ticks after `Player.die()` and then
  allowed the hips 5 cm in 45 ticks of held keys; alone the hips moved 0.05 mm, in the whole suite on main 0, and in
  the whole suite of a branch that added three suites 50.9 mm, with and without the keys: the fall was another one
  (the pose at death is on the real clock) and was still sliding. Three folder bisects did not reproduce it.
  **Seen:** gdstudio #901, 2026-11-10 (`test_ragdoll.gd` now waits for the sleep).
- **Approach:** Compare two staged deaths (bodies made at the death, from a pool) against the spread of two made the
  same way, and stage each on a tick (`await` one tick before `RagdollStage.setup`). **Watch out for:** two deaths
  with new bodies lie up to 1 cm apart after half a second (Jolt orders its work by the bodies, new each time), so 1 mm
  failed a fresh death against itself; and a stage set up between frames rather than right after a tick started its
  walk a tick off and lay 0.3 m from the others. A joint made in the wrong pose lay 0.46 m off, well past the 3 cm
  allowed. **Seen:** gdstudio #1022, 2026-11-10 (`test_ragdoll_pool.gd`).
- **Approach:** Measure what the skin gets with a modifier last on the skeleton (`BoneLengthProbe`): every bone's
  distance from its parent against the rest's on each drawn frame, the rig's `ik_` bones and the pelvis left out, and
  the fastest simulated body each tick; split a case into parts (run, hit, move, hit again, die) so a failure names
  the part. **Watch out for:** `Skeleton3D.get_bone_global_pose` read from a test shows the clip, not the drawn pose
  (the modifiers' pose is thrown away after the skin update), and a single fresh flinch on a standing body stretched
  2 cm: the rods needed a body moved or revived since its bones were last simulated. **Seen:** gdstudio #1338,
  2026-11-12 (`test_hit_bone_lengths.gd`).
