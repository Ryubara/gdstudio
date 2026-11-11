# Animation

<!-- new section: clip rules lived in rig-sharing.md (export) and gaits.md (locomotion); nothing gave the clip conventions
(frame rate, naming, loops, in place) or how a clip is keyed and checked -->

How GDStudio authors animation clips in Blender, by script, on a shared skeleton ([Rigging](rigging.md)), and gets them
into Godot. Locomotion clips that keep a ground speed are on [Gaits](gaits.md); cleaning and exporting a kit's clips on
[Rig sharing](rig-sharing.md); clips that hold a weapon on [Weapons](weapons.md#hands-on-the-weapon). The plan to
replace every library clip the template plays, with the checks and the review every clip of ours goes through, is
[Our own animation set](own-animation.md).

## The conventions {#conventions}

| Rule | Value |
| --- | --- |
| Frame rate | 24 frames a second (the kit's and Deadnight's); glTF stores seconds, so Godot plays the same speed. A clip made to join a pack's library keeps the library's rate (the Universal Animation Library's 30) |
| Root motion | none: clips are in place and the game moves the body |
| Names | bare for whole-body states (`Idle`, `Walk`, `Run`), `<Action>_<Class>` for a held class (`Aim_Rifle`, `Reload_Pistol`), `<State>_<Variant>` for a variant (`Downed_Crawl`); a kit clip keeps its name (`HitReact`, `Death`) |
| Loops and events | not in glTF: a `clips.json` beside the model gives each clip's loop flag and event frames, and Godot adds the method tracks |
| A new gait | keeps the length of the gait it blends with (the zombie's Run is 16 frames, the Soldier's 17) |

Deadnight's naming and file rules are in its `docs/design/animation.md`. Godot's glTF import leaves every clip at
`loop_mode` none, so the loop flag is set on the Godot side ([Crowds](../../engines/godot/crowds.md)).

## Keyframes {#keyframes}

Author a clip from an existing pose of the rig (the kit's `Idle_Shoot` frame 0 for a hold), never from the bare rest
pose, and key every bone the clip touches on its first and last frame. A looping clip's last frame is its first again:
every bone's rotation and location equal on both, so the loop does not pop. Keep quaternion keys' signs continuous
from key to key, or the interpolation spins the long way round, and key location as well as rotation on IK-driven foot
bones ([Rig sharing](rig-sharing.md)).

A bone a clip leaves unkeyed takes the rest pose in Godot, or the pose of the clip played before: bake the static pose
into clips that key few bones (the kit's Idle keys 7 of 43), or key every bone ([Rig sharing](rig-sharing.md)).

A walk or run is measured, not judged by eye: the hips bob twice a cycle, the thighs swing in opposite phase, the arms
swing against the legs (left arm with right leg), and a foot is on the floor in every frame, with nothing under it.
Planted-foot speed gives a gait's ground speed ([Gaits](gaits.md)).

- **Approach:** For each limb, compute its forward swing from the joint positions (the thigh from hip to knee, the
  upper arm from shoulder to elbow) and check the phases against each other after the build: legs opposite, each arm
  with the other side's leg. **Watch out for:** a rotation about X has opposite senses for the swing you mean on a
  limb hanging down and one reached forward, so an arm keyed with the same sign as its own side's leg swung in step
  with it, which looks wrong at once in play and passes a check of amplitude alone. **Seen:** gdstudio #774, 2026-11-07
  (fix: the reference walk's arm signs were flipped; the `clip-walk` eval checks the correlation, not just the size).

## Actions, slots and the NLA {#actions}

In Blender 5 an action plays on an object only through a slot (`animation_data.action_slot = action.slots[0]`), and
glTF roots import in quaternion rotation mode ([Modular kits](modular-kits.md)). Mute NLA tracks before posing by hand
or reading bones, or the tracks override the pose ([Gaits](gaits.md)).

- **Approach:** In Blender 5, set `bpy.context.preferences.edit.keyframe_new_interpolation_type` (and the handle type)
  before a script keys a clip, rather than editing the curves afterwards. **Watch out for:** a layered action has no
  `action.fcurves`; its curves sit in its layers, strips and channel bags, so a script written for Blender 4 that walks
  `action.fcurves` to change interpolation fails. **Seen:** gdstudio #774, 2026-11-07 (the `clip-walk` baseline run).

## Export {#export}

Export each clip as its own NLA track (`export_animation_mode="NLA_TRACKS"`) with `export_force_sampling=True`, and
leave the armature's `pose_position` at POSE: REST froze every clip ([Rig sharing](rig-sharing.md#what-broke)). Give
every build that exports clips a frozen list of them and assert it: a build that exports every action picks up clips
added since ([Build scripts](build-scripts.md#rebuilding)). The exporter writes every bone of every clip; strip the
channels a clip should not drive from the glb's JSON ([Rig sharing](rig-sharing.md#what-broke)).

Check a clip in Godot, not only in Blender: a headless script that plays each clip and asserts bone motion, plus a
capture ([Godot rig sharing](../../engines/godot/rig-sharing.md)).

## Clips solved from targets {#solved-clips}

<!-- new section: the page covered clips derived from a kit clip; nothing said how a clip is made from nothing on a rig
(the 3D Third Person prone and crawl clips, #1009) -->

A clip with no clip to start from is solved, frame by frame, from a few targets, by a script that keys the result
(`templates/3d-third-person/game/assets/animation/prone/build_prone_clips.py`: a prone idle, a low crawl and the two
transitions to the Universal Animation Library's crouch, on the Quaternius universal rig). Godot imports the file with
`importer="animation_library"` beside the libraries
([the libraries](../../engines/godot/third-person/character.md#animation-libraries)).

- **Give each bone a world turn from its rest, not angles on its own axes.** A glTF rig's bone axes are arbitrary, so
  a limb is aimed by mapping two rest directions (along the bone, and the joint's hinge) to where they should point;
  the trunk is a pitch, yaw and roll from the standing rest. The script keeps the rest matrices and the skin as arrays
  and skins the mesh itself (it must agree with Blender's evaluated mesh to a micrometre: check it on a frame of each
  clip), so every frame can be measured without a frame change.
- **Plant what carries weight, in the character's space.** A clip in place moves each planted point back at one speed
  for its share of the cycle and returns it leaving and landing at that speed; the speed is stride over planted time
  and is the number the game needs. A forearm on the floor is planted at the elbow and the hand; a pushing leg at the
  foot, never the knee, which rolls as the leg straightens (7 cm in the crawl). A forearm planted whole cannot turn
  while it is planted, so its angle to the body is chosen once, for the whole pull, from how people place it (the
  crawl's research is in the clips' README: `templates/3d-third-person/game/assets/animation/prone/README.md`).
- **Let the body give where a target leaves no freedom.** An elbow on the floor is exactly one upper arm from the
  shoulder, so the shoulder's height follows from where the elbow is: the crawl's spine pitches and rolls each frame
  by the amount (two unknowns, two elbows, Newton's method) that puts both shoulders at that distance, and the chest
  rides over the planted elbows by itself. The belly rests on the floor the same way: the pelvis's height is moved
  until the lowest vertex of the belly and thighs sinks a few millimetres.
- **Join another clip on its exact pose.** A transition reads the pose it joins (frame 0 of the library's crouch idle:
  joint places, trunk turns, the feet's world turns), keys its targets from those values, and mixes the solved limbs
  with that pose's own in local space over the first frames, so frame 0 is the pose to the bit while the planted foot
  stays put.
- **Export the armature with a one-triangle mesh skinned to the root.** Godot makes a `Skeleton3D` from a skin, and
  the track paths (`Armature/Skeleton3D:<bone>`) come from it; without a skinned mesh the bones import as plain nodes.
  The stand-in keeps the mannequin's mesh out of the file (0.66 MB for four clips).
- **The build's checks** are the clip's own: loops close, planted joints stay within a millimetre at the clip's speed,
  the lowest vertex by body part, a transition's first and last pose against the poses it joins, and the frozen clip
  list. A rebuild writes the same bytes, so `cmp` proves a script change did not move a clip.

- **Approach:** After the first build, read the lowest vertex of each body part (hand, forearm, foot, toes, knee,
  shoulder) on every frame, and render the pose large from the side, the top and a quarter view before tuning any
  number. **Watch out for:** a cross product in the wrong order pointed the kneecap up, so the lying feet were upside
  down and 3.5 cm under the floor; the rest thumb points 47 degrees under the palm and curled fingers reach 6 cm under
  a hand laid flat; a foot on its toes needs the toe bone bent at the floor; a knee bent under a low pelvis goes
  through the floor unless it points out to the side. One number for the whole mesh said only that something was
  under. **Seen:** gdstudio #1009, 2026-11-10 (fix: the per-part report, the thumb laid out, the toes bent at the
  floor, bent knees sent sideways).
- **Approach:** Set the scene's frame rate to the clip's before importing a glb of clips, in the build and in every
  script that renders it. **Watch out for:** Blender imports keys at seconds times the scene's rate, so a 30 frames a
  second library read into a new scene (24) had its 46-frame clip on frames 0 to 37 and every sampled frame fell
  between two keys. **Seen:** gdstudio #1009, 2026-11-10 (fix: `scene.render.fps = 30` before the import).
- **Approach:** Test a clip file of your own in Godot on both mannequins: every track finds its bone, a loop's last
  pose is its first, a transition's first and last pose equal the poses it joins (bone by bone, in the model's space),
  and a planted joint stays put while the model moves at the clip's speed. **Watch out for:** the importer keeps 57 of
  the file's 195 channels (it drops the scale tracks and the positions that never move), an `Array[StringName]` sorts
  by something other than the alphabet (compare `String`s), and a clip solved on the female mannequin rolls a planted
  elbow up to 3 cm on the male, whose upper arms are 5 cm longer, so the limits are per model. **Seen:** gdstudio
  #1009, 2026-11-10 (`tests/gameplay/test_prone_clips.gd`).
- **Approach:** Before keying a gait or a move the library has no clip of, research how real limbs do it, not only
  its speed: a manual or coaching text, a motion study and a dozen photographs. Write down, with sources, each
  limb's angle to the body, where hands and feet land, which limbs move together and each joint's path; build to
  those numbers and test them in Godot. **Watch out for:** the first crawl was researched for its speed and limb
  pairing only, so both forearms pointed almost straight ahead, shoulder-width apart, where every photograph of a
  crawling soldier has the forearms 45 to 80 degrees inward and the hands under the chin; every check passed and
  the pose was still wrong. **Seen:** gdstudio #1020, 2026-11-10, a maintainer correction (fix: the research table
  in the clips' README, forearms 40 degrees inward, a hand planting 0.29 m ahead of the other, and a Godot test).
- **Approach:** Rest a limb that carries weight for long the way a person can keep it up: a forearm lies rolled about
  45 degrees onto its outer edge (the palm down and in), the hand a fist in line with it, the thumb outside. Palm
  down is the end of the forearm's twist and bends the wrist back. Set the joint heights from the forearm's and
  the fist's lowest vertex and look at every finger in close-ups. **Watch out for:** the reworked crawl still lay on
  flat palms; a fist holds the wrist 6.6 cm up (a flat hand 4.5) and is 8 cm tall palm down, so a hand closing in a
  transition lifts first (37 mm under otherwise); lower elbows sink the chest until the collarbones push down 11
  degrees; one fist plays on both mannequins, so its curls sit between their hands. **Seen:** gdstudio #1020,
  2026-11-11, a maintainer correction (fix: `FOREARM_ROLL`, `FIST_CURL`, `fist_numbers`, a Godot test).
- **Approach:** Measure every model that plays a clip on its own skinned mesh, part by part against the floor, in
  the build; read a pose helper's effect off the bone it should move; tell inside from outside with rays, not only
  the nearest face's normal. **Watch out for:** the clips were held on the male by bone heights only, so nobody saw
  his forearms 4.6 cm and his thighs 3 cm under the floor (one clip file cannot rest both bodies); the finger curl
  never ran (`n[:-4]` of `index_01_l` is `index_`); a nearest-normal test called a finger 90 mm inside the thumb's
  open base. **Seen:** gdstudio #1020, 2026-11-11 (fix: `floor_mm` and `fist_mm` in the build's report; the male's
  own clip set is a follow-up).
- **Approach:** Run the limb overlap check on both mannequins inside the build, and when a transition crosses, move
  the keys of the limb that can leave first in time before changing its path. **Watch out for:** the transitions
  passed their own checks with the chest 25 to 50 mm in the front thigh going down and the left arm 51 mm in the
  thigh coming up; opening the knee to clear the chest put it into the male's longer arm (35 mm), and a pole
  target is only a hint; wider elbows in the crawl sank the chest 2.2 cm into the floor. **Seen:** gdstudio #1020,
  2026-11-10 (fix: the hands go up and over the knee by frame 3 and the knee opens from frame 2 to 6; coming up
  the left hand waits outside the knee until frame 19; at most 2.6 mm on both mannequins, the build fails over 5).
- **Approach:** When one clip's target moves, rebuild and read every clip that joins it. **Watch out for:** moving
  the prone idle's hands 2.5 cm forward put the going-down clip's hands 8 mm out of reach on the frame they land,
  since the transition takes its hand places from the idle. **Seen:** gdstudio #1009, 2026-11-10 (the build's miss
  check caught it; the dive was moved forward).
- **Approach:** Judge two hands that touch with both measures and know how they differ: `limb_overlap.py` (Blender,
  every pair of parts both ways, depth to the other part's nearest skin) and the game's `HandContact.measure(side,
  true)` (the hand of `side` against the weapon and the other hand, one way only); measure each side when the hands
  meet. **Watch out for:** on the same pose the limb check read touching hands 3 to 4 mm deeper than `HandContact`,
  and `measure("l", true)` reads the left hand into the right, never the right into the left. **Seen:** gdstudio
  #1081 (PR #1103), 2026-11-11.

## The clip toolkit {#toolkit}

<!-- new section: clips had been solved one build script at a time (prone, vault); the toolkit every clip of our own
is built with had no page (kit #1154) -->

GDStudio's own clips ([the plan](own-animation.md)) are made with one toolkit,
`templates/3d-third-person/game/assets/animation/own/gdsanim/`, so a clip's own file holds only what is particular to
it. It is numpy only and reads and writes glb files itself (no Blender round trip, the same bytes on a rebuild);
Blender is used for the review sheet's pictures and for limbs inside limbs. Axes are glTF's and Godot's (+Y up, +Z the
way the character faces, +X its left), angles are degrees, time is frames at 30 a second.

```sh
uv run --with numpy python -B build_own.py self-test                      every check against a clip built to break it
uv run --with numpy python -B build_own.py review <type> --blender <b>    the variants, into review/<type>.glb
uv run --with numpy python -B build_own.py ship <group> --blender <b>     the shipped file, from picks.json
uv run --with numpy --with pillow python -B review_sheet.py <type> --blender <b> --out <folder>
```

**A new clip type** is three things:

1. **A description**, `clips/<type>.py`: a `DEFAULTS` table (every number a style may set, with what it means) and
   `describe(rig, style, name)`, which returns a `gdsanim.build.Clip`: the clip's frames, its contact plan, a function
   from a frame to the solver's spec, the overlap pass's bones, its kind (`stand`, `gait`, `transition`, `action`) and
   what it declares for the checks (`lags`, `ranges`, `joins`, `plants`, `distance`, `turn`).
2. **A section in each style file**, `styles/style_<letter>.json`: that variant's numbers for the type, and its two
   lines for the review sheet under `notes`. A number the description does not declare fails the build.
3. **A line in `build_own.py`**: the type in `TYPES`, its name in its group's frozen list in `GROUPS`, and its letter
   in `picks.json` once chosen.

| To do this | Use |
| --- | --- |
| Say where the feet are | `plan.ContactPlan` of `Footfall`s (which foot, the frames it lands and leaves, where the ball of the foot stands in the world, heel strike and toe-off) over a `Travel` (the root's path; `Travel.steady(speed)` for a loop). `plan.standing()` for both feet down. A leg the spec leaves out is the plan's. Contact times, speed, footstep events and the start and end foot of `clips.json` come from the plan |
| Pose the body | the spec of `solve.py`: the pelvis's place and turn, the chest's and the head's turn, a hanging arm (`swing`, `out`, `bend`, `pronate`, `clear`) or a placed hand (`wrist_at`, `pole`, `palm`), finger curls. Turns are pitch, yaw and lean from the standing rest, never a bone's own axes |
| Put the weight somewhere | `Clip.balance` (the floor point the centre of mass is over; `weight.support_point` for a share between the feet) and `Clip.stretch` (how straight the straighter leg is): the pelvis is solved from them. `weight.free_fall` and `weight.lean_for` for the air and for a change of speed |
| Make parts trail | `Clip.chains` from the style's `overlap` numbers (`overlap.chains_from`): each bone follows the part it hangs from with a lag in frames and an overshoot, closed round a loop. `overlap.follow` does the same to one number |
| Make the other side | `build.mirrored(rig, built, name, half_cycle=...)` |
| Join another clip | `declared["joins"]`: the pose and the speed a first or last frame must meet |

**What the build does** (`build.build_clip`, `build.build_file`): solves every frame in the world, runs the overlap
pass, takes the root's travel out (the clip is in place, the travel is a curve in `clips.json`), reduces the keys and
checks the reduced clip against the full one on the body, runs [every check](own-animation.md#checks) on every body's
skinned mesh, and writes nothing when one fails (the last line of a good build is `BUILT <file>`). A clip keys
rotations and the pelvis's place, and the `ik_` targets on a rig that has them. The checks are in `checks.py` with
their limits; `selftest.py` breaks a clip for each one.

**What is proved and what is not.** `Idle` went through all of it. The contact plan, the foot's roll, the travel and
the gait checks are proved by the self-test's plain walk (planted soles within 5 mm at its speed on both mannequins),
which is not a clip anyone has looked at for style. Mirroring, the placed hand, the joins and the `ik_` targets are
written and not yet used by a shipped clip: the first issue that uses each proves it. The weight check's lean and the
free fall's arc are tested on made-up motion only. A body whose legs differ from the reference body's is reported with
`needs_ik` and not held to the floor and planted limits.

- **Approach:** Give a description the body's weight and contacts, not its pose: the share of weight on each foot,
  how straight the carrying leg is, how far a hand keeps from the thigh, and let the solver find the pelvis and the
  arm. **Watch out for:** the first idle gave the pelvis a height and the arms an angle from the body; a deeper shift
  put an ankle 4 mm out of reach, and every variant had its curled fingers 27 to 56 mm inside a thigh (the fault the
  library's idle has), because the pelvis travels 8 to 14 cm toward the hand, the female mannequin's hip is 100 mm
  wide of its joint, curled fingertips reach 45 mm inward of their knuckles and the rest pose's thumb points 47
  degrees under the palm. **Seen:** gdstudio #1154, 2026-11-11 (fix: `Clip.stretch`, the arm's `clear`, measured to
  the fingertips on every body, and `thumb_out`).
- **Approach:** Turn a planted foot whose heel rises about the toes' hinge (the `ball` joint), and set a heel that
  lands down by the lowest of its blended skin; read each foot's lowest vertex on every frame of a first gait.
  **Watch out for:** turning about the floor point under the hinge moved the hinge itself, so the toes sank 3 mm and
  slid 9 mm at toe-off; a heel point taken from the sole's bounding box is not on the rounded heel (10 mm off the
  floor), and the heel's skin is shared with the shin, so a rigid guess was 2 to 11 mm wrong; toes left hanging
  under a pitched foot went 12 mm into the floor early in the swing. **Seen:** gdstudio #1154, 2026-11-11 (the
  self-test's walk; fix: `plan._state` and the lift in `plan._swing`).
- **Approach:** Measure the angle between two stored quaternions from the chord between them
  (`4 asin(|a - b| / 2)`), and index a `[frame, bone, 4, 4]` array in two steps (`world[:, bones][:, :, :3, 3]`).
  **Watch out for:** the arc cosine of the dot product loses a twentieth of a degree once keys have been rounded
  to 32-bit, so a reducer at any finer tolerance dropped keys at random and the reduced clip never got within
  0.3 mm; `world[:, bones, :3, 3]` puts the bones first, not the frames, so a check read the hands' error as the
  planted feet's. **Seen:** gdstudio #1154, 2026-11-11 (`maths.quat_angle`, `checks.check_reduction`).
- **Approach:** Prove each check with a clip built to break it before trusting a build that passes
  (`build_own.py self-test`), and break it the way the fault would really happen. **Watch out for:** a pop was first
  measured as the mean of a frame's turn in and out, which a one-frame jump cancels (3 degrees in, 3 back), and then
  as their difference alone, which fails every swing where it reverses; a test body moved sideways took its feet
  along, so the centre of mass was never outside them. **Seen:** gdstudio #1154, 2026-11-11 (fix: `checks._kick`
  compares a frame with the frames beside it; the weight case lifts a foot out of the plan).
- **Approach:** Read a frame number a Blender tool reports at the frame rate that tool set, and look at a named
  fault from the side it is on. **Watch out for:** `limb_overlap.py` sets the scene to 24 frames a second, so its
  "frame 115" of a 30 a second clip is frame 144; close-ups of frame 115 from the front showed a clean hand, and
  the crossing (curled fingers in the thigh) was found only once the pose it measured was printed. **Seen:**
  gdstudio #1154, 2026-11-11.

## The clip eval {#eval}

The `clip-walk` eval ([Agent evals](../../studio/agent-evals.md)) animates a walk on a given rig and measures the loop
seam, the in-place hips, the bob, the leg and arm swings and their phases, the arms' hang and the feet on the floor.
