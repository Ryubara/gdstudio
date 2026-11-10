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
`physical_bones_start_simulation()` hands the skeleton to the bodies.

- **Approach:** Make every bone's `joint_offset` first, then put every body where its joint is to rest (a cone's centre,
  the middle of a hinge's range) in global space, and set the `joint_type` last, bone by bone. **Watch out for:** in
  4.7.2 `PhysicalBone3D` builds its joint in `set_joint_type` (and again on entering the tree when it already has a
  type) from the two bodies' current global transforms and the joint offset; `set_joint_offset` does not rebuild the
  joint, it only moves the body back onto its bone, and the engine forces the joint's origin onto the bone's own
  origin. A joint typed before its neighbours were posed measured its limits from the wrong frame, so the body started
  outside them and was thrown. Source: `scene/3d/physics/physical_bone_3d.cpp`. **Seen:** gdstudio #846, 2026-11-09
  (fix: `PlayerRagdoll._build` sets offsets, poses, then types).
- **Approach:** Free a server joint made between two bones (`PhysicsServer3D.joint_create`) before the bones go: on the
  simulator's `tree_exiting`, and make it again on `tree_entered`. **Watch out for:** a model swap deletes the skeleton
  with the bones in it, and freeing the joint after that crashed the engine (signal 11 in `free_rid`, in the swap
  test). **Seen:** gdstudio #940, 2026-11-10 (`PlayerRagdoll._free_braces`).
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
- **Approach:** Let the bones collide with each other: put the ragdoll's own layer (5) in its `collision_mask` (the
  level and its own, 17), keep the bones off layer 1, and keep each body apart from the one it hangs from with
  `PhysicsServer3D.body_add_collision_exception(a, b)` both ways, once, when the bones are built. **Watch out for:** a
  mask of the level only let limbs through the trunk (13 to 17 cm, in 80 to 90 percent of the frames of a death); the
  "fighting" was a body and its parent overlapping at their joint, and 4.7.2 gives `PhysicalBone3D` no exclusion for
  them on either engine (godot PR 70945 is open). Layer 1 would put the bones in the way of the camera's spring arm,
  the ground probes and the shots (they mask the level only, #875). **Seen:** gdstudio #872, 2026-11-10 (found by the
  maintainer; `test_ragdoll_natural.gd`: non-adjacent capsules overlap under 6 cm).
