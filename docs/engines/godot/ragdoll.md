# Ragdolls with PhysicalBone3D

<!-- new section: the 3D Third Person ragdoll (gdstudio #846) was the first use of PhysicalBone3D; nothing held how
Godot 4.7.2 builds the joints, which engine to run them on or how to test a body that is thrown by a bad start -->

How `PhysicalBone3D`, `PhysicalBoneSimulator3D` and their joints behave in Godot 4.7.2, found while giving the
Quaternius mannequins a ragdoll (the template's own section is
[Ragdoll in 3D Third Person](third-person-template.md#ragdoll)). Measured headless on Windows with the pinned
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
- **Approach:** Generate the bones from the skeleton each time the model changes (the slot's `rig_changed`), name the
  simulator, give nothing an owner, and rebuild live when an export changes. **Watch out for:** bones saved in a scene
  live inside the model's glb, which a swap deletes, and they go stale as soon as the rig differs; owner-less nodes are
  also never written when the scene is saved in the editor. **Seen:** gdstudio #846, 2026-11-09
  (`test_ragdoll.gd`: 16 bones after a run-time swap; nothing saved when `player.tscn` is opened and saved).
- **Approach:** Read the ragdoll's pose from the `PhysicalBone3D` bodies (`global_position`, `global_basis`,
  `linear_velocity`), never from `Skeleton3D.get_bone_global_pose`. **Watch out for:** the simulator is a skeleton
  modifier, whose pose is applied after the skin update and discarded, so the bone poses of the skeleton show the
  animation while the body is limp and a test that read them found the ragdoll standing. **Seen:** gdstudio #846,
  2026-11-09.

## Joint limits {#limits}

<!-- new section: a joint's limits are read in a frame that is not the obvious one, and wrong limits throw the body -->

A ragdoll that dies in a pose its joints do not allow is snapped into range in one step, and the solver turns that
into speed.

- **Approach:** Measure the limits from the poses the game can die in (every clip the character plays, sampled on every
  model, 10 degrees of margin) instead of from anatomy, and centre a cone on the measured mean direction of the bone.
  **Watch out for:** a limit narrower than a pose the clips reach snaps the body into range when it dies in that
  pose; the shoulder cones of this rig need 125 to 133 degrees of swing from the clips' own mean.
  `tools/ragdoll/measure_joints.gd` prints the numbers for the `PlayerRagdoll.BODIES` table; run it again after
  changing a clip, a frame or a rig. **Seen:** gdstudio #846,
  2026-11-09.
- **Approach:** Know the sign: a hinge or 6DOF limit angle has the opposite sign to the turn of the child body about the
  axis, on Godot Physics and on Jolt, so write a limit as the negative of the range you measured, or test the sign
  with a probe that places a body at a known angle first. **Watch out for:** a limit written with the sign of the
  turn you measured limits the other way, and the body is then outside it from the first step. **Seen:** gdstudio
  #846, 2026-11-09 (probed on both engines).
- **Approach:** Under Jolt, give a knee or an elbow a joint frame with X on the bend axis, Y along the bone and Z
  sideways (`PlayerRagdoll.bend_frame()`), and read its three ranges with `swing_twist()` (twist about X first, then
  swing about Y and Z). **Watch out for:** Jolt reads the 6DOF limits as swing-twist, not as Euler angles: a swing
  inflates at large angles, so a bend of up to 145 degrees must be the twist about X, which is exact through the
  whole range. A shoulder or
  a hip, which swings a long way in every direction, is a cone joint with its centre set to the measured mean.
  **Seen:** gdstudio #846, 2026-11-09 (the knee and elbow ranges are the numbers in `BODIES`).
- **Approach:** Leave about 25 degrees of slack when a test asserts a joint is in its limits at rest. **Watch out
  for:** a limit is a soft stop against a load: an arm pinned under the torso rested up to 17 degrees past its twist
  and side limits on both elbows, run after run, with an 8 degree tolerance failing 4 runs in 6. A joint started
  outside its limits is a different thing and is caught by the speed test below. **Seen:** gdstudio #846, 2026-11-09
  (`LIMIT_SLACK` in `test_ragdoll.gd`).

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
