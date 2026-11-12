# Our own animation set

<!-- new section: the Blender pages said how one clip is keyed; nothing held the plan to replace every library clip
the template plays with our own, the audit behind it, or how a clip is made, checked and reviewed (kit #1150) -->

GDStudio's goal is to depend on no downloaded animation. The Universal Animation Library (Quaternius, CC0) stays in
the template as a base and as stand-ins, and every clip the template plays gets a replacement that is our own work,
made by script. This page is the plan: what the library clips measure today, what good game animation is made of,
the set we will own, and how each clip is made, checked, reviewed and swapped in. It makes no clip; the clips are
the child issues [at the end](#waves). The research behind it, with its sources, is on its own page
([What good game animation is made of](animation-research.md)). The skeleton they are keyed on is the prototype
mannequins'
([The rig](#rig), kit #1149).

The feel to aim for is loose, fluid and natural, with transitions that are animated: a character that reverses
out of a sprint plays a turn of its own instead of snapping round ([the feel as numbers](#feel)).

## The library clips the template plays, measured {#audit}

<!-- new section: nobody had measured the library's clips; a replacement needs the number it has to beat -->

Moved to [The library's clips, measured](library-clip-audit.md#audit) when this page reached 50 KB: every library
clip the template plays, measured by `audit_clips.py`, the number a clip of ours has to beat.

### The gaits {#audit-gaits}

Moved to [The gaits](library-clip-audit.md#audit-gaits).

### Every clip {#audit-clips}

Moved to [Every clip](library-clip-audit.md#audit-clips).

### Limbs inside limbs on the template's bodies {#audit-bodies}

<!-- new section: the audit measured the Quaternius bodies; since kit #1187 the template wears the prototype form
bodies, and a replacement has to beat the library on those -->

Every clip's deepest crossing on the prototype `form` bodies beside the Quaternius pair (kit #1286) is on its own page,
[Clip crossings on the template's bodies](body-crossings.md#library-clips), which this page left when it neared 50 KB.

### What the clips cost {#audit-cost}

Moved to [What the clips cost](library-clip-audit.md#audit-cost).

## The feel, as numbers {#feel}

<!-- new section: "loose and fluid" has to be a set of numbers a build can check, or every review argues taste -->

The targets our clips are built to and measured against, with the same script as the audit. Each variant may move
inside the ranges; a number outside one is a decision written in the variant's notes, not an accident.

| Measure | Walk | Jog | Sprint | Why |
| --- | --- | --- | --- | --- |
| Planted sole speed | the game's 1.7 m/s, within 2 % | 4.0 m/s | 6.5 m/s | the feet hold the floor at the speed the body moves |
| Steps a minute | 125 to 140 | 169 to 187 | 190 to 215 | a person's cadence at that speed ([research](animation-research.md#research-weight); the sprint's lies between two sources) |
| Planted share | 0.57 to 0.62 | 0.27 to 0.36 | 0.20 to 0.27 | a walk always has a foot down; a run flies between steps |
| Pelvis up and down | 30 to 50 mm | 60 to 95 mm | 60 to 100 mm | weight without a bounce. The sourced measure is the centre of mass (77 mm, SD 12, in a run), and the pelvis moves more: ours 79 and 90 mm over 64 and 69 |
| Hips turn, shoulders turn | 6 to 10, 6 to 10 degrees, opposed (about 14 between them) | 8 to 14, 15 to 25 | 10 to 16, 20 to 30 | the trunk winds against the legs; the arms swing in their sockets |
| Pelvis tips toward the swinging leg | 4 to 8 degrees | 5 to 10 | 5 to 10 | the hip drops over the leg that carries nothing |
| Trunk lean at a steady pace | 2 to 5 degrees | 4 to 8 | 6 to 12 | the rest of the lean is acceleration's, added by the lean layer |
| Forearm behind upper arm, hand behind forearm | 1 to 2 frames each | 1 to 2 | 1 to 2 | each part starts after the part it hangs from |
| Chest behind hips, head behind chest | 1 to 3 frames | 1 to 2 | 1 to 2 | the turn travels up the spine |
| Halves of the cycle differ by | 1 to 4 degrees | 1 to 4 | 1 to 4 | alive, but no limp |
| Fingers | curl and open a few degrees with the arm swing | same | same | no dead hands |

What makes it loose is in the joins, more than in the loops:

- **Every change of speed or direction has its own clip** ([the set](#set)): starts, stops, pivots, the sprint
  reversal, turns on the spot, landings into a run.
- **The lean is acceleration.** Starting, stopping and turning lean the body by `atan(a / g)` of the acceleration
  the controller is really applying, as an additive layer over any gait, so a 6 m/s2 start leans 31 degrees for
  the moment it lasts and a steady run stands nearly upright.
- **Nothing stops on one frame.** After a stop the pelvis settles first, then the chest, then the arms and the head,
  each a frame or two later, each overshooting a little.
- **Blends carry momentum.** A new clip starts from the pose and the speed of the old one, not from a mix of two
  poses ([in the tree](#replacing)).

**No mirror poses.** A held pose is never the same on both sides: one foot ahead of the other and turned out
more, one knee lower, the weight more on one leg, the hips and shoulders tilted and turned a little against each
other, the hands at different heights and doing different things. Start a held pose from how a person rests in it
(the library's crouch idle has one heel up, the knees apart at different heights, one forearm on a knee), then
write each side's numbers on their own. A mirrored clip for the other foot is the build's job, not a reason to make
one clip symmetric about its own middle.

- **Approach:** Give every pose and loop its own numbers per side (stance, knee height, weight, hand place and
  task), check a capture from the front and from above for anything lined up, and compare it with the library clip
  it replaces before it goes to review. **Watch out for:** our crouch idle stood with the feet side by side and level
  and the hands placed evenly on both sides, which read as squatting on a toilet beside the library's staggered,
  relaxed crouch; the clip toolkit's style files and solved poses drift toward symmetry unless each side is asked
  for on its own. **Seen:** gdstudio #1160 (PR #1285), 2026-11-11, from the maintainer's review.
- **Approach:** Wind a one-handed blow up with its arm (the hand higher and further back, the collarbone lifted);
  keep the chest and head upright or leaning into it, and measure both against the joined pose on every frame before
  contact, in the build. **Watch out for:** the pistol whip pitched the chest 3 and the head 2 degrees back before
  the swing, and the chest's roll, turned backward by its yaw, added more (3.7 degrees, the head 25 mm back): it read
  as rearing away from the target. **Seen:** gdstudio #1254 (PR #1315), 2026-11-11, from the maintainer's review
  (fix: `LEAN_BACK_LIMIT` in `build_melee.py`).
- **Approach:** Check a one-shot on the every-frame front sheet, not only on the key frames, for limbs that line up on
  the way out and back, and pose each hand from its own per-side table, never from one tuple with a flipped sign.
  **Watch out for:** the melee clips had the guard and the striking fist level at frames 4 and 12 to 14, between keys,
  so the key-frame sheet looked uneven while the move passed through a mirror pose; a flipped tuple mirrors the sides by
  construction. **Seen:** gdstudio #1254, 2026-11-11.
- **Approach:** Before a loop goes to review, run `fluidity.py` (the clips' `own/` folder) on it beside the library
  clip it replaces, on one body: the joints', pelvis's and head's effective harmonic (1 is one smooth wave a cycle)
  and the largest change of a joint's speed in a frame. Fix what it shows in the description (a path with fewer
  waves, an ease, a longer trail), never by filtering keys, and film old, new and library in one row (`OWN_BEFORE`,
  `OWN_ROW`). **Watch out for:** our walk passed every check with its pelvis and head jolting 14 mm fore and aft in
  two frames as each foot left the floor (harmonic 3.7, the library's 1.9): the pelvis was solved from the centre of
  mass on every frame and the foot was flicked off at speed; the import was not the cause. **Seen:** gdstudio
  #1155 (PR #1275), 2026-11-12, the maintainer's review (fix: `pelvis_waves`, `swing_ease`, longer trails).
- **Approach:** Give a loop's sides their own timing as well as their own poses: when each heel comes up, when
  each foot is highest in its swing, when each arm is furthest forward (`roll_out`, `kick_at`, `arm_at` under a
  style's `left` or `right`); keep the footfalls half a cycle apart, since the blend between gaits needs them
  in step. **Watch out for:** the gaits had a pose per side and one clock for both, so the right side replayed
  the left's half cycle with other sizes, and the sharp walk's halves differed by 0.6 degrees, under the 1 to 4
  of the table above; with the right side 0.015 to 0.03 of a cycle late they differ by 1.0 to 2.5. **Seen:**
  gdstudio #1155 (PR #1275), 2026-11-11.

## The set we will own {#set}

<!-- new section: the issue asks for the grouped list, replacements told from new clips, and what depends on the body -->

R replaces a library clip the template plays; N is new (the library has none, or the template plays none). Body: I
plays on any proportions with no new keys; C needs its contacts carried by the `ik_` targets
([other proportions](mannequin-rig.md#proportions)); B needs a pass per body, because limbs touch the body itself.

| Group | Clips | R or N | Body |
| --- | --- | --- | --- |
| Locomotion | `Idle`, `Walk`, `Jog`, `Sprint` | R | I |
| | `Walk_Back`, `Walk_Left`, `Walk_Right`, `Jog_Back`, `Jog_Left`, `Jog_Right` (aiming moves any way) | N | I |
| | `Crouch_Idle`, `Crouch_Walk` | R | I |
| | `Lean_Left`, `Lean_Right`, `Lean_Fwd`, `Lean_Back` (additive poses) | N | I |
| Transitions | `Idle_To_Walk`, `Idle_To_Jog`, `Idle_To_Sprint`, each left and right foot first | N | I |
| | `Walk_Stop`, `Jog_Stop`, `Sprint_Stop`, each on the left and the right foot | N | I |
| | `Jog_Turn_180`, `Sprint_Turn_180`, each planting left and right; `Jog_Turn_90_L/R` | N | I |
| | `Turn_In_Place_90_L/R`, `Turn_In_Place_180_L/R` | N | I |
| | `Stand_To_Crouch`, `Crouch_To_Stand`; `Crouch_To_Prone`, `Prone_To_Crouch` (ours since #1009) | N | I, the prone pair C |
| | `Jump_Start` (standing, running), `Jump_Rise`, `Jump_Apex`, `Jump_Fall`, `Land_Soft`, `Land_Hard`, `Land_To_Jog` | R, the split and the run landing N | I |
| | `Slide_Start_L/R`, `Slide`, `Slide_To_Jog`, `Slide_To_Crouch` | R | C |
| Combat and weapons | per weapon class (pistol, rifle, fists): `Hold`, `Aim` at five pitches, `Shoot`, `Reload`, `Raise`, `Lower`, `Switch` | R, the last three N | C: hands on the weapon's sockets |
| | `Punch_Jab`, `Punch_Cross`, a guard pose, each blow with a step | R | B |
| | `Throw` | N | I |
| Traversal | `Vault_Low`, `Vault_High`, `Vault_Mantle` (kit #1016), a second mantle height, `Push` | R | C |
| | `Prone_Idle`, `Crawl_Fwd` (ours since #1009), `Crawl_Back`, `Crawl_Left`, `Crawl_Right` | N | C: forearms on the floor |
| | `Climb_Ladder`, `Swim_Idle`, `Swim_Fwd` | N | C |
| Reactions | `Hit_Front`, `Hit_Back`, `Hit_Left`, `Hit_Right` (additive), `Knockback`, `Stagger` | R, three sides N | I |
| | `Death_Front`, `Death_Back` (when no ragdoll is allowed), `Get_Up_Front`, `Get_Up_Back` | R, the get-ups N | C |
| | `Interact_Low`, `Interact_Mid`, `Interact_High`, `Pick_Up` | R | C |
| Idles and emotes | three idle breaks (a look round, a stretch, a shift of weight), `Idle_Armed`, `Wave`, `Point`, `Nod`, `Shake_Head` | N | I, B for the stretch |

That is about 110 clips against the 27 played today. Left-and-right pairs are one authored clip and its mirror,
which the build makes ([how a clip is made](#making)); the first wave is the
locomotion rows and the transitions down to the jumps, without the prone pair.

Not clips: the look at a target, the lean's strength, feet on a slope, the hands on a weapon and the recoil's size
are computed in the game from a few poses ([additive and procedural](animation-research.md#research-layers)), and
stay cosmetic, never
networked.

## How a clip is made {#making}

<!-- new section: clips had been solved one build script at a time; a hundred clips need one shared way -->

**By script, always.** A clip is a Python description that a build solves into keys, as the prone and vault clips
are ([Clips solved from targets](animation.md#solved-clips); the vault clips' section of that page, "A clip that
touches the world", lands with kit #1016).
Nothing is keyed by hand in Blender's interface: a hand-keyed clip cannot be rebuilt, compared byte for byte, made
in three variants from one description or rebuilt when the rig's proportions change. A library clip may be read as
a starting pose or a timing reference, never copied into ours.

The first child issue builds the shared toolkit (`templates/3d-third-person/game/assets/animation/own/gdsanim/`),
so a clip's own file holds only what is particular to it:

1. **Controls in the world.** The pelvis, each ankle and wrist, where each knee and elbow points, the chest's and
   the head's turn, each as a curve in the world of a reference floor, with the root moving at the clip's speed
   (a constant for a loop, a curve for a transition) that is taken out again on export. Planted feet are two keys
   at one place.
2. **A contact plan first.** A gait is written as its footfalls: which foot, when it lands, when it leaves, how
   far ahead it lands. Foot paths, the pelvis's height and the trunk's wind are derived from the plan, so cadence,
   planted share and speed are inputs, not things that happen.
3. **Solved, not posed.** Limbs by two-bone solves about the rig's own hinges, the trunk from pitch, yaw and roll,
   the pelvis from the centre of mass where the body leaves the ground or changes speed (segment masses on the
   bones; lean equals acceleration).
4. **Overlap as a pass.** Arms, hands, fingers, the chest and the head take their motion through a damped spring
   from the part they hang from, each with a delay and an overshoot that are the variant's numbers, then are baked
   to keys. Loops run the pass round the cycle until it closes.
5. **Mirrors and families.** The build mirrors a clip for the other foot or side, and makes a family (the stops
   from three gaits) from one description with other numbers.
6. **Variants are parameter sets.** A variant is the same description with another style file (`style_a.json`):
   cadence, bob, wind, lean, delays, overshoot, timing of the poses. Three visions cost three small files.
7. **Checked, then exported.** The build runs [the checks](#checks) before it writes anything, exports at 30
   frames a second with the frozen clip list, and writes `clips.json` beside the glb: per clip its loop flag,
   speed, root travel and turn as curves, contact times per foot, the foot it starts and ends on, and the event
   frames (footsteps).

Clips are **in place** with their travel in `clips.json`, as the rig's root section allows: the template's
controller moves the body (it is predicted and networked), and the tree fits the clip to it. A
game that wants root motion builds the same descriptions with the root keyed.

## The checks a clip passes {#checks}

<!-- new section: a clip of ours has to beat the library's by measure, so the measures and their limits are fixed -->

In the build, on every frame and on every shipped body's skinned mesh, before the export; a failure stops the build.

| Check | Limit |
| --- | --- |
| Loop seam | the last pose is the first to the bit; the change of speed across the seam is no more than the largest in the cycle |
| Floor | a planted sole's lowest vertex within 2 mm of the floor; no vertex more than 5 mm under it on any frame; a crouched clip under its capsule's height (`ceiling`); wider by the difference on a body whose toes rest elsewhere than the reference's ([other proportions](mannequin-rig.md#proportions)) |
| Planted feet | a planted sole wanders at most 5 mm in a contact at the clip's speed; the speed in `clips.json` is the measured one within 2 % |
| Planted hands, forearms, knees | at most 1 mm of drift in the world while planted (as the vault clips, kit #1016) |
| Limbs inside limbs | at most 5 mm on every body (`limb_overlap.py`) |
| Gait | legs half a cycle apart within a frame; each arm with the other side's leg (correlation over 0.7); shoulders against hips; cadence, planted share and bob inside [the feel](#feel)'s ranges or the variant's declared ones |
| Overlap | the forearm, hand, chest and head each trail their parent by the variant's declared frames, within half a frame; no part moves more than 0.5 degrees on the frame a contact lands without its parent moving |
| Weight | in the air the centre of mass is on a free fall's arc within 15 mm; on the ground its lean is the acceleration's within 5 degrees; standing, it is over the feet; with a foot down it drops at no more than 1.05 of gravity |
| Joins | a transition's first and last pose are the poses it joins within 1 mm and half a degree, at the phase `clips.json` names, and its speed there is the joined clip's |
| Travel | a transition's root travel is the distance and the turn `clips.json` declares; a planted foot stays within 5 mm in the world while the root travels |
| Limits | no joint past a person's range ([the ragdoll's limits](../../engines/godot/ragdoll.md#limits)); no elbow or knee bending backward; no change of a joint's speed over a per-joint limit in one frame |
| Cost | [the budget](#budget): bones moved, keys kept, imported bytes |
| The frozen list | the build exports exactly the clips its issue names; a rebuild writes the same bytes |

In Godot (`tests/gameplay/test_own_clips.gd`, on every body): every track finds its bone, loops loop, joins meet
bone by bone, a planted foot stays put while the model moves along the clip's travel curve, and the tree plays the
clip where the library's played. Then the capture from the game's camera.

Passing every check is where review starts, not where it ends: the crawl passed every check with its forearms
wrong ([solved clips](animation.md#solved-clips)). Before keying a move, its motion is researched and written down
with sources (how real limbs do it), and each fault a capture shows becomes a check when a number can say it.

## Three variants and the review sheet {#review}

<!-- new section: the maintainer chooses between variants; what they are shown has to be the same for every clip -->

Every clip type ships in at least three variants, each a vision with its emphasis, for example for the gaits:
**A, grounded** (a person's numbers: low bob, true cadence, small overlap), **B, loose** (the hips lead, long
overlap on arms and head, more wind and lean, a later settle), **C, sharp** (stronger key poses, shorter eases,
fewer in-betweens; reads at a distance and on a small low-polygon body). The agent may propose others; the three
must differ in a number the sheet shows, not only in taste.

The pull request for a clip type carries one **review sheet** per type, made by the toolkit's `review_sheet.py`
(no hand step), attached with `gh pr create --attach`:

1. **A strip image:** one column per variant and a last column for the library clip it replaces (or "none"), every
   column the same frames of the cycle; rows for the side, the front and the top, over a 0.25 m floor grid moving at
   the game's speed, so a foot that slides is seen sliding.
2. **A clip (mp4):** the variants side by side in Godot from the game's camera, on the template's map: the loop for
   five seconds, then the moves that use it (start, turn, stop) driven by the same recorded input for each
   (`tools/capture/own_clips_review.tscn`; `OWN_ONLY=<clip>` films one variant, short enough for a GIF). Film it
   in an imported game (`gds template test 3d-third-person --suite <one> --keep`, then `gds capture frames
   --project game` there), never the worktree's own `game/`; a gait starts `OWN_AHEAD=6` metres into the map,
   since the spawn pad ends 4.6 m ahead and a body that walks off it plays its fall.
3. **The numbers:** the audit's table with one column per variant and the library's, the limits beside them.
4. **Notes:** two lines per variant: the vision, and what was tried and could not be done, with the number that
   shows it. A fault the agent can name in its own capture is fixed before review, not listed
   (learned on the vault clips, kit #1016).
5. **Other bodies:** the same frame of each variant on every shipped body (male, female, chibi).

The pull request carries `S-hold`; the maintainer answers with a letter per clip type, or with a change. The
variants live in `own/review/<type>.glb` under their letters (`Walk_A`) and are not imported by the game; the
chosen one is built again under its plain name into the shipped file by the same pull request once chosen, and the
other style files stay in the repository, so a game picks another vision by rebuilding.

- **Approach:** When a clip declares its own limits, read its numbers on the review sheet against those, and say so in
  the sheet's notes. **Watch out for:** the sheets print the checks' default limits even where a clip declares its own,
  so a 0.42 or a 17.99 (keys kept, key bytes a second, on a 22-frame stride) looks like a failure that passes. **Seen:**
  gdstudio #1160 (PR #1285), 2026-11-11.
- **Approach:** When the pick of a pose other clips are built on changes (a crouch idle that the walk is carried
  like and the stance changes join), rebuild every review file of those types and the shipped file, then run the
  whole game suite: what the hands hold is measured there, not in the build. **Watch out for:** idle B passed every
  build check and, picked, put the held pistol 32 mm into the thigh its hand lay on in two clips
  (`test_pistol_clearance.gd`); the walk's A and C variants, tuned on idle A's carriage, put a forearm 50 to 70 mm
  into a thigh or the pelvis on idle B's, 22 checks at once. **Seen:** gdstudio #1160 (PR #1285), 2026-11-12 (fix:
  the hand held 0.06 m higher, the walk's default carriage fitted to the shipped idle).
- **Approach:** When the pick changes, measure the newly picked variant with `fluidity.py` beside the library's
  clip before `ship`, and give it every fix the review asked of the old pick, with limits of its own. **Watch out
  for:** a fix made after review is written into the picked variant's style section only; the walk's pick moved
  from B to A, and A still had the jolt the review had asked out (pelvis path harmonic 3.69 against the library's
  1.88, the calf's speed changing 36.9 degrees in a frame) with every check green. **Seen:** gdstudio #1155
  (PR #1275), 2026-11-12 (fix: A's walk given `pelvis_waves`, `swing_ease`, no `swing_early` and a 27 degree limit).

## How a chosen clip replaces the library's {#replacing}

<!-- new section: swapping a clip touches the constants, the tree and the web build; the steps are the same each time -->

1. **A library of our own.** The shipped clips are `assets/animation/own/<group>.glb`, imported as animation
   libraries under one name, `gds` (`gds/Walk`), beside `ual1` and `ual2`. Today the library is the one file
   `locomotion.glb`; a second group's file needs the tree's issue to merge them under the name.
2. **The constant moves.** `CharacterClips.WALK` becomes `&"gds/Walk"`; the library's name stays in `ALL` and in a
   `STAND_INS` table, so a game or a test can put the library clip back in the inspector, and a test proves each
   stand-in still plays.
3. **The tree reads `clips.json`.** Blend points sit at the clips' measured speeds; each gait plays at ground speed
   over clip speed; transitions are picked by the gait, the planted foot and the turn asked for, and are played
   along their travel curve against what the controller really did. That is the Godot child issue, not a clip
   issue (done in #1158: `GaitClips` reads the records, and what a transition clip's record needs is on
   [the template's gait settings](../../engines/godot/third-person/clips.md#gait-settings)).
4. **The web build drops what nothing plays.** Once a group is replaced, the libraries' unused clips leave the
   exported game (an import script keeps the clips a list names; the full files stay in the repository for
   stand-ins and study), and the size before and after goes in the pull request.
5. **Docs.** The clip's row on `engines/godot/third-person/clips.md` and the template's inspector list change in
   the same pull request.

- **Approach:** List every clip a build adds to the shipped file in `CharacterClips.ALL` (and its count in
  `test_character_clips.gd`), new clips that replace nothing as well, and run that suite with the clip's own before
  the full one. **Watch out for:** the eleven directions and leans shipped in `locomotion.glb` without a line in
  `ALL`; every suite of their own passed, and only the full run's count (133 clips for 122 listed) showed it.
  **Seen:** gdstudio #1159, 2026-11-12.

## The rig, and other proportions {#rig}

<!-- new section: the clips and the prototype mannequins are made at once and must agree on one skeleton -->

Clips are keyed on the prototype mannequins' skeleton (kit #1149, `mannequin-rig.md`): the library's 65 bones with
its rest orientations, plus twist bones, sockets and four `ik_` targets that no library clip keys. What the plan
takes from it:

- **Only rotations, and positions on `pelvis`, `root` and the `ik_` targets.** No scale keys. Twist bones and
  sockets are never keyed.
- **The reference body** is the one whose `pelvis` rests 0.9166 m up; position keys are in its metres and a body
  with other legs scales them by `motion_scale`.
- **In place**, with the travel in `clips.json` ([how a clip is made](#making)).
- **Our clips key the `ik_` targets** wherever a foot or a hand is planted, with a weight curve in `clips.json`
  that is 1 while it is planted.

What the clips need from the rig, asked of #1149:

- each body's sole points (heel, ball, toe tip, in the foot bone's space) and palm point in `rig_<body>.json`, so
  the floor and contact checks and the foot solve agree on where a sole is;
- segment masses per bone in `rig_<body>.json` for the centre-of-mass checks;
- each body's leg length (hip joint to sole) and arm length, for the speed a clip covers on that body;
- the part of each bone for the overlap check, twist bones with their limb;
- which bones a far level of detail drops, so a clip can ship without their tracks;
- `ball_l/r` hinged flat to the floor at the ball of the foot, so a heel can lift over planted toes.

What carries a clip over to a body with other proportions, and what one clip file cannot do for two bodies, is
[Clips on other proportions](mannequin-rig.md#proportions).

## The budget in the web build {#budget}

<!-- new section: cost counts in the web build; a clip set five times larger must not cost five times more -->

| What | Budget | How |
| --- | --- | --- |
| Tracks a gait clip keys | 22 body bones and the pelvis's position; fingers only where they move | fingers at rest come from one hand-pose clip under the gait; a clip names its bones and the export strips the rest |
| Keys | under 40 % of the frames on a moving bone at half a degree | curves solved at 30 a second, reduced by the build, checked against the full curve on the skinned mesh (1 mm at the hands and feet) |
| Imported size | 6 KB a second of clip, compressed import; the first wave under 250 KB | measured by importing in Godot in the build's test, per file, never per clip: a short fast loop alone is over both this and the key budget (the sprint keeps 51 % of its keys, declared as `keys_kept`; with the gaits, on the prototype rig with its `ik_` targets keyed, `locomotion.glb` is 5.6 KB a second) (`Idle`: 3.9 KB a second, with the importer's optimizer off: [the libraries](../../engines/godot/third-person/clips.md#animation-libraries)) |
| Clips blended at once | four on a character near the camera (two gaits, a transition or an action, one additive); one on a far one | the tree's layers are counted in the Godot issue's bench, in the browser |
| Download | the web build's pack no larger after the first wave than before it | the libraries' unplayed clips leave the export ([replacing](#replacing)) |

## Waves and child issues {#waves}

<!-- new section: the plan files its own work; the order and the reason for it belong with the plan -->

The first wave is locomotion and its transitions, in this order (each issue names its clips and its checks, and
every clip pull request carries `S-hold` for the maintainer's choice of variant):

| Issue | Clips |
| --- | --- |
| #1154 the clip toolkit and the review sheet (done) | `Idle`, three variants, A shipped as `gds/Idle`; the shared build, the checks and their self-test, `review_sheet.py`, the first swap ([the toolkit](animation.md#toolkit)) |
| #1155 the loops (done) | `Walk`, `Jog`, `Sprint`, three variants, `Walk` B and `Jog` and `Sprint` A shipped; one description, `clips/gait.py` ([adding a gait](animation.md#toolkit)) |
| #1156 starts and stops | `Idle_To_Walk`, `Idle_To_Jog`, `Idle_To_Sprint`; `Walk_Stop`, `Jog_Stop`, `Sprint_Stop`; left and right |
| #1157 the reversal, pivots, turns on the spot | `Sprint_Turn_180`, `Jog_Turn_180`, `Jog_Turn_90_L/R`, `Turn_In_Place_90_L/R`, `Turn_In_Place_180_L/R` |
| #1158 the tree (Godot) (done) | speed matching, transitions by code from `clips.json`, the momentum blend, the lean layer, the browser cost ([gaits fitted to the body](../../engines/godot/animation-tree.md#gait-fitting)) |
| #1159 directions and lean (built, A of each in the file until the pick) | `Walk_Back`, `Walk_Left`, `Walk_Right`, `Jog_Back`, `Jog_Left`, `Jog_Right`, in step with `Walk` and `Jog` at their own speeds (1.3, 1.2 and 3.0 m/s); `Lean_Left`, `Lean_Right`, `Lean_Fwd`, `Lean_Back` as poses with their reference `Lean_Ref`; one description each, `clips/directed.py` and `clips/lean.py` ([the toolkit's rows](clip-toolkit.md#toolkit)) |
| #1160 crouch (done) | `Crouch_Idle`, `Crouch_Walk`, `Stand_To_Crouch` (B, chosen), `Crouch_To_Stand` (A, chosen), solved on `form_female`; the prone transitions rebuilt on the new crouch |
| #1161 jumps | `Jump_Start` (standing, running), `Jump_Rise`, `Jump_Apex`, `Jump_Fall`, `Land_Soft`, `Land_Hard`, `Land_To_Jog` |

Later waves, filed when the first has landed and its toolkit has settled: the slide and the curved runs; combat
and weapons (per weapon class, with the hold solver); traversal (the second mantle, the push, the crawl's other
directions, a ladder, swimming); reactions (hits by side, knockback, deaths and get-ups, interactions at three
heights); idles and emotes.

- **Approach:** Measure a library's clips on the skinned mesh, at the speeds the game plays them, before planning
  what replaces them, and read the numbers against what the game does with each clip. **Watch out for:** the
  template's gaits looked acceptable in every capture since it shipped, while the walk's feet covered 56 % of the
  ground and the jog's swept 48 % faster than it; nobody had divided a clip's planted speed by the speed its blend
  point sits at. **Seen:** gdstudio #1150, 2026-11-11 (`audit_clips.py`; the fix is #1158).