- **Approach:** Start each bone with its own linear and angular velocity, read from where the animation moved it over
  the last physics frame (sample the 16 bodies' animated poses every tick while alive, then
  `(now - before) / dt` and the axis-angle of `now * before.inverse()` over `dt`, and drop a sample that moved over
  40 m/s: it was a teleport), so a swinging limb keeps swinging when the body goes limp. **Watch out for:** every bone
  given the character's velocity and no spin keeps the pose in free fall, since gravity moves all of them alike: a
  body killed at the top of a jump stayed in its jump pose until it hit the floor, and a clip that holds a pose has no
  velocity to give (see [Going limp](#going-limp)). **Seen:** gdstudio #872, 2026-11-10 (found by the maintainer on the
  #846 ragdoll, `PlayerRagdoll` `pose_velocity`).

## Joint limits {#limits}

<!-- new section: a joint's limits are read in a frame that is not the obvious one, and wrong limits throw the body -->

A ragdoll that dies in a pose its joints do not allow is snapped into range in one step, and the solver turns that
into speed.

- **Approach:** Take the limits from a body's range of motion: elbows -5 to 150 and knees -5 to 140 degrees as hinges,
  the others cones (spine 20 and 12, then 30 and 20; head 45 and 60; shoulder 100 and 60; hip 70 and 35; wrist 60 and
  60; ankle 35 and 15, swing then twist), the same left and right, and push the animated pose inside them when the body
  goes limp (`PlayerRagdoll._clamped_world`; `tools/ragdoll/measure_joints.gd` shows how far the clips go past).
  **Watch out for:** limits widened to hold every clip pose plus 10 degrees let an elbow lean 73 degrees and a knee 39
  in a run's death (hinges: 8, 17); a limit narrower than the death pose throws the body unless the pose is
  clamped. Sources: NASA-STD-3000, Luttgens and Hamilton; Unity, Jolt, Godot. **Seen:**
  gdstudio #846, 2026-11-09; gdstudio #872, 2026-11-10 (`test_ragdoll_natural.gd`: no hinge off its axis by 25).
- **Approach:** Know the sign: a hinge or 6DOF limit angle has the opposite sign to the turn of the child body about the
  axis, on Godot Physics and on Jolt; make the joint at the middle of its range with the same limit each way
  (`PlayerRagdoll` does) and the sign stops mattering, or test it with a probe that places a body at a known angle
  first. **Watch out for:** a limit written with the sign of the turn you measured limits the other way, and the body
  is then outside it from the first step. **Seen:** gdstudio #846, 2026-11-09 (probed on both engines).
- **Approach:** Make a knee or an elbow a `HINGE` joint, not a 6DOF: Z on the bend axis, X along the bone
  (`PlayerRagdoll.hinge_frame()`), `angular_limit_upper` and `lower` in degrees. **Watch out for:** Jolt reads a 6DOF's
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
- **Approach:** Hold elbows and knees with several hinges between the same two bones (`hinge_passes`, 4: the bone's
  own joint and three `PhysicsServer3D.joint_make_hinge` copies with its frames and limits), and judge it over many
  deaths: over 70 lab deaths the mean worst overrun went from 12.9 to 4.1 degrees, the worst from 51 to 17, the
  deaths past the 25 degree slack from 10 to 0. **Watch out for:** a limb the trunk lands on gives way (an elbow
  at 178, or 50 backwards) under Jolt's project-wide 10 velocity and 2 position steps; 4.7.2 gives scripts no
  per-joint step override. Projecting the joint back before each step, heavier forearms, more damping and less
  `relax_gravity` did not help. **Seen:** gdstudio
  #872, 2026-11-10 (four solver settings); gdstudio #940, 2026-11-10 (`test_ragdoll_hinges.gd`; 3 hinges: 5.1 and
  22, 6: 2.4 and 12).

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
  quiet`, and keep only runs whose time before the deaths is the game's usual (0.5 to 1 ms). **Watch out for:** on a
  shared machine two runs in three were noise (30 to 90 ms ticks before any death). Clean runs: one death 1.7 to 2.4 ms
  in the first second, 0.4 to 0.9 after; four 3.1 to 3.4, then 0.7 to 1.3; ten (four limp, six clips by the cap) 4.3,
  then 1.1 to 1.4; asleep by about 10 s. The solver steps of [Joint limits](#limits) made four deaths 5.0 ms (one clean
  run). **Seen:** gdstudio #872, 2026-11-10 (the probe `game_perf.gd` in the task's scratch folder).
- **Approach:** Take a settled body out of the budget: after `settle_time` seconds with every bone asleep the node says
  `settled`, stops counting toward the cap and a game frees the body there; beyond `ragdoll_range` metres from the
  camera a death is the clip. **Watch out for:** how long a body takes to lie still depends on the pose it died in
  (3 to 6 s in the lab, the animation clock being real time), so a test waits up to 15 s and asserts the event, and
  the bones of a body that is never settled (Godot Physics) keep the cap's slot until it gets up. **Seen:**
  gdstudio #872, 2026-11-10.

## Ragdoll in 3D Third Person {#template}

<!-- new section: the template page reached its 50 KB limit, so the template's ragdoll moved here, beside the engine -->

The template's character dies into a ragdoll and gets up again, the usual hybrid: an animated `CharacterBody3D` with
its capsule while alive, a full ragdoll while dead, and a blend back to the animation on getting up.

- **What it is.** `Player.die()` and `revive()` (`is_dead()`, the `died` and `revived` signals, `State.DEAD`). Dying
  stops the animation tree, turns the capsule off, ignores every gameplay input and lets the `Ragdoll` component
  (`PlayerRagdoll`) take the pose on screen, pushed inside the joints' limits, each bone keeping the velocity the
  animation gave it and the limbs let drop for a third of a second (a death in the air goes limp there). When the
  ragdoll declines (over `max_active`, or past `ragdoll_range`) the character plays `ual1/Death01`
  (`Player.died_by_clip`). The camera orbits and follows the hips. A ragdoll below the tuning's `fall_limit` respawns;
  `teleport()` and `respawn()` get a dead character up at once. Getting up stands the body under the hips, facing the
  chest's way, restarts the animation and fades the ragdoll's hold out over `get_up_time`. The library has no get-up
  clip; a game with one plays it with `play_clip()` from `revived`.
- **The inspector.** On `Player`, the group Ragdoll: `ragdoll_body` (the component), `ragdoll` (a live bool: tick it in
  the inspector or the remote inspector to kill, untick to get up) and `ragdoll_key` (Y by default; None turns the key
  off). The key is added to the input action `ragdoll` when the game runs, next to anything a game binds there in the
  Project Settings; it is a testing aid, so a game that ships without it sets None. On `Ragdoll`: `mass` (the whole
  body, shared out by the segment masses of a person), `thickness` (the capsules), `joint_range` (how far the joints
  swing, as a share of a person's range), `hinge_passes` (how many hinges hold each elbow and knee, 4: one lets a limb
  the body lands on fold past its range, [why](#limits)), `linear_damp`, `angular_damp`, `friction`, `bounce`;
  Death and getting up:
  `carry_velocity`, `pose_velocity` (each bone's own velocity, on), `relax_gravity` and `relax_time` (the limbs let
  drop, 12 m/s squared for 0.35 s), `get_up_time`; Cost: `max_active` (4 limp at once in the game), `settle_time` (8 s,
  then `settled` and the cap's slot is free) and `ragdoll_range` (0, any distance); Collision: `collision_layer` (16,
  the ragdoll's own, layer 5) and `collision_mask` (17: the level and its own layer, so limbs rest on the body and on
  each other, never on the bone they hang from; no player capsule, camera wall, ground probe or shot sees a bone: a
  shot passes through and marks what is behind, `test_impact_marks.gd`; hit zones (#876) need their own layer).
  Every one applies live, has a pinned default and a test.
- **Why the bones are generated.** The 16 `PhysicalBone3D`s (no fingers) hang off a `PhysicalBoneSimulator3D` named
  `RagdollBones` under the `Model` slot's skeleton, made from `PlayerRagdoll.BODIES` whenever the rig changes, in the
  editor too (Debug, Visible Collision Shapes), never saved: the glb a swap deletes would hold them. Any rig with these
  65 bones works, both mannequins included. Generated, not the editor's Create Physical Skeleton: a joint's zero is the
  pose it is made in (here a neutral pose, there the T-pose), the swap needs code anyway, and the mannequins differ by
  up to 9 cm ([why](#building)).
- **How the limits are set.** A person's: hinges for elbows and knees (each held by `hinge_passes` hinges), cones for
  the rest, the same both sides ([numbers](#limits)); a cone's centre is the clips' mean direction
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

## Testing a body that the engine throws {#testing}

<!-- new section: a single death proves nothing and the animation clock is real time -->

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
  `Player`'s `AnimationTree` runs on real time, so a death through `Player.die()` is a different pose each run; and
  editing a script the lab runs while sweeps run in the background breaks their runs (175 errors a run): copy it, or
  wait. **Seen:** gdstudio #940, 2026-11-10 (`test_ragdoll_hinges.gd`).
