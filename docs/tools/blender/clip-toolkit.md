# The clip toolkit

<!-- new section: moved from animation.md#toolkit when a merge of main put that page at 57 KB (kit #1275) -->

The toolkit every clip of our own is built with, and what building the idle and the gaits taught. The conventions,
the keyframes and the export of any clip are on [Animation](animation.md).

## The toolkit {#toolkit}

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
uv run --with numpy python -B fluidity.py --bones                         the shipped gaits beside the library's
```

`fluidity.py` reads how smooth a loop is ([the feel](own-animation.md#feel)): `--pair <file>:<Clip>=ual1/<Clip>`
for a review file's variant. A gait's `pelvis_waves` is how many waves a cycle the pelvis may answer the limbs
with (0: it is moved every frame until the centre of mass is exactly on its path, which passes a foot's flick up to
the head), and `swing_ease` 1 with `swing_early` 0 makes a foot leave the floor from rest.

**A new clip type** is three things:

1. **A description**, `clips/<type>.py`: a `DEFAULTS` table (every number a style may set, with what it means) and
   `describe(rig, style, name)`, which returns a `gdsanim.build.Clip`: the clip's frames, its contact plan, a function
   from a frame to the solver's spec, the overlap pass's bones, its kind (`stand`, `gait`, `transition`, `action`) and
   what it declares for the checks (`lags`, `ranges`, `joins`, `plants`, `distance`, `turn`).
2. **A section in each style file**, `styles/style_<letter>.json`: that variant's numbers for the type, and its two
   lines for the review sheet under `notes`. A number the description does not declare fails the build.
3. **A line in `build_own.py`**: the type in `TYPES`, its name in its group's frozen list in `GROUPS`, and its letter
   in `picks.json` once chosen.

**A new gait** is a table of numbers, not a description: `clips/gait.py` is one description for `walk`, `jog` and
`sprint` (kit #1155), and a strafe, a backpedal or a crouched walk starts as a fourth table in it. A gait gives the
toolkit, in this order: the footfalls (the left foot lands at frame 0, the right at half the cycle; a contact is a
whole number of frames), the speed (the game's), the centre of mass as a point in space on every frame
(`weight.settle` takes the point; a free fall between a run's contacts), its own swing path (`ContactPlan.state()`
gives the planted foot, the description places the swinging one), then the trunk, the arms and the overlap numbers.
Each side has its own numbers (`left` and `right` in a style's section, for the foot's width and turn, the arm, the
hand; the `_rest` numbers for a turn or a tilt the pelvis, the chest and the head keep): a gait whose sides share
every number reads as a machine ([no mirror poses](own-animation.md#feel)). The pelvis and the knees are what those
leave, never keyed. `Gait._set_down` then corrects each frame's ankle on every
body's skin. The ranges a gait's measured cadence, planted share and bob are held to are in `GAITS`, from
[the feel](own-animation.md#feel). `review <type>` writes nothing unless every variant passes, so try one variant's
numbers with a script of your own in scratch that calls `describe` and `build.build_clip` and prints the checks.

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

**What is proved and what is not.** `Idle`, `Walk`, `Jog` and `Sprint` went through all of it: the contact plan, the
foot's roll, the travel, the gait checks and the free fall's arc (0 to 1.1 mm off it in the runs). Mirroring, the
placed hand, the joins and the `ik_` targets are
written and not yet used by a shipped clip: the first issue that uses each proves it. The weight check's lean is
tested on made-up motion only. A body whose legs differ from the reference body's is reported with
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
- **Approach:** Read a frame number a Blender tool reports at the frame rate that tool set, look at a named fault
  from the side it is on, and have a build that hands a file with reduced keys to a tool name the rate
  (`build_own.py` passes `--fps`). **Watch out for:** `limb_overlap.py` set the scene to 24 frames a second until
  kit #1035, so its "frame 115" of a 30 a second clip was frame 144; close-ups of frame 115 from the front showed
  a clean hand, and the crossing (curled fingers in the thigh) was found only once the pose it measured was
  printed. Sparse keys can be whole frames at a lower rate too, so a rate guessed from them can be wrong.
  **Seen:** gdstudio #1154, 2026-11-11 (measured again at 30 after #1035: our idles still 0, 1.3 and 0 mm; the
  library's walk 11 to 12 mm, `Death01` 41 mm on the male, `ClimbUp_1m` 23 to 26 mm).
- **Approach:** Write a direction that turns with a joint out as sines and cosines of the joint's angle
  (`cos(bend) * bend_dir - sin(bend) * aim`), and render the hands of a first build of any pose with an elbow bent
  past a right angle. **Watch out for:** the hanging arm's thumb direction was made square to the forearm from the
  bend direction (`square_to(bend_dir, aim_f)`), which points the other way once the elbow passes 90 degrees: the
  first jog's hands were turned 110 degrees, and the idle and the walk never bend that far. **Seen:** gdstudio
  #1155, 2026-11-11 (`solve.py`; the idle rebuilds to the same bytes).
- **Approach:** Set a foot down on every shipped body's own skin, frame by frame: measure each body's lowest sole
  vertex at the planned ankle and correct the ankle until the lowest of them all is on the floor while planted and
  clear of it in the swing. **Watch out for:** a heel point estimated on one body was 4.6 mm under the floor on the
  female at an 18 degree heel strike, and the male's toes, 24 mm longer, went 8.8 mm under in the swing; one clip
  plays on both, and neither fault showed on the body the path was tuned on. **Seen:** gdstudio #1155, 2026-11-11
  (`Gait._sole_gaps`, `Gait._set_down`).
- **Approach:** Land a run's foot still moving back at a share of the ground's speed (`land_speed`, half) and
  start its swing a frame before it leaves (`swing_early`); a walk's foot may rest over the floor first.
  **Watch out for:** a run's foot brought to rest in the air before it lands has to reach past its landing place
  while the body goes on under it (11 cm in the jog, 20 in the sprint), and the furthest-reaching leg sets the
  height of the whole cycle, so the hips sank; a swing starting from rest stretched the trailing leg on its first
  frame. **Seen:** gdstudio #1155, 2026-11-11.
- **Approach:** Read `audit_clips.py`'s planted numbers knowing it calls a foot planted while its sole is within
  25 mm of the floor: give contacts whole frames, and carry a swinging foot above that near both ends
  (`carry_height`, `leave_frames`, `land_frames`). **Watch out for:** a foot swinging low read as planted, so the
  audit gave 57 to 460 mm of slide and a wrong planted share for clips whose own build held the sole within 5 mm;
  fractional contact frames did the same at each end. **Seen:** gdstudio #1155, 2026-11-11.
- **Approach:** Measure a planted foot's wander only on skin weighted 95 % or more to the foot and the toes, and
  only on the patch that is on the floor on both frames compared (`checks.Played.firm`, `FIRM`). **Watch out
  for:** the heel's skin is shared with the shin, which swings 25 degrees a frame over a planted foot in a run,
  and a rising heel lifts its own skin: the check read 9 mm of slide in the jog while no bone of the foot moved.
  The audit still follows every sole vertex (7 mm for the same clip), and the sheet prints both. **Seen:**
  gdstudio #1155, 2026-11-11 (the self-test still breaks the check with a real slide).
- **Approach:** At a gait's pace treat the overlap spring as a filter on a sine: declare the lag the spring gives
  at that cycle length, lead and enlarge the parent's swing by what the spring will take (`_through_spring` in
  `gait.py`), keep the overshoot at 0.2 or under, and pass a chest's lag on to its three bones once, not three
  times (`chest_late`). **Watch out for:** an overshoot of 0.25 to 0.3 that settles nicely in an idle rings when
  driven near its own frequency: the elbow went 21 degrees past straight and the hand turned 100 to 146 degrees
  from the forearm, and the measured lag was not the style's number. **Seen:** gdstudio #1155, 2026-11-11.
- **Approach:** Send a swinging arm out past the hip on its way back and less inward across the chest
  (`arm_out_back`, `arm_clear` 0.19), and run limbs inside limbs on both bodies after every change to the trunk's
  turn. **Watch out for:** an arm swung straight fore and aft put the hand up to 110 mm into the hip and the
  chest once the hips and the shoulders wound against each other; the male's wider chest and the female's wider
  hip need opposite room. A side's own `arm_out` moved the measured forearm lag from 1.2 to 1.1 frames, under what the
  variant declares: rebuild every variant after a per-side number. **Seen:** gdstudio #1155, 2026-11-11 (0 mm on
  both bodies).
- **Approach:** After any change to the arm that carries a weapon (the right), run the template's
  `test_pistol_clearance.gd` and `tools/carry/measure_clearance.gd`: the gait's arm carries the pistol under the
  grip pose, and the limbs check knows nothing of it. **Watch out for:** a right arm held tighter than the left
  (a deeper elbow, less swing) put the carried pistol 7 mm into the female's flank for one frame of the jog and
  4 mm into her chest at the sprint's seam, between the test's eight samples of the first and on one of the
  second; three more degrees of `arm_out` moved it 1 mm, while a shallower elbow, `arm_out_back` and less
  `arm_twist` cleared it by 50 mm. The test samples 24 times now. **Seen:** gdstudio #1155, 2026-11-11.
- **Approach:** Solve a clip on the body the player wears and check it on the other bodies the game wears
  (`build_own.py`: `REFERENCE` is `form_female`, `BODIES` adds `form_male`); when the template's bodies change,
  rebuild every review file and the shipped file on them the same day and read the floor, the planted sole and
  the key bytes before the limbs. **Watch out for:** the gaits and the idle were solved on the Quaternius pair
  while the template moved to the prototype bodies. Solved again, six of nine variants failed: the rig's four
  `ik_` targets are keyed (a fifth more key bytes: each gait declares `kb_a_second`), longer feet put a knee at
  140.6 degrees and a calf 0.6 degrees a frame over its limit, and the self-test's plain walk left the floor
  band at a 38 degree heel. **Seen:** gdstudio #1155 (PR #1275), 2026-11-11.
- **Approach:** Treat the frame a contact ends on as planted: compare a frame with `duty * frames` through a small
  margin (`EDGE` in `clips/gait.py`), and read each sole's height on every frame of a contact after a body
  changes. **Watch out for:** `15 / 26 * 26` is a float just under 15, so the walk's last contact frame was the
  swing's first and its sole was never set down: 5.0 mm over the floor on the prototype bodies, whose sole turns
  up ahead of the ball of the foot (the toes' own skin is 7 mm up, so a foot rolled onto its toes stands on the
  ring of skin under the joint, which rises with the heel); the Quaternius sole kept the same frame inside the
  2 mm band, and the loose walk, whose contact ends between frames, passed. **Seen:** gdstudio #1155 (PR #1275),
  2026-11-11.
