# Animation

<!-- new section: clip rules lived in rig-sharing.md (export) and gaits.md (locomotion); nothing gave the clip conventions
(frame rate, naming, loops, in place) or how a clip is keyed and checked -->

How GDStudio authors animation clips in Blender, by script, on a shared skeleton ([Rigging](rigging.md)), and gets them
into Godot. Locomotion clips that keep a ground speed are on [Gaits](gaits.md); cleaning and exporting a kit's clips on
[Rig sharing](rig-sharing.md); clips that hold a weapon on [Weapons](weapons.md#hands-on-the-weapon); clips with a
hand or a foot planted on an obstacle under [A clip that touches the world](#contacts). The plan to replace every
library clip the template plays, with the checks and the review every clip of ours goes through, is
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
- **Approach:** Before a keyed clip is shown to anyone, measure on every frame, on every model's skinned mesh, how
  deep each body part is inside another (leg in leg, arm in leg, limb in torso), and make the build fail over a few
  millimetres: the template's `assets/animation/limb_overlap.py` does it for the universal rig (5 mm on the vault
  clips; the library's 43 clips never cross the legs). **Watch out for:** feet and hands keyed as world positions
  put a shin through the other thigh on frames where every contact check passes, and a sheet of small tiles hides
  it. **Seen:** gdstudio #1016, 2026-11-10 (the maintainer found the vault clips' legs passing through each other, 75
  mm deep; fix: the check in `build_vault.py` and `tests/assets/test_vault_clips.gd`, the legs keyed again).

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

## A clip that touches the world {#contacts}

<!-- new section: the page had loops and gaits; nothing said how a clip with a planted hand or foot on an obstacle is
keyed, checked and handed to the code that warps it (the vault clips, kit #1010) -->

A vault, a climb or a push puts a hand or a foot on something that stands still while the body moves. Key such a clip
in the **world of a reference obstacle**, not in place: the controls (the pelvis, each wrist and ankle, where each
elbow and knee points) get world positions, a planted hand is two keys at one place, and the body's root moves forward
at a constant speed that is taken out again on the way to the bones, so the exported clip is in place like every
other. A constant speed keeps a smooth curve the same in both spaces. Write the obstacle's size, the speed, where the
root starts and each contact's time into a file beside the clip: the code that warps the clip to another obstacle
reads them (the template's `assets/animation/vault/build_vault.py` and `vault_clips.json`).

The build checks, on every frame and on the skinned mesh, before it exports: the lowest vertex against the floor, the
deepest vertex inside the obstacle (12 mm allowed, as wide as a wall so the legs must clear the top), the planted
palm's gap to the surface, how far each planted wrist or ankle moves in the world while planted (0.5 mm on the vault
clips), that the body is never jerked to keep a hand in reach, and that no limb is inside another on either mannequin
([Keyframes](#keyframes); 5 mm allowed). It also checks what the body does between its contacts: its centre of mass
on the arc of a free fall while nothing touches it, the planted arm giving and then straight, the landing leg reaching,
an arm that has let go staying under its shoulder's height and gaining speed without a snap, the legs going over
together with no leg astride, folded shut, snapped or held
([the vault clips](../../engines/godot/third-person/clips.md#vault-clips)).

- **Approach:** Where a body leaves the ground, key the pelvis from the centre of mass, not by eye: write its
  height for every frame (free fall between contacts, a curve with a height and speed at each end while a limb
  carries it), measure in each pose how far it is above the pelvis (segment masses on the bones), key the pelvis
  that much lower and repeat until it settles (`Clip.drive` and `Clip.settle`: three or four passes, under 0.2 mm).
  **Watch out for:** a pelvis on a smooth curve is not a body on an arc: legs that reach down and arms that swing
  move the pelvis the other way. **Seen:** gdstudio #1016, 2026-11-11 (both vaults within 0.3 mm of the arc; the
  build fails over 15 mm).
- **Approach:** Take both legs over an obstacle **together and to one side**: roll the hips onto the carrying arm (72
  degrees in `Vault_High`), let the legs trail beside them a hip width apart with the knees near a right angle, and
  key each foot on one smooth path from the pelvis in the world's axes. Measure it (`legs_of` in `build_vault.py`) and
  fail the build on the knees' and ankles' spread in hip widths, the tightest knee, a leg bone under the top, an
  ankle's change of speed in a frame and a leg held still. **Watch out for:** one leg over ahead and the other folded
  behind the hands reads as a squat on the box (knees 3.8 hip widths apart, one knee at 14 degrees, the legs still for
  five frames); feet keyed in the hips' axes jump 0.4 m in a frame as the hips roll and lean. **Seen:** gdstudio
  #1016, 2026-11-11, a maintainer correction (fix: `LEGS_*` in the build).
- **Approach:** A fault you can name in your own capture is fixed before the pull request goes to review; the list of
  weak points holds only what was tried and could not be done, each with the number that shows it and what it would
  take. Measure each weak point you are about to write down: one a check can express becomes a check. **Watch out
  for:** writing down that the body is folded tight over the top and reads as a crouch on the box, sending it for
  review, and getting the same words back as the review's fault a round later; a review that names one fault does not
  pass the others on your list. **Seen:** gdstudio #1016, 2026-11-11 (the squat over the top stood in the weak points
  of the second and third rework and was the fourth review's fault).
- **Approach:** Key an arm that has let go from **its own shoulder in the world's axes** (`Clip.shoulder` in
  `build_vault.py`), let the hand go while the elbow is still bent, and let it gain speed evenly from rest over four
  or five frames until it travels with the body. Fail the build on the wrist's height over its shoulder, its speed in
  the world and against the shoulder, and its change of speed in one frame. **Watch out for:** keyed in the hips' axes
  with the body rolled 56 degrees, the wrist went 0.30 m over the shoulder, above the head, at 11 m/s within two
  frames; a hand held until the arm is at full stretch is torn off by the shoulder; a hand that only rides with the
  body already moves at 3.6 m/s in the world. **Seen:** gdstudio #1016, 2026-11-11, a maintainer correction (fix:
  `Vault_High`'s right hand lets go a frame earlier; `FREE_*` in the build).
- **Approach:** Key the limbs that are in the air in the **hips' own axes** (a point from the pelvis bone, turned
  with the pelvis's keys: `hips()` in `build_vault.py`), the left foot with `left` above 0 and the right below it,
  and keep world positions for what touches the world. Take the leg paths from footage of the real move: over a
  speed vault the body lies near level and the legs go over stacked, one above the other with a gap, knees bent.
  **Watch out for:** with the body rolled 50 degrees, world keys that looked apart put the lower leg's foot above
  the upper leg's, so the legs crossed for eight frames; rolling further to lift the legs drops the lower hip onto
  the obstacle instead. **Seen:** gdstudio #1016, 2026-11-10 (fix: both vaults' legs and free arm keyed in the hips'
  axes; the overlap check reads 0.5 mm at most).
- **Approach:** Tell inside from outside on a part cut from a skinned mesh by closing its cut rims (a fan to each
  rim's middle) and casting rays; measure depth to the skin, and put the lowest spine bone with the pelvis.
  **Watch out for:** a nearest-surface test on the open part read a head beside a raised upper arm as 100 mm inside
  it (a point beyond a limb's open end lies behind its rim), and the female mannequin's hips are skinned to
  `spine_01`, which read the rest pose as 87 mm of chest in thigh. **Seen:** gdstudio #1016, 2026-11-10 (fix:
  `limb_overlap.py` closes the rims; its `--self-test` reads 0 on the rest pose and a crossing on swung legs).

- **Approach:** Let a planted hand pull the pelvis toward itself when the arm cannot reach, smooth that pull over a
  few frames, and keep the planted arm a little bent (0.94 of its length) so the arm takes up what the smoothing
  leaves. **Watch out for:** a pull applied only on the frames that needed it moved the body 30 to 45 mm for single
  frames (a jerk at 24 frames a second), and an arm allowed to its full length was straight, bent 43 degrees and
  straight again on three frames. **Seen:** gdstudio #1010, 2026-11-10 (fix: the smoothed pull and the jerk check in
  `build_vault.py`).
- **Approach:** Check that a planted bone stays in place, not only that it is at the right height. **Watch out
  for:** the first build measured the palm's gap to the top and the skin inside the box, both of which a hand sliding
  along the top passes. **Seen:** gdstudio #1010, 2026-11-10 (fix: the drift check on every planted wrist and ankle).
- **Approach:** Open a hand from the rest pose with the thumb lifted into the palm's plane, and measure the wrist's
  height over a surface on the skinned mesh. **Watch out for:** the universal rig's thumb rests pointing 28 degrees
  down, so a flat palm with rest-pose fingers put the thumb 72 mm into the box; the wrist bone rides 36 mm over a
  surface the female mannequin's palm lies on. **Seen:** gdstudio #1010, 2026-11-10.
- **Approach:** Solve a limb about its own hinge: the upper bone's direction to the elbow and the bend plane's normal
  give its whole rotation, with the hinge axis read from the rest pose (on the universal rig: down for the left
  elbow, up for the right, the body's left for both knees, as `upper x lower`). **Watch out for:** a swing from a base
  pose leaves the twist of that pose in the upper arm, and the elbow then bends about the wrong axis.
  **Seen:** gdstudio #1010, 2026-11-10 (`build_vault.py`, `LIMBS`).
- **Approach:** Take the first and last poses from the loop the clip joins, and key that loop's poses two frames
  outside the clip as well, so the curves leave and arrive at the loop's own speed. Read a library clip onto the rig
  as each bone's rotation relative to its parent on this rig's own bone lengths: that is what Godot plays on a
  mannequin with other proportions. **Watch out for:** the pack's clips sit on the male armature, whose upper arm is
  5 cm longer than the female's, so a pose copied as bone matrices stretches the other model's arms. **Seen:**
  gdstudio #1010, 2026-11-10 (the vaults start on the sprint's left foot strike and end on its right one; the joins
  measure under 20 mm in Godot).

## Clips solved from targets {#solved-clips}

<!-- new section: the page covered clips derived from a kit clip; nothing said how a clip is made from nothing on a rig
(the 3D Third Person prone and crawl clips, #1009) -->

A clip with no clip to start from is solved, frame by frame, from a few targets, by a script that keys the result
(`templates/3d-third-person/game/assets/animation/prone/build_prone_clips.py`: a prone idle, a low crawl and the two
transitions to the Universal Animation Library's crouch, on the Quaternius universal rig; and since kit #1016
`vault/build_vault.py`, the three vault clips). Godot imports the file with
`importer="animation_library"` beside the libraries
([the libraries](../../engines/godot/third-person/clips.md#animation-libraries)).

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
- **A check that names its bodies poses every body the game wears.** The clip checks were made on the Quaternius
  pair; since kit #1286 each poses `CharacterBodies.FEMALE` and `MALE` (the prototype `form` bodies) as well, and
  `limb_overlap.py --brief --json <clips>/bodies_overlap.json` writes each clip's deepest crossing a body with the
  clip file's SHA-256, which the Godot suites read (`tests/fixtures/bodies_overlap.gd`), so a rebuilt file that was not
  measured again fails. `test_limb_overlap.py` runs on the `form` bodies by default (`--model` for others). The
  prototype male's thighs meet by 1.9 mm at rest, which the self-test allows (`REST_MM`, 2.5).
- **A check that reads a clip file measures every key at the file's own rate.** A glb has key times in seconds and
  no frame rate. `limb_overlap.py`'s command line reads the rate from the key times (`clip_rate()`: the lowest of 24,
  25, 30, 48, 50, 60 and 120 at which every key is a whole frame; `--fps` for a file that fits none), sets the scene
  to it before the import and measures each whole frame from the first key to the last: the frames a build measures
  when it calls `measure()` on its baked actions. Its lines name the frame, the clip's range, the rate and the
  seconds (`at frame 26 of 0 to 44 at 30 fps, 0.867 s`), and `test_limb_overlap.py` beside it runs a clip both ways
  at 30 and at 24 and fails on any difference.

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
- **Approach:** A script that reads any clip file takes the frame rate from the file's key times, never a constant,
  and prints the rate and the seconds beside every frame number. **Watch out for:** `limb_overlap.py` set 24 for
  every file, so on the library's 30 frames a second `Roll` it measured 36 of 45 frames, read 62.4 mm for 64.7,
  named frame 21 for frame 26, missed the chest 18.3 mm in a thigh and read the male's hand 4.5 mm in his upper arm
  (under the 5 mm limit) for 10.2. **Seen:** gdstudio #1035, 2026-11-11 (fix: `clip_rate()` and the both-ways test
  `test_limb_overlap.py`).
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
- **Approach:** When the bodies a game wears change, run every clip check on the new bodies the same day, on their
  skinned meshes as well as their bones, and give each failure its own issue with the numbers and a capture.
  **Watch out for:** the template moved to the prototype bodies (kit #1187) with its prone, vault and limb checks
  still posing the Quaternius mannequins; on the new bodies the prone forearms lie 3.3 to 5.5 cm in the floor, the
  vault's planted hand slides 7 to 8 cm and two clips cross 17 to 34 mm, all unseen; the bones-only floor test read
  -3 cm where the skin was -5.5, and counted the new rig's unanimated sockets and IK bones (1.4 m up) until it kept to
  the bones the clip keys. **Seen:** gdstudio #1286, 2026-11-11 (fix: the four-body suites, `bodies_overlap.json`;
  kit #1293, #1294, #1295 for the clips).
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
| Join another clip | `clips/joined.py` (`Joined`: the picked variant of another clip, its first frame as a spec and its solved pose), `Clip.meet` (the exact end poses, with the frames the difference is let go over) and `declared["joins"]`: the pose and the speed a first or last frame must meet |
| Hold or raise a heel | `Footfall.heel` for a foot that stands on its ball for a whole contact (the swing lands on it with the toes already bent), or `ContactPlan.raised(rig, side, frame, heel)` for a heel that moves; name the side in `declared["heel_up"]` so `clips.json`'s `flat` says no frame of it is flat |
| Give each side its own pose | a pair `[left, right]` for every number of a description that a side could own (foot place and turn, heel, knee, each arm's numbers, each hand's curl), read with `AT[side]`; a description never shares one number between two limbs |
| Lay a forearm on a thigh | the arm's `rest` (`{"on": side, "gap": metres, "hand": metres}`): the arm comes down until its forearm's line is `gap` from that thigh's and shin's on every body, measured at each body's own joints; leave that arm out of `Clip.chains` |
| Step a foot inside a transition | two `Footfall`s of that side with the step between them (`clips/stance.py`, `stance_plan`): the plan swings the foot, and `toe_reach` clears the longest toes |
| Take a body down or up | `Clip.stretch` as a function of the frame; the weight check fails a drop over 1.05 of gravity with a foot down; `declared["ceiling"]` holds a crouched clip under its capsule on every body |

**What the build does** (`build.build_clip`, `build.build_file`): solves every frame in the world, runs the overlap
pass, takes the root's travel out (the clip is in place, the travel is a curve in `clips.json`), reduces the keys and
checks the reduced clip against the full one on the body, runs [every check](own-animation.md#checks) on every body's
skinned mesh, and writes nothing when one fails (the last line of a good build is `BUILT <file>`). A clip keys
rotations and the pelvis's place, and the `ik_` targets on a rig that has them. The checks are in `checks.py` with
their limits; `selftest.py` breaks a clip for each one.

**What is proved and what is not.** `Idle` went through all of it. The contact plan, the foot's roll, the travel and
the gait checks are proved by the self-test's plain walk (planted soles within 5 mm at its speed on both mannequins),
which is not a clip anyone has looked at for style. The joins are proved by the stance changes (kit #1160: both ends
0.0 mm and 0.09 degrees from the idles' first poses), which also prove a step inside a transition, and the contact
plan by `Crouch_Walk`; the crouch idle proves `rest` and a foot held on its ball. Mirroring, the placed hand
and the `ik_` targets are written and not yet used by a shipped clip: the first issue that uses each proves it. The
weight check's lean and the free fall's arc are tested on made-up motion only. A body whose legs differ from the
reference body's is reported with `needs_ik` and not held to the floor and planted limits.

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
- **Approach:** Give a gait its own overlap numbers (`overlap_<type>` in the style file), sized to its step: a
  part may trail by a sixth of a step at most, and three bones that share a part's lag each get a third of it, never
  under half a frame. **Watch out for:** the loose style's idle numbers (the forearm 4 frames behind the upper arm,
  which is 4 behind the chest) on a 12-frame step swung each arm with its own side's leg (-0.31 where the check
  asks for 0.7), and trailed the hands 38 to 49 mm into thighs that rose in a stance change; a chest lag of half
  a frame shared by three spine bones is a sixth of a frame each, and the spring ran to infinity.
  **Seen:** gdstudio #1160, 2026-11-11 (fix: `overlap_crouch_walk` and `overlap_stand_to_crouch` in the styles).
- **Approach:** On a deeply bent leg, land the foot flat and let its heel rise from the landing on, and read the
  ankle's bend and the sole's wander on every frame of a first gait before tuning anything else. **Watch out for:**
  a flat sole under a shin that swings 45 degrees slid 6.8 mm in a contact with its joints still, because the
  heel's skin is shared with the shin; the same low pelvis asked 67 to 80 degrees of the ankle and put the
  trailing knee 15 cm off the floor; the male mannequin's toes are 24 mm longer and went 14 mm under the floor in
  a swing cleared for the reference body. **Seen:** gdstudio #1160, 2026-11-11 (fix: `heel_rise`, a quicker
  cadence, `ContactPlan.toe_reach`; the wander is 4.3 to 5.0 mm).
- **Approach:** Time a move that lowers or raises the body from the fall of its centre of mass, and let the check
  refuse what gravity does not allow, before fitting it to a controller's number. **Watch out for:** the
  controller's `crouch_time` is 0.2 s and the crouch lowers the centre of mass 0.45 m, which a free fall takes
  0.30 s over; a 12-frame drop asked 1.33 of gravity and a 12-frame rise had to stop at 1.6 of it. **Seen:**
  gdstudio #1160, 2026-11-11 (fix: `checks.FALL` with its self-test; the shortest drop is 13 frames, the rise 14).
- **Approach:** Check a crouched pose against the capsule on every body before tuning how it looks, and fold the
  spine before the hips. **Watch out for:** the first crouch stood 1.26 m tall in a 1.1 m capsule; tipping the
  pelvis to lower it turned the thigh 143 degrees from its rest (the limit is 125); the male mannequin's head is
  24 mm higher in the same pose, and his longer forearm was 30 mm inside a thigh the female's cleared.
  **Seen:** gdstudio #1160, 2026-11-11 (fix: `declared["ceiling"]`, the pelvis tipped 12 degrees under an 80
  degree fold, the arms hung forward).
- **Approach:** Write a held pose from how a person rests in it, one side at a time: read the clip it replaces
  from the front, the side and above, write down what each foot, knee, hip, shoulder and hand does, and give every
  number a side could own a value per side (a pair in the description and the style files). **Watch out for:** the
  first crouch shared one `heel`, `knee_out`, `arm_swing` and `elbow` between both sides and stood on the standing
  idle's feet so that no foot had to move, so it was a level squat with its hands hung evenly and failed review;
  a variant that changes only timing and amplitude is the same stance three times. **Seen:** gdstudio #1160
  (PR #1285), 2026-11-11, a maintainer correction (fix: pairs in `clips/crouch_idle.py` and `crouch_walk.py`, a
  right foot a step behind on its ball, a forearm on a knee, three stances, a Godot test that the pose is no
  mirror).
- **Approach:** Measure a limb that rests on another on every body's own joints (`Solver._joint_on`), and leave it
  out of the overlap pass. **Watch out for:** a forearm laid 105 mm from the reference body's thigh line was 49 mm
  inside the male mannequin's thigh, whose longer legs put the knee elsewhere; the overlap pass then trailed the
  resting forearm 14 mm into the shin whatever the gap asked for, and the same number came back four builds running
  before the pass was suspected; a hanging arm's `clear` opens the arm on one frame as a thigh passes it, which
  reads as a pop on a landing frame. **Seen:** gdstudio #1160 (PR #1285), 2026-11-11 (fix: `rest` reads each
  body, resting arms are not in `chains`, the walk carries both arms outside the thighs).
- **Approach:** When a foot lands on its ball, bend the toes before the landing and give the stepping foot the
  longest body's toes (`toe_reach`); let a foot that leaves a flat stance roll over its toes for at least three
  frames. **Watch out for:** a step that landed heel-up with straight toes put them 33 mm under the floor on the
  landing frame (50 on the male), and a roll of one frame turned the toe bone 46 degrees in a frame. **Seen:**
  gdstudio #1160 (PR #1285), 2026-11-11 (fix: `Footfall.heel`, the toe's bend in `plan._swing`).
- **Approach:** Film a review clip in a game made from the branch (`gds template test <template> --suite <one
  suite> --keep`, then `gds capture frames --project game` in the kept folder), and count the frames it wrote.
  **Watch out for:** the template's own `game/` folder has no kit addons, so the capture scene did not parse
  (`AudioSettings` not declared) and Movie Maker still wrote 300 frames of an empty scene; an import there
  rewrote three `.exr.import` files. **Seen:** gdstudio #1160, 2026-11-11.

## The clip eval {#eval}

The `clip-walk` eval ([Agent evals](../../studio/agent-evals.md)) animates a walk on a given rig and measures the loop
seam, the in-place hips, the bob, the leg and arm swings and their phases, the arms' hang and the feet on the floor.
