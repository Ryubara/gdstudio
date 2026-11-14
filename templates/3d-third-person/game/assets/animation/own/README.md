# GDStudio's own clips

Clips made by GDStudio, by script, that replace the Universal Animation Library's one clip type at a time (the plan:
the kit's `docs/tools/blender/own-animation.md`; how to use the toolkit: `docs/tools/blender/animation.md#toolkit`).
Nothing here is copied from a library clip or from another game: a clip is a description that `gdsanim/` solves.

| File | What it is |
| --- | --- |
| `bodies_overlap.json` | The shipped file's deepest limb crossing per clip and body, with the file's SHA-256, the hash of the measure's code and each body file's (`../measure_hash.py`); the build writes it and the Godot suite reads it, so a file that was rebuilt and not measured fails, and so does a report made by another `../limb_overlap.py` or on another body. |
| `locomotion.glb`, `locomotion.json` | The shipped clips and what the game needs to know of each (`clips.json` of the plan): loop, length, speed, travel and turn curves, contact times per foot, the foot it starts and ends on, events. Godot imports the glb as an `AnimationLibrary`; the player's `AnimationPlayer` holds it as `gds`, so the clip is `gds/Idle`. |
| `picks.json` | Which variant each shipped clip is built from (`"Idle": "A"`). |
| `clips/<type>.py` | A clip type's description, with every number a style may set and what it means. |
| `clips/directed.py`, `clips/lean.py` | The gaits that do not go the way the body faces (one description, a table a clip), and the lean poses with their reference. |
| `clips/joined.py` | What a clip reads of the shipped clips it joins: their numbers, their first frame, their solved first pose. |
| `styles/style_<letter>.json` | A variant: a vision, its numbers per clip type and its overlap numbers. |
| `review/<type>.glb`, `.json` | Every variant of a type under its letter (`Idle_A`), for review; the game does not import this folder. |
| `gdsanim/` | The toolkit: the solver, the contact plan, the overlap pass, the checks and the writer. |
| `build_own.py` | Builds a review file or a shipped file; refuses to write when a check fails. |
| `review_sheet.py`, `review_render.py` | The review sheet: the strip, the other bodies, the numbers, the notes. |

```sh
uv run --with numpy python -B build_own.py self-test
uv run --with numpy python -B build_own.py review <type> --blender <the pinned Blender> [--report <json>]
uv run --with numpy python -B build_own.py ship locomotion --blender <the pinned Blender>
uv run --with numpy --with pillow python -B review_sheet.py <type> --blender <the pinned Blender> --out <folder>
```

A rebuild writes the same bytes (`--check` compares with the files on disk and writes nothing). The clip from the
game's camera is `tools/capture/own_clips_review.tscn` (the starts and stops: `own_moves_review.tscn`; the jump's:
`own_jump_review.tscn`); the Godot tests are `tests/gameplay/test_own_clips.gd`, `test_own_moves.gd` and
`test_own_jump_clips.gd`.

The clip types are `idle`, `walk`, `jog`, `sprint`, `crouch_idle`, `crouch_walk`, `stand_to_crouch`,
`crouch_to_stand`, the directions `walk_back`, `walk_left`, `walk_right`, `jog_back`, `jog_left`, `jog_right`, the
leans `lean_left`, `lean_right`, `lean_fwd`, `lean_back` (below, "The directions and the lean"), the families
`idle_to_walk`, `idle_to_jog`, `idle_to_sprint`, `walk_stop`, `jog_stop` and `sprint_stop` (two clips each), and the
jump's `jump_start`, `jump_start_run_l`, `jump_start_run_r`, `jump_rise`, `jump_apex`, `jump_fall`, `land_soft`,
`land_hard` and `land_to_jog` (below, "The jump"). After `ship locomotion` changes `Crouch_Idle`, rebuild the prone
clips too (`../prone/`): their two transitions join its first pose. `fluidity.py` reads the shipped gaits against
the library clips they replaced (below, "How fluid the gaits are").

## The bodies

The clips are solved on `form_female` (`build_own.REFERENCE`), the body the template's player wears
(`CharacterBodies.FEMALE`), and every check runs on four bodies (`BODIES`): `form_female`, `form_male` (the
enemies), and the Quaternius pair, which stays in the template as bodies a game can swap in. Until kit #1160 the
reference was the Quaternius female; on the form bodies a foot standing on its ball then hung 5 to 6 mm over the
floor.

- **A foot on its ball is set down by its own skin** (`plan._state`, the rig's `tread`): the toes stay flat, the
  rest of the foot turns over them, and the foot is moved by what that leaves lowest. The form bodies' toes curl
  7.3 mm up off the floor at rest and the skin under the ball is shared between the foot and the toes; the Quaternius
  mannequins' toes lie on the floor. The ball's joint therefore goes down up to 4.5 mm as a heel rises.
- **One file cannot stand both foot shapes on their balls.** On the form bodies a planted sole is within 0.6 mm of
  the floor in every clip. On the Quaternius pair a raised foot sinks 5.2 to 7.4 mm, and the checks widen that
  body's floor and wander limits by the difference between its toes and the reference's (`checks.TOES_SAME`,
  `toes_off_mm` in the numbers): 9.3 mm for a planted sole, 12.3 mm under the floor.
- **The gaits' feet are set down for the template's two bodies** (`build_own.GAIT_BODIES`, `gait.play_on`), and
  checked on all four. Set down for the Quaternius pair as well, a gait's soles stood 3.3 to 3.9 mm off the floor on
  the form bodies. A gait sets its own skin on the floor frame by frame, so its plan turns the first bullet's
  settle off (`ContactPlan.tread`).
- **The four `ik_` targets are keyed** (`ik_foot_l/r`, `ik_hand_l/r`), since the prototype rig has them: each
  clip has 52 bones' rotations, the pelvis's place and the targets' places and turns. The Quaternius skeleton has
  no such bones and the tracks move nothing there. With the eight clips before the starts and stops the shipped
  file was 356 KB and imported to 130 KB for 24.8 s of clips (5.3 KB a second; the budget was 6, 7 since
  2026-11-13); with the twelve starts and stops and the nine jump clips it was 1.4 MB and imported to 352 KB for
  50.8 s (6.8 KB a second); with the strafes and lean poses of kit #1159 too it is 1.5 MB and imports to 397 KB for
  55.7 s (7,126 bytes a second, 42 bytes a second inside the 7 the test holds, below), with Godot's compression pages
  at 32 KiB: at 8 a long dense clip lost its pelvis's keys (`test_own_jump_clips.gd` compares the import with the
  file).
- **The targets are set from the finished pose** (`build.retarget`, kit #1161) and checked on every frame
  (`checks.check_targets`, 4 mm). Before, the overlap pass left a hand's target up to 53 mm off in a walk, and a
  loop's first and last targets were a stride off (the shipped jog's `ik_foot_l` 2.46 m ahead); every clip was
  rebuilt, and only the targets' keys moved.

**Picking another variant:** set the letter in `picks.json`, run `ship locomotion`, run the test. The other styles
stay here, so a game picks another vision by rebuilding, or writes a `style_d.json` of its own.

## Idle

Replaces `ual1/Idle`, which stays in the game as its stand-in (`CharacterClips.STAND_INS`). The library's idle
breathes and nothing else: 17 bones move, the pelvis 8.5 mm, no weight shift, no finger moves, its seam is 3 mm open
and its hand is 17 mm inside the thigh on the Quaternius female mannequin.

### What a standing person does (the research)

Read on 2026-11-11, before any number was keyed. Every finding below was read in a search's summary of the page
named, not in the page itself (two did not open, the others were not fetched), so each is a lead to confirm and the
clip's numbers are declared choices; where nothing was found it says so.

| What | Finding | Source | What the clip does with it |
| --- | --- | --- | --- |
| Shifts of weight | Standing unconstrained for half an hour, people move their centre of pressure in three ways: a **shift** to a new place, a **fidget** (out and back) and a slow **drift**; about two such changes a minute in all. A shift happens every 199 s (plus or minus 148) side to side and every 316 s front to back, 17 mm (plus or minus 15) front to back. | [Duarte and Zatsiorsky, 1999](https://scilit.com/publications/e55ba77c0ae037619e53051fee3e6824) | The clip shifts from one leg to the other and back once a loop (8 to 12 s), far more often than a person: a game's idle is watched for seconds, and a declared choice. The drift is the small fore and aft sway. |
| Standing on one leg more than the other | People standing relaxed are not symmetric, and women in the study less so than men, with two preferred ways of sharing the weight. | [Prado-Rico and Duarte, 2019](https://ouci.dntb.gov.ua/works/4Kgda6o4) | The loop starts and spends most of its time on the left leg; no frame has the weight even except in passing. |
| Breath | 12 to 20 breaths a minute at rest; breathing in is active and quiet breathing out is passive. | [Clinical Methods, respiratory rate](https://ncbi.nlm.nih.gov/books/NBK365) | 15 to 18 breaths a minute (a breath is 100 or 120 frames and divides the loop); in takes 38 % of a breath, out 47 %, then a pause. |
| How far the chest moves | Not found in a source we could open. | | The upper spine opens 1 to 1.6 degrees and the collarbones rise 1.2 to 2: working numbers, chosen so the breath reads from the game's camera and the head stays still. |
| The resting hand | Clinical texts give the knuckles 45 to 75 degrees of bend and the next joint about 10; a splint's resting position is 30 to 45 and up to 20. They differ by purpose, and an ergonomics study says the clinical ones are not a relaxed hand's. | [Evaluation of the hand](https://www.msdmanuals.com/professional/musculoskeletal-and-connective-tissue-disorders/approach-to-the-patient-with-joint-symptoms/evaluation-of-the-hand); [Lee and Jung, 2014](https://yadda.icm.edu.pl/baztech/element/bwmeta1.element.baztech-785f4b91-56ad-477b-8b98-36d5dc7e344c/c/Lee.pdf) | Each finger curls 52 to 76 degrees over its three joints, more toward the little finger, the knuckle taking 45 % of it; the thumb lies beside the palm. |
| The arm's hang | Not found: no source gave the elbow's angle of a relaxed standing arm. | | 12 degrees, the forearm turned 12 degrees inward, from looking at the pose from the side and the front. |
| Where the weight is over the foot | Standing, the body's line of weight falls a few centimetres ahead of the ankle (gait texts say so; none opened with a number). | | 34 % of the way from heel to toe, 2.7 cm ahead of the ankle joint on this foot. |

### How it is built

- **The weight is an input.** The description gives the share of the weight on the left foot on every frame; the
  pelvis is solved until the centre of mass (segment masses on the bones) is over that point between the feet, and
  raised or lowered until the straighter leg is 99.7 % of its length. So the body is in balance on every frame and
  the carrying knee is nearly straight, by construction.
- **The hips tip, the shoulders answer.** The free leg's hip drops, the pelvis turns toward it, the chest leans the
  other way by a share of the tip, the head stays level.
- **The hands keep off the thighs.** The solver opens each arm from the body until the wrist, the knuckles and the
  curled fingers' tips are 127 mm from the thigh's line on every body: the Quaternius female's hip is 100 mm wide of the
  joint, and curled fingers reach 45 mm inward of their knuckles.
- **Overlap.** The chest, the head, the upper arms, the forearms and the hands each follow the part they hang from
  through a spring with the style's lag and overshoot, run round the loop until its seam closes.

### The three variants

Measured by `../audit_clips.py` on the Quaternius female mannequin, the body the idle was first solved on; since
kit #1155 and #1160 the shipped idle is the same description solved on `form_female`, where its soles are within
0.2 mm of the floor and no limb crosses another on any of the four bodies (the review sheet prints its table on
that body):

| | A, grounded | B, loose | C, sharp | `ual1/Idle` |
| --- | --- | --- | --- | --- |
| Length | 10 s | 12 s | 8 s | 2.5 s |
| Bones that move, fingers among them | 50, 30 | 50, 30 | 48, 28 | 17, 0 |
| Weight on the carrying foot | 66 % | 80 % | 74 % | 50 % |
| Pelvis side to side | 80 mm | 137 mm | 123 mm | 8 mm |
| Hips tip, hips turn | 6, 4 degrees | 13, 10 | 10, 7 | 0, 0 |
| Head turns | 5 degrees | 11 | 15, looked and held | 0.2 |
| A shift takes | 60 frames | 75, and swings 12 % past | 26, held either side | none |
| Parts trail by (chest, head, arm, forearm, hand) | 2, 3, 2, 2, 2 frames | 4, 6, 4, 4, 5 | 1, 2, 1.5, 1.5, 1.5 | 0 |
| Limbs inside limbs, female and male | 0, 0 mm | 1.3, 0 mm | 0, 0 mm | 17 mm, hand in thigh |
| Seam | closed to the bit | closed | closed | 3 mm open |

**A is the one shipped** (`picks.json`), as the recommendation: it reads as a person at rest from the game's
camera, and its shift is small enough that the gaits' first frames stay close to it. B is the vision to pick for a
loose, lived-in character; C for a small or stylised body seen from far.

### Numbers for the code

- The idle is in place and does not travel (`speed` 0); both feet are down for the whole clip (`contacts`).
- Imported with Godot's key optimizer off and track compression on: 39 KB for the 10 s clip (3.9 KB a second,
  alone in the file), and a planted foot's joints stay within 2 mm (`tests/gameplay/test_own_clips.gd`: 0.2 mm on
  the file's own keys, 1.1 to 1.5 mm after the import's compression, under a pelvis that travels 73 mm).
- It keys 52 bones' rotations and the pelvis's place; the root, the `_leaf` bones and (on the prototype rig) the
  twist bones and sockets are never keyed.

## The crouch: `Crouch_Idle`, `Crouch_Walk`, `Stand_To_Crouch`, `Crouch_To_Stand`

Kit #1160. `Crouch_Idle` and `Crouch_Walk` replace `ual1/Crouch_Idle` and `ual1/Crouch_Fwd`, which stay as their
stand-ins. `Stand_To_Crouch` and `Crouch_To_Stand` are new: Quaternius's library has no stance change, and the game
cross-faded between a standing pose and a half kneel 719 mm apart at the head.

The first crouch of this issue stood on the standing idle's feet, side by side and level, with one number for both
knees and both arms. It read as a squat over a toilet beside the library's crouch and was rejected in review. The
rule it broke is the kit's `docs/tools/blender/own-animation.md#feel` ("No mirror poses"): a held pose has a number
per side. This crouch is built that way, and every number below that a side could own is a pair `[left, right]` in
the description and in the style files.

### What each side of the library's crouch does (read, not copied)

Read on 2026-11-11 from `ual1/Crouch_Idle` and `ual1/Crouch_Fwd` on the female mannequin, filmed from the front,
the side and above and measured joint by joint. These are what makes it read as a person at ease; none of its keys
or values is used, and our numbers are in the next table.

| Part | Left | Right |
| --- | --- | --- |
| Foot | flat, 0.37 m ahead of the root, turned out 3 degrees | 0.32 m behind the root on its ball, the heel up 51 degrees, turned out 21 |
| Knee | up in front of the chest, 0.53 m off the floor, bent 95 degrees | pointing forward and down, 0.27 m off the floor, bent 133 |
| Hip | 13 degrees lower than the right; the pelvis is 0.47 m up and turned 8 degrees toward the rear leg | the higher hip |
| Shoulder | 4 degrees lower; the chest folds 80 degrees and turns 8 against the hips | |
| Arm and hand | the elbow far out and back, bent 47 degrees; the hand hangs 0.41 m out to the side, outside the knee, at 0.42 m | the elbow bent 75 degrees; the hand held ahead of the low knee at 0.49 m |
| Head | looks 39 degrees down, turned 3 | |
| Life | breath only: the pelvis moves 6 mm, the fingers hold a pose | |

In `Crouch_Fwd` the trunk and both arms hold that pose for the whole stride (the hands move only as the trunk
does), the pelvis keeps its 8 degree turn and tips from 14 degrees to none and back rather than evenly to both
sides, each trailing knee comes within 0.14 to 0.18 m of the floor, the trailing heel is up 41 to 51 degrees, the
leading foot lands with its toes up 21, the pelvis rises 0.46 to 0.52 m twice a stride and the head sways 0.09 m
from side to side. Its feet are the ones the audit measured: a planted sole wanders 574 mm.

**What we take from it:** the stance is staggered and each foot lies differently; one knee is high and one low;
the hips and the shoulders are turned and tipped against each other; the two arms do different things; a walk
keeps the idle's carriage. **What ours does differently:** the stagger is shorter (one step from standing makes
it), the stance is narrower, the low knee's hip is the lower one, the left forearm lies on the thigh where the
library's left hand hangs outside the knee, the right arm hangs where the library's is held, the head looks
ahead, the weight moves, and the walk's arms swing.

### How a body crouches and walks crouched (the research)

Read on 2026-11-11, before the numbers were set. The squat study was read on its own page; the others in a search's
summary of the page named, so they are leads; where nothing was found it says so and the number is a declared choice.

| What | Finding | Source | What the clips do with it |
| --- | --- | --- | --- |
| How far each joint folds in a deep squat | Squatting as deep as they could hold, feet at shoulder width and heels down, people went down 43 to 47 % of their leg length; the knee moved through 119 to 125 degrees, the hip 99, the ankle 31, the pelvis tipped forward 20 to 23 and the lower spine flexed 30 to 44. | [Zawadka et al., 2020](https://pmc.ncbi.nlm.nih.gov/articles/PMC7429430) | The crouch lowers the pelvis to 0.44 m, 48 % of its standing height. The front knee bends 115 degrees with its heel down; the rear knee bends more than a level squat allows (140), which is why that foot is behind on its ball. The pelvis tips 12 degrees and the spine takes the rest of a 78 degree fold. |
| The order the joints finish in | The pelvis's forward tip peaks at 62 to 70 % of the way down and the ankle at 87 to 90 %; the knee, the hip and the spine reach their ends together at the bottom. | the same study | Going down, the pelvis's turn is done by 62 % of the clip and the legs and the trunk finish last. |
| The heel | A heel that leaves the floor makes up for an ankle that has run out of bend. | a coaching text and a review, both in a search's summary | The rear foot stands on its ball with the heel 46 degrees up; the front sole stays flat. |
| A crouch held at rest | Not found in a study we could open: no source gave the angles of a person resting in a staggered crouch. | | The stance is read from how the library's crouch rests (the table above) and from our own bodies, then given our own numbers; they are declared choices. |
| Running and walking on bent legs | Running with the knees bent lowers the body's vertical stiffness and costs up to 50 % more oxygen; walking on bent hips and knees has a nearly flat path of the centre of mass, lower peak forces, much more ankle bend and less hip extension, and the swinging leg turns further because the foot has less room under it. | [McMahon et al., 1987](https://doi.org/10.1152/jappl.1987.62.6.2326) and a review of bent-hip, bent-knee walking, in a search's summary | The crouch walk's pelvis dips 8 to 24 mm as each leg takes the weight (the library's rises and falls 61 mm), the foot lands flat and its heel rises from the landing on, and the swing clears the floor by 45 mm. |
| Cadence and step of a crouched walk at 1.5 m/s | Not found in a source we could open. | | 150 to 180 steps a minute on steps of 0.50 to 0.60 m: a declared choice, set by the body. With the pelvis this low a longer step bends the ankle past its 55 degrees and brings the trailing knee toward the floor. |
| How long a drop takes | No study with a time was found. Physics gives the floor: a body with a foot down cannot fall faster than gravity, and the centre of mass goes down 0.45 m, which a free fall takes 0.30 s over (9 frames) before any braking. | computed | 15 frames is the shortest drop here that stays under gravity (0.93 of it); the build fails one that does not (`checks.FALL`). The controller's `crouch_time` is 0.2 s (6 frames), which no drop of this depth fits. |
| The capsule | `CharacterTuning.crouch_height` is 1.1 m for a body 1.80 m tall. | the template | Every frame of the crouch idle and walk is under 1.1 m on every body (`form_male` reaches 1.071 and 1.068 m, the Quaternius male, the tallest, 1.0996 and 1.0963 m; the library's walk reaches 1.127 m on the Quaternius female), which is what folds the trunk 78 degrees. |

### How they are built

- **A staggered stance, one step from standing.** The left foot stands flat where the shipped standing idle has it
  (`clips/joined.py` reads `picks.json`); the right foot is a step behind on its ball, wider and turned out
  further. Only the right foot's place differs from the standing idle's, so one step makes the stance.
- **The knees at different heights.** The front knee is up in front of the chest; the rear knee points outward of
  its foot and 30 degrees under level (`knee_down`), a hand or two off the floor.
- **The weight is an input**, as in the idle: the pelvis is solved until the centre of mass is over a point
  between the flat foot and the ball of the rear one (62 to 72 % of the way to the front foot), and the front leg is
  folded to a share of its length. The pelvis is turned toward the rear leg and tipped so that leg's hip is lower;
  the chest turns and leans the other way.
- **A forearm on a thigh.** The solver's `rest` lowers the left arm until its forearm's line is 115 mm from the left
  thigh's and shin's on every body, measured at each body's own joints, on every frame, so it stays there
  while the chest breathes and the weight moves; that arm is left out of the overlap pass. The right arm hangs
  24 degrees out from the body and keeps its hand 100 mm from its thigh's line, which is what keeps a pistol held
  in that hand out of the leg on both of the template's bodies (`tests/gameplay/test_pistol_clearance.gd`: the
  pistol is 38 mm clear of `form_female` in the idle, 53 and 55 mm in the stance changes and over 100 mm in the
  walk, and over 100 mm clear of `form_male` in all four).
- **The walk is its footfalls** (`gdsanim.plan`): speed, cadence and planted share are inputs, and the two steps are
  the same length half a stride apart, as a steady gait's must be. Its carriage is read from the shipped crouch
  idle (pelvis height, the trunk's fold, half of the idle's turn and tilt, each arm's hang), and everything else
  has a number per side: the right foot tracks wider and turns out further, its knee swings wider, the left arm
  is carried bent and swings little, the right hangs longer and swings freely. Both arms are carried outside
  their thighs, which rise to the chest.
- **A stance change steps the right foot** (`clips/stance.py`, `stance_plan`): the left sole never moves. Going
  down the right foot leaves over its toes as the hips let go and lands on its ball as the body arrives over it;
  coming up it leaves from its ball once the legs have begun to push and lands flat. Every other control is mixed
  from the one idle's first frame to the other's on its own timing, each arm from its own numbers, and
  `Clip.meet` makes the ends the idles' first poses (within 0.2 mm and 0.09 degrees in the build's check,
  which reads 32-bit keys).

### The variants

Three stances, not one stance at three tempos. Measured on `form_female` at the first frame by the build and
`../audit_clips.py` (the review sheets print the audit's tables); the library's column is its clip on the same
body.

| `Crouch_Idle` | A, grounded | B, loose | C, sharp | `ual1/Crouch_Idle` |
| --- | --- | --- | --- | --- |
| The right foot behind the left, and the feet apart | 0.53 m, 0.26 m | 0.65 m, 0.32 m | 0.41 m, 0.24 m | 0.68 m, 0.37 m |
| The feet turned out, left and right | 9, 26 degrees | 9, 35 | 9, 18 | 3, 21 |
| The right heel up | 46 degrees | 54 | 38 | 51 |
| Knees off the floor, left and right | 0.50, 0.25 m | 0.51, 0.25 m | 0.50, 0.34 m | 0.53, 0.28 m |
| Hips turned, and the right hip lower by | 12, 5 degrees | 18, 8 | 7, 3 | 3, and the left lower by 13 |
| Shoulders turned the other way | 11 degrees | 17 | 6 | 1 |
| The trunk folds, the head looks down | 78, 22 degrees | 84, 26 | 76, 20 | 80, 39 |
| The left arm | forearm on the left thigh, elbow 57 degrees, the hand drooping inside the knee | the same with the elbow at 73 (at 58 the forearm lay 15 mm inside the form female's knee), the hand drooping further | the same, elbow 65, the fingers closed further | hangs outside the knee, elbow 47 |
| The right arm | hangs 24 degrees out from the body, outside the low knee, elbow 17 degrees, wrist 0.34 m up | the hand held over the low thigh, 0.06 m higher than a hand lying on the knee (lying there, the pistol it holds sat 32 mm inside the form female's thigh), elbow 43 | bent 63 degrees, the hand held outside the knee at 0.39 m | held ahead of the knee, elbow 74 |
| Length | 8 s | 10.7 s | 8 s | 2.9 s |
| Pelvis side to side, hips turn, head turns | 31 mm, 3, 7 degrees | 33 mm, 6, 14 | 18 mm, 3, 29 (looks, holds, looks back) | 6 mm, 1, 4 |
| Highest vertex, `form_female`, `form_male` and the Quaternius male | 1.035, 1.071, 1.0996 m | 1.033, 1.068, 1.097 | 1.030, 1.067, 1.095 | 1.045 on the Quaternius female |
| A planted sole off the floor, `form_female` and `form_male` | 0.1, 0.4 mm | 0.1, 0.6 | 0.1, 0.3 | |
| Limbs inside limbs, the four bodies | 0 mm | 0 on the template's two, 4.3 on the Quaternius male | 0 | none |

| `Crouch_Walk` | A, grounded | B, loose | C, sharp | `ual1/Crouch_Fwd` |
| --- | --- | --- | --- | --- |
| Stride | 22 frames | 24 | 20 | 60 |
| Steps a minute | 164 | 150 | 180 | 60 |
| Planted sole speed | 1.51 m/s | 1.51 | 1.51 | 0.46 (0.04 to 0.96) |
| A planted sole wanders (the build's measure, `form_female` and `form_male`) | 2.3, 1.7 mm | 2.2, 1.2 | 2.2, 1.7 | 574 on the Quaternius female |
| A planted sole off the floor, the same two | 0.2, 0.3 mm | 0.2, 0.5 | 0.0, 0.3 | |
| Pelvis up and down | 16 mm | 24 | 8 | 61 |
| The trunk's turn the walk keeps, hips and shoulders | 6, 4 degrees | 6, 4 | 6, 4 | 8, 10, held still |
| The feet turned out, left and right; the right tracks wider by | 4, 11 degrees; 18 mm | the same | the same | 3, 3 at landing |
| The arms swing, left and right | 10, 18 degrees | 13, 22 | 7, 13 | the arms hold still |
| The elbows, left and right | 74, 36 degrees | the same | the same | 47, 75 |
| The arms carried out from the idle's, left and right | 25, 18 degrees (at 18 the left hand went 10 to 30 mm into the form female's calf) | the same | the same | |
| Arm with the other side's leg | 0.83 | 0.82 | 0.83 | none |
| Highest vertex, `form_male` and the Quaternius male | 1.066, 1.0955 m | 1.066, 1.0950 | 1.066, 1.0956 | 1.127 on the Quaternius female |
| Limbs inside limbs, the four bodies | 0 mm | 0 | 0 | none |

| Stance changes | A, grounded | B, loose | C, sharp |
| --- | --- | --- | --- |
| `Stand_To_Crouch` | 16 frames, 0.85 of gravity; the right foot in the air from frame 3 to 10 | 20 frames, 0.54; 4 to 13 | 15 frames, 0.91; 3 to 10 |
| `Crouch_To_Stand` | 16 frames, stops at 0.94 of gravity; the right foot in the air from frame 6 to 14 | 20 frames, 0.50; 7 to 16 | 15 frames, 1.04; 4.5 to 12 |
| First and last pose against the idles' | 0.2 mm at most, 0.09 degrees | the same | the same |
| A planted sole wanders, `form_female` | 1.1 and 0.3 mm | 1.2 and 0.0 | 1.2 and 0.0 |
| A planted sole off the floor, `form_female` and `form_male` | 0.0, 0.3 mm | 0.1, 0.3 | 0.1, 0.3 |
| Limbs inside limbs, the four bodies | 0 mm | 0 | 0 |

**B is shipped for `Crouch_Idle`, `Crouch_Walk` and `Stand_To_Crouch`, and A for `Crouch_To_Stand`**
(`picks.json`): the maintainer's choice, `Crouch_Walk` on 2026-11-11 and the rest on 2026-11-12 (the stand-up
first B, then A the same day: 16 frames, the quicker rise); the other variants stay in the review files. On
`form_male` the standing end of both stance changes reads 2.1 mm, thigh in thigh, which is the shipped idle's
own standing pose on that body (`bodies_overlap.json`; the limit is 5). Every
variant of a stance change joins the shipped idles and every variant of the walk is carried like the shipped
crouch idle, so the tables above are A, B and C on idle B's pose, and the walk's default carriage
(`clips/crouch_walk.py`: `lift`, `chest_more`, `arm_out`, `arm_fore`) is the one that fits it: on the carriage
tuned for idle A the walk's forearm went 50 to 70 mm into a thigh or the pelvis. A `Crouch_Idle` of another letter
rebuilds the walk, the stance changes and the prone transitions on its pose. In every variant the left foot keeps
its standing place, so one step of the right foot makes the stance.

### The crouch's numbers for the code

- `Crouch_Walk` is in place at 1.5 m/s (`speed`), the left foot lands at frame 0 and the right half a stride later
  (`contacts`, `events`). `flat` in `locomotion.json` is each contact's frames with the whole sole down: from an
  entry's first frame to the end of its contact the ball of the foot stays on its place while the heel may rise.
- The stance changes do not travel. The left foot is down for the whole clip; the right has two contacts with its
  step between them (`contacts`), and a `footstep` event where it lands. `joins` names the shipped clips whose
  first poses the ends are, and the event `crouched` (frame 19 of 20) or `rising` (frame 1 of 16) marks where the
  legs' fold ends or begins. They are 0.67 s down and 0.53 s up against a `crouch_time` of 0.2 s: going down, the
  capsule and the camera get
  there first; coming up, the capsule is full height before the body is. The tree that plays them is kit #1158.
- The crouch stands behind the root: its pelvis is 0.36 m behind it and its rear foot 0.65 m (the library's
  pelvis is 0.28 m behind), since the front foot keeps the standing idle's place.
- Each clip keys 52 bones' rotations, the pelvis's place and the four `ik_` targets; the walk's fingers move with
  the arm swing, so it carries their tracks. The cost per clip is in the pull request.
- The walk's sole wander is the heel's skin, which the shin shares: at an ankle bent this far it slides a few
  millimetres over a foot whose joints do not move (the Godot test holds the joints to 2 mm on the floor, and lets
  the ball's joint go down 6 mm as the heel rises).

## Walk, Jog, Sprint

Replace `ual1/Walk`, `ual1/Jog_Fwd` and `ual1/Sprint`, which stay in the game as their stand-ins. The library's
gaits do not hold the floor at the speeds the game moves them at (the walk's feet cover 56 % of the ground, the
jog's sweep 48 % faster than it), its jog is in the air for 64 % of its cycle with 245 mm of bob, the run's arm
swing is the chest turning 76 degrees, and nothing trails (the kit's
`docs/tools/blender/own-animation.md#audit-gaits`). All three are one description, `clips/gait.py`, with a table of
numbers per gait.

### How people walk and run (the research)

Read on 2026-11-11, before any number was keyed. "Opened" means the page itself was read; "summary" means only a
search's summary of it was, so the number is a lead; where nothing was found it says so and the clip's number is a
declared choice.

| What | Finding | Source | What the clips do with it |
| --- | --- | --- | --- |
| A walk's pace | At a comfortable 1.32 m/s: 118 steps a minute, a 0.67 m step, a foot down 60.7 % of the cycle. Walking fast at 1.87 m/s: 141 steps, 0.79 m, 58.5 %. | [Shemmell et al., 2007](https://pmc.ncbi.nlm.nih.gov/articles/PMC1866234/) (summary, its table) | Between the two at the game's 1.7 m/s: 134 steps a minute and 59 %. `Walk` is 26 frames (138 steps, a 0.74 m step) with a foot down for 15 of them (58 %); the loose one is 28 frames (129). |
| A run's pace against speed | 860 recreational runners on a treadmill at their own pace (2.75 m/s on average): 164 steps a minute (SD 9), 289 ms on the ground, a foot down 39 % of the cycle, the centre of mass 77 mm up and down (SD 12). Each m/s faster: 11 steps a minute more, 62 ms less on the ground, 5.9 points less of the cycle; the rise and fall does not change with speed. | [Reference values in recreational runners, 2023](https://pmc.ncbi.nlm.nih.gov/articles/PMC10588426/) (opened; the per-m/s figures are its per-km/h slopes times 3.6) | At 4.0 m/s: 178 steps a minute, 211 ms and 32 %. `Jog` is 20 frames (180 steps) with a foot down for 6 (200 ms, 30 %). Its centre of mass goes 64 mm, inside one SD of the 77. |
| A sprint's pace | Elite sprinters at 10.6 m/s: 4.56 steps a second (274 a minute), 96 ms on the ground, 124 ms in the air, a 2.32 m step. The study above stops near 4.2 m/s and its straight lines give nonsense at 6.5. | [Stride characteristics of elite sprinters, 2021](https://pmc.ncbi.nlm.nih.gov/articles/PMC8008308/) (opened) | 6.5 m/s is between the two sets: the ground a contact covers goes from 0.84 m at 4.0 m/s to 1.02 m at 10.6, so about 0.91 m and 140 ms here, at about 210 steps a minute. `Sprint` is 18 frames (200 steps) with a foot down for 4 (133 ms, 22 %): a declared choice between two sources, not a measured figure. |
| The joints of a running leg | The hip is about 50 degrees bent as the foot lands and 10 past straight after it leaves; the knee about 40 bent as it lands, 60 as it takes the weight, 40 again as it leaves, and up to 125 in the swing; the swing is 62 % of the cycle (40 % in a walk). | [Biomechanics of running, lecture notes](https://gyansanchay.csjmu.ac.in/wp-content/uploads/2022/02/Biomechanics-of-Running.pdf) (opened; it gives no speed and no primary source for the angles) | `Jog`'s knee: 20 degrees as the foot lands, 51 under the weight, 20 as it leaves, 109 in the swing. The landing knee is straighter than the notes': the ball of the foot lands 0.37 m ahead of the body's centre, and a deeper knee would need the hips lower than the 82 cm they sink to. |
| A sprinter's leg | Knee 24 degrees bent at landing and 25 at take-off, 140 at its tightest in the swing, the thigh 21 degrees under level at the top of the knee lift; "a flat, active foot contact". | the elite sprinters' study above (opened) | `Sprint`: 40 at landing, 16 at take-off, 132 in the swing, the thigh 77 degrees forward of straight down (13 under level). It lands on the ball of the foot with the heel 14 degrees up, and the heel stays 5 up. Its landing knee is deeper than an elite sprinter's: a declared choice for a body that is not one. |
| Between contacts | A body in the air is in free fall. | physics | The centre of mass of the runs is on a free fall's arc from the frame a foot leaves to the frame the other lands (the build's check reads 0 to 1.1 mm off it), and the contact in between catches and throws it. The pelvis is solved from the centre of mass on every frame. |
| The pelvis's turn | Its range in running is 5 to 28 degrees between runners; walking pelvis and thorax turn against each other more the faster the walk. Its timing differs between walking and running: cited to Novacheck (1998), which we could not open. | [Folland et al., 2017](https://pmc.ncbi.nlm.nih.gov/articles/PMC5473370) (opened; ranges only, its table is an image); [lumbo-pelvic kinematics with speed](https://www.sciencedirect.com/science/article/abs/pii/S0268003305000902) (summary) | Hips turn 8 degrees in `Walk`, 12 in `Jog`, 18 in `Sprint`, the shoulders 8, 19 and 25 against them. In the walk the hip of the landing leg is furthest forward as it lands; in the runs the hip of the driving knee is, about as the other foot leaves. That timing is our reading of how the knee drive and the arms go together, not a sourced number. |
| The arms | In a walk the elbow moves through 29.7 degrees (SD 10.2). In a run the elbow is held near a right angle and bends and opens twice a cycle. No page we could open gave the shoulder's swing in degrees. | [Kang et al., 2023](https://doaj.org/article/d3582d494e3a48d7b694f5b55df11067) (summary); a coaching article (summary) | `Walk`: the left upper arm swings 49 degrees and the elbow gives 24; the right arm swings about a quarter less, more bent. `Jog`: 87 degrees on the left with the elbow near a right angle. `Sprint`: 121. The swings' sizes are declared choices, read off the renders. |
| The foot's landing speed | Not found in a source we could open. | | A walk's foot is at rest over the floor as it lands. A run's keeps half of the ground's speed (`land_speed`) and comes down at about 1 m/s: brought to rest in the air first, it has to reach past its landing place while the body goes on under it (11 cm in the jog and 20 in the sprint, by the path's own arithmetic), and the leg that reaches furthest sets the height of the whole cycle. |

### How the gaits are built

- **Footfalls first.** The left foot lands at frame 0 and the right at half the cycle in all three; a foot is on
  one place of the floor for a whole number of frames while the root travels at the game's speed. Cadence, planted
  share and speed are the style's numbers, and `locomotion.json` carries them (speed, contact frames, a footstep
  event per landing).
- **The centre of mass is the input.** It moves at the clip's speed, sways toward the carrying foot, and goes up
  and down as a body's does (highest over the standing leg in a walk; a free fall between a run's contacts). The
  pelvis is solved from it, and the whole path is set as high as the furthest-stretched leg allows (`stretch`), so
  no knee locks and no ankle is out of reach.
- **The feet are set down on every body's skin.** The clips are solved on `form_female` and checked on `form_male`
  (the prototype bodies the template wears, kit #1299; they were first made on the Quaternius pair, whose soles
  are not one shape). The heel's skin follows the shin, and the prototype sole turns up ahead of the ball of the
  foot (the toes' own skin is 7 mm over the floor), so a foot that rolls onto its toes stands on the ring of skin
  under the toes' joint: each frame's ankle height is corrected until the lowest skin of both bodies is nearest
  the floor while planted (the foot comes down 5 mm by the frame the toes leave) and clear of it in the swing.
- **The swing.** The foot leaves over its toes, is drawn up behind (`kick`), passes under the body and comes down
  onto the floor at a speed. The knee's bend is what the path leaves it, not a keyed angle.
- **The trunk and the arms.** The pelvis turns and tips with the legs, the chest turns and leans against it, the
  head stays level; each arm swings in its socket with the other side's leg, and goes out past the hip on its way
  back so the hand clears it on both bodies.
- **Overlap.** The chest, the head, the upper arms, the forearms and the hands follow through the overlap pass.
  At a gait's pace a spring changes a swing's size and timing, so the description leads and enlarges the upper
  arm's swing by what the spring will take, and the declared lags are the spring's at that pace.
- **Each side has its own numbers** (`left`, `right` and the `_rest` numbers of a style's section; the kit's
  `docs/tools/blender/own-animation.md#feel`, no mirror poses). In the grounded walk the right foot points 10
  degrees out and lands 85 mm from the middle line, the left 4 degrees and 75 mm; the left arm swings 21 degrees
  forward and 24 back with the elbow at 18, the right 14 and 19 with the elbow at 22, hanging 2 degrees further
  out, turned in 6 more and its fingers closed 6 to 10 degrees more; the pelvis stays turned a degree and its
  right side a degree low, the chest 2 degrees back on the right with that shoulder 1.5 lower, the head turned
  1.5 and tilted 1 against them. The runs do the same with their own figures (the right arm tighter and its
  shoulder a little raised and lower, the feet at different widths and toe-out). The loose variant has 1.4 times
  these differences and the sharp one 0.8. On top of that the right foot reaches 12 mm further and lifts a tenth
  higher and the left arm swings 8 % wider (`uneven`). **Each side has its own timing too**: in the grounded
  walk the right heel takes 6.8 frames to come up where the left takes 7.5, the right foot is drawn highest 33 %
  into its swing (the left 30 %), and the right arm is furthest forward 0.02 of a cycle after half a cycle from
  the left's (`roll_out`, `kick_at`, `arm_at` under `right`; the loose variant by 0.03, the sharp by 0.015). The
  feet still land half a cycle apart to the frame, so a blend between the gaits stays in step. The right arm is the
  one that carries a weapon: in the
  shipped jog and sprint it goes further out on its way back and turns in less, which keeps the carried pistol
  78 mm clear of the female in the walk and more than 100 mm clear of both bodies in the jog and the sprint
  (`tools/carry/measure_clearance.gd`, 96 samples a clip; `tests/gameplay/test_pistol_clearance.gd`).

### The three variants of each

Measured by `../audit_clips.py` on `form_female`, the body the clips are solved on (the player's), with the
build's own numbers for `form_male` (the enemies'); the review sheets print the whole table.

| | A, grounded | B, loose | C, sharp | the library's |
| --- | --- | --- | --- | --- |
| **Walk**: steps a minute, planted sole speed | 138, 1.70 m/s | 129, 1.70 | 138, 1.70 | 90, 0.95 |
| Pelvis up and down, side to side | 37, 48 mm | 44, 66 | 34, 50 | 53, 71 |
| Hips turn and tip, shoulders turn | 8 and 6, 8 degrees | 12 and 9, 12 | 6 and 5, 10 | 4 and 5, 15 |
| Upper arm swings; forearm, hand, chest trail | 49; 1.4, 1.4, 1.3 (degrees; frames) | 65; 2.1, 2.0, 2.4 | 50; 0.9, 0.9, 0.8 | 33; 0.2, 2.2, 1.3 |
| Thigh swings, trunk leans, halves differ | 62, 5.2, 1.5 degrees | 67, 5.6, 2.0 | 63, 5.2, 1.0 | 58, 11.7, 2.5 |
| Planted sole wanders (the build), female and male | 2.6 and 2.8 mm | 2.8 and 3.0 | 2.6 and 2.7 | 64 (the audit) |
| Limbs inside limbs, female and male | 0.0 and 0.6 mm | 0.0 and 0.4 | 0.0 and 0.3 | 12 mm on the Quaternius female |
| Key bytes a second | 19.9 KB | 21.4 | 23.7 | |
| **Jog**: steps a minute, planted sole speed | 180, 4.00 m/s | 180, 4.00 | 180, 4.00 | 129, 5.90 |
| Pelvis up and down, side to side | 79, 38 mm | 91, 53 | 81, 33 | 245, 36 |
| Hips turn and tip, shoulders turn | 12 and 8, 19 degrees | 16 and 11, 25 | 9 and 5, 14 | 1 and 10, 76 |
| Upper arm swings; forearm, hand, chest trail | 87; 0.8, 0.9, 0.8 (degrees; frames) | 108; 1.2, 1.4, 1.8 | 83; 0.9, 0.9, 0.8 | 86; 1.6, none, none |
| Thigh swings, trunk leans, halves differ | 77, 7.8, 1.6 degrees | 80, 7.8, 2.3 | 86, 9.1, 0.9 | 117, 25.5, 3.7 |
| Planted sole wanders (the build), female and male | 2.4 and 2.2 mm | 2.5 and 2.3 | 2.5 and 2.3 | 10 |
| Limbs inside limbs, female and male | 0.0 and 1.8 mm | 0.0 and 2.5 | 0.0 and 1.3 | not measured |
| Key bytes a second | 24.7 KB | 21.2 | 24.8 | |
| **Sprint**: steps a minute, planted sole speed | 200, 6.51 m/s | 200, 6.51 | 200, 6.51 | 180, 5.87 |
| Pelvis up and down, side to side | 90, 26 mm | 93, 29 | 88, 24 | 138, 36 |
| Hips turn and tip, shoulders turn | 18 and 8, 25 degrees | 22 and 10, 31 | 14 and 5, 19 | 4 and 10, 47 |
| Upper arm swings; forearm, hand, chest trail | 121; 0.9, 0.9, 0.8 (degrees; frames) | 138; 1.3, 1.5, 1.3 | 122; 0.9, 0.9, 0.8 | 78; 0.3, 0.1, none |
| Thigh swings, trunk leans, halves differ | 95, 9.9, 1.9 degrees | 95, 9.3, 2.5 | 101, 12.4, 0.9 | 112, 39.2, 13.4 |
| Planted sole wanders (the build), female and male | 2.1 and 1.8 mm | 2.1 and 1.8 | 2.1 and 1.8 | 305 |
| Limbs inside limbs, female and male | 0.0 and 1.6 mm | 0.0 and 2.7 | 0.0 and 1.6 | not measured |
| Key bytes a second | 23.9 KB | 24.1 | 27.0 | |

**Shipped** (`picks.json`, the maintainer's picks on PR #1275): `Walk`, `Jog` and `Sprint` are all A (the jog
reads better with the pistol held; the walk was B until the second pick).
A's numbers are a person's at the game's speeds; B is the vision for a loose,
long-limbed character; C for a small or stylised body seen from far.
The grounded and the sharp runs trail by the same frames; what tells them apart is the trunk (hips, shoulders,
lean) and the knee lift; the "halves differ" row follows the thighs only, and the sides differ most in the
arms, the feet's turn and the shoulders' set. The key bytes are a fifth more than on the Quaternius rig: the
prototype rig's four `ik_` targets are keyed too (a rotation and a place each), for the game's foot and hand
placement, and each gait declares its own limit (`kb_a_second`: 24, 25 and 27 KB a second).

### What the numbers do not say

- **The walk's knee is 23 degrees bent as the heel lands** (a person's about 5) and the hips ride 2 to 6 cm under
  the standing height: the step is 0.74 m on 0.83 m legs and the rise and fall is held to 37 mm.
- **The runs sit low.** The pelvis goes down to 82 cm in the jog and 80 cm in the sprint (92 standing), and it is 7
  to 12 cm behind the centre of mass in the sprint because the trunk leans.
- **The audit reads the jog's planted sole wandering 7 mm.** It follows every vertex of the sole, and the heel's
  skin is weighted to the shin, which swings 25 degrees a frame over the planted foot. On the skin that only the
  foot and the toes move, the build read 4.4 mm there; on the prototype bodies it reads 2.4 mm.
- **The toes' joint comes down 5 mm as a foot rolls off.** In Godot the joint stays within 0.4 mm along the floor
  on both bodies and moves 5.2 to 5.7 mm in height through a contact (`tests/gameplay/test_own_clips.gd` holds
  the two apart): that is the turned-up sole above, not a slide.
- **The pelvis moves 2 to 5 cm fore and aft in place.** The centre of mass moves at one speed, so the pelvis gives
  way as a leg swings forward. The game's capsule moves at one speed; the tree's issue (kit #1158) decides whether
  the pelvis's own travel is kept.

### Numbers for the code (the gaits)

| | Walk | Jog | Sprint |
| --- | --- | --- | --- |
| Frames, seconds | 26, 0.867 | 20, 0.667 | 18, 0.6 |
| `speed` in `locomotion.json` (the game's) | 1.7 m/s | 4.0 | 6.5 |
| Left foot down (frames), right foot lands | 0 to 15, 13 | 0 to 6, 10 | 0 to 4, 9 |
| Footstep events | 0 (left), 13 (right) | 0, 10 | 0, 9 |
| In the air | never | frames 6 to 10 and 16 to 20 | 4 to 9 and 13 to 18 |
| Tracks: bones' rotations, and the places of the pelvis and the four `ik_` targets | 56 and 5 | 56 and 5 | 56 and 5 |
| Keys kept by the build, of every frame | 76 % | 79 % | 76 % |
| Keys a half-degree reducer keeps on moving bones (budget 40 %) | 33 % | 44 % | 51 % |
| Key bytes in the file | 20.6 KB | 16.5 KB | 14.3 KB |

- **Imported size:** the library file was 68.4 KB imported with the idle and the three gaits, 5.6 KB a second over
  their 12.1 s (130 KB and 5.3 with the crouch clips, 24.8 s), inside the budget the test holds the file to (6 KB
  a second then, 7 since 2026-11-13) (57.6 KB and 4.8 on the Quaternius rig, before the `ik_` targets were keyed).
  A gait alone is over that budget: a short loop of fast motion has few frames a reducer can drop, and the jog and
  the sprint are over the 40 % key budget for that reason (declared in the description, `keys_kept`).
- **Frame cost:** ten walking characters take 1.39 ms a frame with `gds/Walk` against 1.28 ms with the library
  walk on the desktop (the median of `tests/gameplay/test_parts_budget.gd`, five runs of each, interleaved): 8 %
  more, 0.011 ms a character, for 61 tracks where the library clip moves 21 bones.
- **They are played at their own pace** by the ground blend space, as the library's were; since their speeds are
  the game's own, the feet hold the floor at the three tuned speeds. Between them the blend still slides: speed
  matching is kit #1158.
- **Footsteps** come from the feet's height as before (`Footsteps`), now seven a three seconds in a walk.
- **The pistol's hold** was solved on the library's gaits; `tests/gameplay/test_pistol_hold.gd` and
  `test_pistol_clearance.gd` pass on ours without a change.

## How fluid the gaits are

The first review found the loops less fluid than the library's. `fluidity.py` measures it on the player's body, each
clip as its file plays (`uv run --with numpy python -B fluidity.py --bones`). The shipped picks before and after
the pass, and the library clip each replaced:

| | Walk (A) before | after | `ual1/Walk` | Jog (A) before | after | `ual1/Jog_Fwd` | Sprint (A) before | after | `ual1/Sprint` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Frames a cycle | 26 | 26 | 40 | 20 | 20 | 28 | 18 | 18 | 20 |
| Joints' effective harmonic (1 is one smooth wave a cycle) | 3.88 | 3.18 | 4.17 | 2.82 | 2.37 | 4.05 | 2.60 | 2.24 | 3.36 |
| Largest change of a joint's speed in one frame (degrees) | 36.9 | 25.8 | 18.0 | 53.8 | 32.1 | 73.6 | 72.6 | 40.5 | 67.9 |
| Joints' change of speed, RMS (degrees/s2) | 3328 | 3023 | 1494 | 6020 | 4842 | 7054 | 8762 | 7086 | 10522 |
| Pelvis's path: effective harmonic | 3.69 | 1.92 | 1.88 | 2.86 | 2.05 | 2.61 | 2.84 | 2.13 | 2.59 |
| Head's path: effective harmonic | 3.70 | 1.93 | 1.92 | 2.84 | 2.04 | 2.66 | 2.84 | 2.12 | 2.72 |
| Pelvis's acceleration, RMS (m/s2) | 4.95 | 4.10 | 1.72 | 12.5 | 9.0 | 18.3 | 18.1 | 10.7 | 20.8 |
| Hand's acceleration, RMS (m/s2, left) | 13.2 | 12.5 | 3.5 | 28.2 | 27.6 | 30.3 | 57.5 | 54.9 | 33.3 |
| Forearm and hand trail by (frames) | 1.4, 1.4 | 1.4, 1.4 | 0.2, 2.2 | 0.8, 0.9 | 1.4, 1.6 | 1.6, none | 0.9, 0.9 | 1.2, 1.4 | 0.3, 0.1 |

By these numbers the walk was rougher than the library's where an eye rests (the pelvis and the head), and the runs
were not rougher than the library's runs before the pass; the pass took the same faults out of all three. The rows
of the tables above this section were measured before it. The walk's pass was made on B, the pick at the time;
when the pick became A the same three numbers went into A's walk, with its own limit (27 degrees: its cycle is
two frames shorter), and B keeps its pass.

What was choppy, and what changed (all in `clips/gait.py` and the picks' style sections; the other variants build
to the same bytes as before):

- **The trunk and the head jolted as each foot left the floor.** The pelvis was moved on every frame until the
  centre of mass was exactly on its path, so a foot flicked off the floor threw the hips the other way: the walk's
  pelvis went 14 mm forward and back in two frames, twice a cycle, and the head with it (the library's pelvis does
  not move fore and aft at all). `pelvis_waves` (3) lets the pelvis answer the limbs with three waves a cycle at
  most: the centre of mass keeps its path (a run's free fall is off its arc by 1.5 mm at most) and the fast part of
  what the legs do is no longer passed up the spine.
- **The foot was flicked off the floor.** `swing_early` gave the foot a share of its speed on its first frame in
  the air (79 mm a frame from nothing in the walk; the calf's speed changed 37 degrees in that frame, 73 in the
  sprint). The picks leave the floor from rest and their acceleration grows from nothing and ends in nothing
  (`swing_ease` 1, `swing_early` 0); each declares a tighter `speed_limit` (27, 36 and 45 degrees) so a rebuild
  cannot bring the flick back.
- **The runs' arms and head moved nearly with the trunk** (forearm and hand under a frame late, where the feel asks
  for one to two). The jog's and the sprint's chest, head, forearm and hand trail further (`overlap_jog`,
  `overlap_sprint`), and the trunk gives 2 degrees as each foot takes the weight (`lean_live`). The sprint's forearm
  stops at 1.3 frames: at 1.6 the left hand was 4.4 mm inside the chest on the female.
- **Not the import.** The imported clips are within 0.013 degrees of the file's keys on every joint (compressed, 61
  tracks), and Godot plays straight lines between 30 keys a second for ours and for the library's alike.

What is left, and why: our cycles are shorter than the library's (26, 20 and 18 frames against 40, 28 and 20: a
person's cadence at the game's speeds), so each frame is a larger share of the motion, and a foot that holds the
floor at the game's speed has to swing faster than one that slides (the walk's joints change speed twice as hard as
the library's, by the square of the pace). Keys at 60 a second would halve each step; that doubles the file's key
bytes, over the 7 KB a second the import is held to, and is a budget decision, not a clip one.

## The jump: take-offs, the air and landings

Nine clip types, one description (`clips/jump.py`, kit #1161). `Jump_Start`, `Jump_Fall` and `Land_Soft` replace
`ual1/Jump_Start`, `ual1/Jump` and the fixed `Jump_Land`, which stay as their stand-ins. The other six are new
(the library has no take-off from a run, no rise or apex of their own, one landing depth and no landing into a run;
the kit's `docs/tools/blender/own-animation.md#audit-clips`) and no state plays them yet: the tree that picks them
is gdstudio #1371.

### How bodies jump and land (the research)

Read on 2026-11-12, before the landings were keyed; "opened" and "summary" as in the gaits' table.

| What | Finding | Source | What the clips do with it |
| --- | --- | --- | --- |
| A drop landing's knee | From 30 cm: the knee 23 degrees bent at contact, 88 to 94 at its deepest, 208 ms from contact to the deepest knee, 2.9 body weights at the peak. | [Norcross et al., 2013](https://pmc.ncbi.nlm.nih.gov/articles/PMC3867085) (opened) | `Land_Soft`: the knees from the fall's 41 and 55 to 84 and 87 at the deepest, frame 3 (100 ms: the game's own jump lands at 7.3 m/s, faster than a 30 cm drop's 2.4, and gives control back at 0.3 s). |
| Soft against stiff | From 40 cm: the knee 15 degrees at contact landing soft and 9.6 stiff, 55 and 37 degrees of travel, 1.63 and 2.60 body weights. | [Myers et al., 2011](https://pmc.ncbi.nlm.nih.gov/articles/PMC4167636) (opened) | The soft landing travels further than either (the fall is faster); the hard one goes deeper still and holds. |
| A deep landing | Soft landings flex the knee about 117 degrees, stiff ones 77, from 59 cm. | DeVita and Skelly, 1992 (summary) | `Land_Hard`: the knees to 115 and 109 (A), the weight down 0.36 m, for falls from 9 m/s. |
| The arms in a jump | An arm swing adds about 7 cm, or 12 to 38 %, to a jump's height. | Hara et al., 2008, and others (summary) | Every take-off swings the arms up over the whole rise (the left to 48 degrees forward, the right to 26, in A), each to its own height, the forearm and the hand each a little behind the part they hang from. |
| A take-off's joints | Not found in a source we could open. | | The legs finish their stretch by frame 2.5 with the toes pointed 50 and 44 degrees: a declared choice. |
| In the air | A body in the air is in free fall. | physics | The capsule carries the body on the controller's own arc; the clips hold the centre of mass at one place against the root (the build reads 0.1 to 9.6 mm off the arc). |

### How the jump is built

- **The game gives a take-off no frame on the floor.** The capsule leaves on the tick of the press at 6.25 m/s, so
  no take-off crouches first: at 0.2 m a frame the feet would be 0.2 to 0.4 m under the capsule. A take-off lasts
  the rise's 12 frames (`jump.RISE_FRAMES`): the legs and the trunk stretch in the first 5 to 7 and then drift with
  the rise's own loop, and the take-off ends on `Jump_Rise`'s first pose.
- **The arms float (kit #1369).** The arms swing up over the whole take-off, each part of the arm on its own eased
  window (`maths.smoother`, no step in its acceleration), the forearm and the hand 0.6 to 1 frame behind the part
  they hang from (`arms_lag`); the poses of the air keep their arms within about 10 degrees of each other, since
  the game blends between them in 0.15 s; a landing's arms start down a frame after the foot lands, reach their low
  pose 5 to 9 frames after the weight does and float back up. In a clip that plays once the overlap pass springs
  only the trunk and the head (`jump.TRUNK_PARTS`): along the arm its lags add up past the end of a short clip, and
  joining the next clip crushed the rest of the swing into three frames. Every arm joint is held under a bound read
  off the shipped gaits (`checks.check_arms`): no faster than the jog's same joint (`Land_To_Jog`, which ends in
  the jog's own swing seven frames after the floor: the sprint's), no sharper change of acceleration than the
  gaits' sharpest arm joint. The numbers before and after are in kit #1369.
- **The air is carried.** No footfall in its plan, the root's height over the floor declared per frame
  (`declared["carried"]`, `jump.arc()`), the centre of mass held to the root. The rise, the apex and the fall are
  loops of 36 to 40 frames that drift 2 to 4 degrees, for a blend by vertical speed.
- **The fall stands on the capsule's bottom.** The first foot's ball is on it (`jump.FEET`), so a landing begins
  with that foot on the floor; the knees are what the weight's height leaves (41 and 55 degrees, more bent than a
  person's before a landing).
- **A landing is a curve of the weight's height.** From the fall's speed, of which the body keeps 4 m/s (`keep`),
  to the bottom (`dip`, `bottom`), then up on a push and a coast; `jump.standing_spec` lowers the pelvis where a
  folded trunk would ask the legs past their length. The right foot lands a frame or two after the left, ahead, and
  is drawn back while the knees are still bent.
- **Joins.** `Jump_Start` begins on the idle; `Jump_Start_Run_L` and `_R` on the jog's frame 0 and frame 10 at
  4 m/s; every landing on the picked fall; `Land_To_Jog` ends on the jog's frame 10 at the jog's speed. Variants of a
  transition join the picked poses, as the stance changes do.

### The jump's variants

| Type | A, grounded (shipped) | B, loose | C, sharp |
| --- | --- | --- | --- |
| `Jump_Start` | 12 frames, the legs' push 6, the left arm up to 48 degrees, the right to 26 | a push of 7, the arms wider, the chest arched 10 back | a push of 5, the legs straight by frame 1.8 |
| `Jump_Start_Run_L` | 12 frames, a push of 6, the struck leg sweeps 6 cm back, the right knee driven 5 cm up | a push of 7, 7 cm of drive, the arm pumped 4 degrees | a push of 5, 4 cm, the arm pumped 3 |
| `Jump_Start_Run_R` | 12 frames, a push of 6, the struck leg drawn up into the rise's leading knee | a push of 7, 4 cm of drive and trail | a push of 5, 2 cm |
| `Jump_Rise` | stretched, the right thigh 24 forward, the arms 48 and 26 degrees forward | the arms 56 and 34 forward and wider out, a 1.6 times wider drift | the left arm 56 forward, the right fist at the hip |
| `Jump_Apex` | gathered, the thighs 30 and 58 forward, the knees 70 and 96 | a wider gather, the thighs 11 and 14 out | a tight tuck, the knees 88 and 112 |
| `Jump_Fall` | the right foot 0.14 m ahead and 55 mm up, the arms out at 36 and 48 | the right foot 0.18 m ahead, turned out 20 | the feet 0.11 m apart, the elbows bent 46 and 58 |
| `Land_Soft` | down 0.20 m in 3 frames, control at 9, 22 frames | down 0.24 m, 25 frames, the chest folds 38 | down 0.16 m in 2 frames, 19 frames |
| `Land_Hard` | down 0.36 m in 5 frames, held 3, control at 20 of 38 | 42 frames, held 4, down 0.32 m | 33 frames, held 2, control at 17 |
| `Land_To_Jog` | 8 frames, the left foot down for 4, then the jog's own flight | sinks 7 cm more, keeps 3.8 m/s | no extra sink, keeps 2.4 m/s |

What each tried and could not do is in the style files' notes and on the review sheets.

### Numbers for the code (the jump)

| Clip | Frames | `clips.json` |
| --- | --- | --- |
| `Jump_Start` | 12 (0.4 s, `jump_rise_time`) | `carried`, `made_for` (`jump_height` 1.25, `jump_rise_time` 0.4, `fall_gravity_scale` 1.35) |
| `Jump_Start_Run_L`, `_R` | 12 | `speed` 4.0, `joins.first_frame` 0 and 10, `carried`, `made_for` |
| `Jump_Rise`, `Jump_Apex`, `Jump_Fall` | 36, loops | `carried`, no contacts |
| `Land_Soft` | 22 | `fall_speed` 4.5 to 9 m/s, `control` 9 (0.3 s, the game's `land_time`), `lowest` at 3 |
| `Land_Hard` | 38 | `fall_speed` from 9, `control` 20, `lowest` at 5 |
| `Land_To_Jog` | 8 | `speed` 4.0, `fall_speed` 4.5 to 9, `joins.last_frame` 10 |

- **Cost (A, as shipped, since kit #1369):** up to 61 tracks each (40 to 56 bones move, plus the 5 places); keys
  kept of every frame 39 to 58 % in the 12-frame take-offs and 81 % in `Land_To_Jog` (short and fast), 12 to 13 % in
  the air's loops, 32 and 22 % in the landings; key bytes 10.4 to 11.4 KB for a take-off, 15.6 to 19.9 KB a loop,
  17.4 and 23.5 KB for the landings. The import stays inside the budget (`test_own_clips.gd`).

## The directions and the lean

Kit #1159. `Walk_Back`, `Walk_Left`, `Walk_Right`, `Jog_Back`, `Jog_Left`, `Jog_Right` and the poses `Lean_Left`,
`Lean_Right`, `Lean_Fwd`, `Lean_Back` with their reference `Lean_Ref`. **None of them is in Quaternius's library**
(its Standard files have no strafe, no backpedal and no lean pose), and the game plays none of them yet: while it
aims, the character moves any way under the forward walk. The tree that plays them is kit #1158.

### How people go backward, sideways and lean (the research)

Read on 2026-11-12, before the numbers were set. "Opened" means the page itself was read; "summary" means only a
search's summary of it was, so the number is a lead; where nothing was found it says so and the clip's number is a
declared choice.

| What | Finding | Source | What the clips do with it |
| --- | --- | --- | --- |
| A backward walk against a forward one | Slower, on shorter steps, with a longer share of the cycle on the ground (one study of healthy adults found the stance share the same); the hip's and the knee's angles are close to a forward walk's played backward, the ankle's are not. | [a review of backward walking](https://pmc.ncbi.nlm.nih.gov/articles/PMC7359031) and [Winter, Pluck and Yang, 1989](https://scilit.com/publications/0c32bde682b1fc8cafec495df210671b) (both summary) | `Walk_Back` is 1.3 m/s on the forward walk's 26 frames: 0.56 m steps where the forward walk takes 0.74, a foot down 16 frames of 26 (62 %, the forward walk's 58). The foot reaches back toes first and the heel comes down under the weight. |
| Which part of the foot leaves last, walking backward | Not found in a source we could open. | | The sole is lifted whole. A heel that left last with the toes up (the forward walk reversed) raised the ball of the foot 20 mm inside its declared contact. |
| A backward run against a forward one | Thirty runners flat out backward: 5.1 m/s (70 % of their forward 7.3), 2.50 m strides at 124 strides a minute where the same speed forward took 3.60 m at 86, a foot down 31 % of the stride against 27 %, the hip through 42 degrees against 63 and the knee through 83 against 119. At one speed the step is about 11 % quicker backward. | [Arata, kinematic comparison of high speed backward and forward running](https://pages.uoregon.edu/btbates/backward/alan2.htm) (opened); [a treadmill study](https://oasis.library.unlv.edu/ahs_fac_articles/329) (summary) | `Jog_Back` is 3.0 m/s on the forward jog's 20 frames (2.0 m strides, 90 a minute), a foot down 7 frames (35 %), landing and leaving on the ball of the foot, the knee through 71 degrees, the hips low and the trunk 9 degrees over the toes. At the game's 4.0 m/s the tree plays it a third faster, which is the quicker step the studies find. |
| Which part of the foot a backward runner lands on | Not found in a source we could open. | | The ball, the heel 20 degrees up and never fully down: a declared choice from how a backpedal looks. |
| Sideways steps | The leading leg steps out and the trailing leg is drawn in past the middle; the two legs do different work (one makes the vertical push, the other takes the shock); step length and step rate rise with speed and the share on the ground falls. | [forward and sideways walking, 2023](https://www.nature.com/articles/s41598-023-34369-4.pdf), [Kuntze et al., 2009](https://www.jssm.org/jssm-08-1.xml-abst), a paper on lateral walking found only as a library record (all summary) | A strafe's two steps are not alike: a long open step of the leading foot and a short crossed step of the trailing one (0.72 and 0.32 m in the grounded walk). |
| Shuffle or crossover | Badminton players were measured in sidesteps and in crossover steps at a set 3 m/s; coaching texts keep the shuffle for a few steps and cross the legs to cover ground. No measured top speed of either was found. | Kuntze et al. above; coaching pages (summary) | The strafes cross: at 1.2 m/s with the forward walk's cadence the trailing foot would have to stand 0.6 m behind the body to stay behind the leading one. `Jog_Left` and `Jog_Right` are 3.0 m/s, the speed the study set. |
| How far the hips turn in a crossover | Not found in a source we could open. | | A third toward the step (26 to 34 degrees), as the issue asks; the chest turns back to 6 to 10 and the head looks ahead. |
| The lean | A body that changes speed leans by `atan(a / g)` (the kit's `docs/tools/blender/own-animation.md#feel`). People held leaning from the ankles could hold 14.9 degrees (SD 1.4) with the ankle muscles alone, and recover from 5.9 when let go at once. | [balance recovery with the ankle strategy](https://scilit.com/publications/0ffaaa3069df809a25d6fdf066116130) (summary) | The full poses are 8 to 12 degrees of the centre of mass off the upright, inside what the ankles hold; the tree scales them by the acceleration and may go past the full pose. |
| Side to side | Fore and aft balance is the ankles' alone; side to side the hips take part. | [Winter et al., 1996](https://edisciplinas.usp.br/pluginfile.php/5245117/mod_resource/content/1/winter_1996JNP.pdf) (summary) | A side lean tips the pelvis (5.5 to 9 degrees) and bends the inner knee; a forward one keeps the legs as they stand and turns at the ankles (16 degrees). |

### How the directions are built

One description, `clips/directed.py`: the gait of `clips/gait.py` (footfalls first, the centre of mass as the
input, the pelvis and the knees solved, the feet set down on both of the template's bodies) travelling `heading`
degrees to the left of the way the body faces, with a table of numbers per clip.

- **In step with the forward gaits.** The cycle is the shipped `Walk`'s (26 frames) or `Jog`'s (20), the left foot
  lands at frame 0 and the right at half the cycle in all six, so the tree can blend a direction with the forward
  gait in step. The steps are shorter, so each clip has its own speed, in `locomotion.json` with its `heading` and
  the gait it is `in_step_with`.
- **A backpedal lands on the ball of the foot** and the heel comes down under the weight. The walk lifts its sole
  whole; the run leaves over the ball, with the hips low and the trunk over the toes. Each arm swings with the
  other side's leg, as forward.
- **A strafe turns the hips a third toward the step and passes its feet in two lanes.** The leading foot's lane
  is 0.12 m behind the root's path and the crossing foot's 0.12 m ahead of it, so the crossing leg swings across
  in front. The swinging foot goes 5 cm further out as it passes the planted one (`pass_wide`), and the knees pass
  apart: the leading knee points on toward the step and the crossing knee ahead (`knee_turn`). With one turn for
  both legs the thighs met by 50 mm as the crossing foot landed, and in two straight lanes 0.2 m apart a foot went
  36 mm through the other.
- **A left strafe is not a right strafe flipped.** Each has its own table: to the left the hips turn 30 degrees
  (34 in the jog) and the chest 9, to the right 26 (29) and 6; the right strafe opens wider and crosses less
  (0.77 and 0.27 m against 0.72 and 0.32); the lanes, the feet's turns, the arms and the hands differ, and the
  right arm, which carries the weapon, is held tighter in both. Flipped onto each other the two walks differ by 4
  degrees at the hips, 42 mm at a foot and 17 mm in a hand's height (`tests/gameplay/test_own_directions.gd`).
- **The fingers hold their curl.** These gaits play while the character aims, with a weapon in its hands whose
  hold poses the fingers. Thirty finger tracks that opened and closed 3 degrees were a quarter to a third of a
  clip's key bytes, and with them the library file imported at 6.2 KB a second, over the 6 the test holds it to.

### How the lean poses are built

`clips/lean.py`. `Lean_Ref` is the shipped standing idle's first frame with the arms carried by the chest. A lean
pose is that reference with the centre of mass moved a number of degrees off the upright, measured from the floor
point the reference's weight is over, both soles flat where they stand: the pelvis is solved from it, so the ankles
take what the trunk does not. The pelvis, the chest and the head each lean by a share of those degrees, and each
upper arm keeps hanging along the body's line with its hand off its thigh. Everything else is the reference's, so
the difference between a lean pose and `Lean_Ref` moves only the pelvis, the spine, the neck, the head, the legs
and the upper arms.

In Godot the template's tree (`GaitLean`, kit #1158) adds `Lean_X - Idle` (the idle's first frame) over the
locomotion (`AnimationNodeSub2` into `AnimationNodeAdd2`), weighted by the body's acceleration over
`lean_full_at`. `Lean_Ref` is the idle's first frame within 0.3 degrees a bone, so the difference is the one the
poses were built as. Over the reference at full weight it gives the lean pose back within 0.06 degrees a bone, both
soles within 0.7 mm of the floor on both of the template's bodies; on the player, standing, the head goes 210 to
330 mm the pose's way and the feet and the `ik_` targets stay within 0.1 mm of where they were on their limbs
(`test_own_directions.gd`). The poses key the `ik_` targets where their hands and feet are: a pose without them
would pull each target back toward its rest by the idle's offset. Over a gait the legs' share of the lean moves
the feet, which a foot placement would have to hold; the tree has none yet.

### The variants of the directions and the lean

Measured by the build on `form_female` (and `form_male` where two numbers are given); the review sheets print the
whole tables.

| Strafes | A, grounded | B, loose | C, sharp |
| --- | --- | --- | --- |
| The hips turn toward the step: `Walk_Left`, `Walk_Right`, `Jog_Left`, `Jog_Right` | 30, 26, 34, 29 degrees | 36, 32, 40, 35 | 22, 19, 26, 22 |
| The open step and the crossed one, `Walk_Left` | 0.72 and 0.32 m | 0.66 and 0.38 | 0.77 and 0.27 |
| The same, `Jog_Left` (with a flight between) | 1.31 and 0.69 m | 1.26 and 0.74 | 1.34 and 0.66 |
| The chest leans into the step, walk and jog | 2 and 4 degrees | 3.5 and 6 | 1 and 2.5 |
| Pelvis up and down, walk and jog | 30 and 70 mm | 36 and 70 | 31 and 77 |
| Forearm and chest trail, walk | 1.7 and 1.4 frames | 2.2 and 2.4 | 1.1 and 0.8 |
| Limbs inside limbs, the four bodies, worst of the four clips | 0.9, 3.1, 0, 2.6 mm | 0.4, 2.9, 0, 0 (4.6 before `width`, below) | 0.5, 2.7, 0, 2.6 |
| A planted sole wanders, `form_female` and `form_male` | 1.8 and 1.7 mm | 1.8 and 1.7 | 1.8 and 1.8 |
| Joints' effective harmonic, walk and jog (the shipped `Walk` 3.17, `Jog` 2.37) | 2.8 and 2.0 | 2.5 and 2.0 | 2.8 and 2.1 |

| Backpedals | A, grounded | B, loose | C, sharp |
| --- | --- | --- | --- |
| `Walk_Back`: the heel up as the ball lands, and the roll down | 16 degrees, 4.5 frames | 20, 4.5 | 22, 3.5 |
| Hips turn and tip, trunk leans | 6 and 5, 2 degrees | 10 and 8, 3 | 4 and 3.6, 1 |
| Pelvis up and down | 32 mm | 39 | 26 |
| Forearm and chest trail | 1.4 and 1.5 frames | 2.0 and 2.4 | 0.9 and 0.9 |
| `Jog_Back`: pelvis up and down, trunk leans | 52 mm, 9 degrees | 61, 11 | 50, 7 |
| The foot's lift in the swing | 0.05 m | 0.05 | 0.08 |
| Off a free fall's arc in the air | 0.0 mm | 0.0 | 0.0 |
| Limbs inside limbs, the four bodies, worst of the two clips | 0, 1.7, 0, 0 mm | 0, 2.3, 0, 0 | 0, 1.7, 0, 0 |
| Joints' effective harmonic, walk and jog | 3.0 and 1.9 | 2.6 and 1.8 | 3.3 and 2.0 |

| Leans | A, grounded | B, loose | C, sharp |
| --- | --- | --- | --- |
| The vision | the trunk bends a little more than the legs lean, the head half follows | the hips stay, the chest and the head go: a curve | a plank from the ankles, the head level |
| `Lean_Left` (10 degrees): pelvis, chest, head | 5.5, 11, 3.5 degrees | 4, 17, 10 | 9.5, 10, 0 |
| `Lean_Right` (10 degrees) | 9, 6, 2 | 6, 13, 9 | 10.5, 8.5, 1.5 |
| `Lean_Fwd` (12 degrees) | 9.6, 15.6, 6 | 6, 21.6, 12 | 12, 12.6, 2.4 |
| `Lean_Back` (8 degrees) | 4, 9.6, 1.6 | 2.4, 13.6, 6.4 | 7.2, 8, 0 |
| A planted sole off the floor, `form_female`, `form_male`, the Quaternius male | 0.0, 0.6, 0.7 mm at most | 0.0, 0.5, 0.6 | 0.0, 0.7, 0.8 |
| Limbs inside limbs, the four bodies, worst of the four poses | 0, 3.9, 0, 0 mm | 0, 4.7, 0, 0 | 0, 2.0, 0, 0 |

**The maintainer picked B for the strafes and the backpedals and A for the leans** (2026-11-12, `picks.json`).
B's `Walk_Right` and `Jog_Left` set their feet 0.02 m off the middle line along the step (`width`): at 0,
`form_male`'s thighs met by 4.6 and 3.5 mm, over the 3.5 that `test_own_directions.gd` holds a strafe's legs to (A
read 2.8 and 2.6); now 2.7 and 2.9. On `form_male` the legs read 1.5 to 2.9 mm in the shipped directions, thigh in
thigh: his thighs meet by 2 mm in his rest pose and by 3.8 in the shipped `Jog`.

### What the numbers do not say (the directions and the lean)

- **The crossing knee is not turned a third toward the step.** The toes are (17 to 21 degrees for the crossing
  foot, 39 to 43 for the leading one), the leading knee is, and the crossing knee points ahead (-1 to 7 degrees):
  it has to pass in front of the other knee.
- **Nothing plays them yet.** The captures show the variants in place on the game's map; whether a strafe blends
  cleanly with the forward walk at 45 degrees is the tree's to prove (kit #1158).
- **The speeds are not the game's.** Aiming moves the character at 1.0 to 1.5 m/s and a run at 4.0; the clips are
  1.2, 1.3 and 3.0 m/s on the forward gaits' cycles, and the tree plays each at ground speed over clip speed.
- **The gait checks read a strafe in two planes**: its legs along the way it travels, its arms across the way its
  hips face, and its legs' phase where the soles land (`declared["legs_facing"]`, `facing`, `legs_by_landing`).
  The audit's forward-plane rows (thigh swing, arm with the other side's leg) are left off these sheets.

### Numbers for the code (the directions and the lean)

| | `Walk_Back` | `Walk_Left`, `Walk_Right` | `Jog_Back` | `Jog_Left`, `Jog_Right` |
| --- | --- | --- | --- | --- |
| Frames, seconds | 26, 0.867 | 26, 0.867 | 20, 0.667 | 20, 0.667 |
| `speed`, `heading` | 1.3 m/s, 180 | 1.2 m/s, 90 and -90 | 3.0 m/s, 180 | 3.0 m/s, 90 and -90 |
| `in_step_with` | `Walk` | `Walk` | `Jog` | `Jog` |
| Left foot down (frames), right foot lands | 0 to 16, 13 | 0 to 15, 13 | 0 to 7, 10 | 0 to 6, 10 |
| `flat` (the sole at rest), left | 4.5 to 12.5 | 3 to 9 | 2.5 to 4.5 | 1.5 to 3 |
| Key bytes in the file | 12.3 KB | 12.8, 12.9 | 10.9 | 10.9, 11.0 |

- `travel` in `locomotion.json` is `[frame, forward, left]`: a backpedal's forward is negative, a strafe's left is
  its travel (negative to the right).
- A lean pose's record has `pose` (true), `lean` (`way`, degrees to the left of ahead, and `degrees`, the lean the
  full pose is) and `reference` (`Lean_Ref`). The weight of a lean is the lean wanted over `degrees`. Each pose is
  two keys a bone on 52 bones and the four `ik_` targets, 1.9 KB in the file.
- **Imported size:** 166 KB for the nineteen clips, 29.7 s, with Godot's compression pages at 32 KiB: 5.58 KB a
  second against the 6 the test holds the file to (174 KB and 5.86 at 8 KiB pages; 130 KB and 5.3 before these
  clips, 6.2 with the directions' fingers keyed). The next short loops will need the budget looked at: a file of
  short fast loops and held poses has few seconds to spread its keys over.
- **The import keeps every key at either page size** for these clips: each bone's place within 0.01 mm and turn
  within 0.07 degrees of the file, at 8 KiB pages and at 32 (`test_own_directions.gd`,
  `test_the_import_keeps_the_directions_and_the_leans`). The file imports at 32 since kit #1161's landing clips
  lost keys at 8.
- **The `ik_` targets are set from the finished pose** (`build.retarget`, the same change as kit #1156 and #1161)
  and checked on every frame (`checks.check_targets`, 4 mm): the directions' targets are within 0.13 to 0.79 mm
  of their limbs' ends in every variant. Every review file and the shipped file were rebuilt; the lean poses key
  no target and are unchanged, and only the targets' keys moved in the others.

## The starts and the stops: `Idle_To_Walk`, `Idle_To_Jog`, `Idle_To_Sprint`, `Walk_Stop`, `Jog_Stop`, `Sprint_Stop`

Kit #1156. All new: Quaternius's library has no start and no stop, and the game cross-faded for 0.15 s between the
idle and a gait, poses 436 to 685 mm apart. Each type is two clips, `_L` and `_R`: a start is named for the foot
that steps off first, a stop for the foot that strikes as it begins. All twelve are one description,
`clips/moves.py`, and each type is a family in `build_own.py` (`FAMILIES`): `review idle_to_walk` builds both feet
under every letter, and one letter of `picks.json` picks the pair.

### How a body starts and stops (the research)

Read on 2026-11-12, before the numbers were set. "Summary" means only a search's summary of the page was read, so
the finding is a lead; "computed" is our own arithmetic from the physics named; where nothing was found it says so
and the clip's number is a declared choice.

| What | Finding | Source | What the clips do with it |
| --- | --- | --- | --- |
| Before the first step | A standing person who starts to walk first moves the point the feet press on backward and toward the foot that will swing, which tips the body forward and onto the other leg; the further back it goes, the faster the body is moving as the first foot lands. Then that foot is unloaded, then it steps. | [Postural organization of gait initiation](https://www.jove.com/t/64088/postural-organization-gait-initiation-for-biomechanical-analysis); [Brenière and Do's line of work, in a study of children](https://research.vu.nl/en/publications/the-build-up-of-anticipatory-behavior-an-analysis-of-gait-initiat/) (both summary) | A start gathers for 7 to 10 frames before a foot leaves (`prep`): the hips go over the standing foot (`shift`) and sink a little (`dip`), and the root does not move on the first frame. From the idle, which stands on its left leg, the right foot is free sooner: `_R` gathers three frames less and shifts 12 mm where `_L` shifts 50. |
| How fast a standing body can speed up | Not found as a number in a source we could open. Physics gives it: a body that stands can only fall forward over its feet, so its acceleration is `g / h` times the distance from where the feet press to the centre of mass. With the heels 0.10 m behind it and `h` 1.0 m that is 1 m/s2 at first; falling until the standing foot is 0.45 m behind takes 0.76 s and ends at 1.7 m/s, the walk's speed. | computed (an inverted pendulum) | The start's speed is that fall (`lever`, `push_most`), scaled until the gait's speed is reached two frames after the last landing but one. The scale (1.9 to 2.0 in the grounded walk start) is how much harder the clip pushes than a fall alone; the build's lean check reads what that costs. |
| When the gait's speed is reached | The speed at the end of the first step grows with the backward shift and the time spent on it; no page we could open said by which step a walk is steady. | the same pages (summary) | The walk is at speed as its second foot lands (two landings), the jog after three steps of four, the sprint after four of six: declared choices. |
| A sprinter's first steps | From a standing start, faster athletes have 11 to 13 % shorter contacts and about 9 % more steps a second over the first three steps; among world-class men the trunk's angle and the thighs' spread at the first take-off explain almost 90 % of how well the first contact speeds them up; short contacts go with a quick first four metres. | [Standing and Maulder, 2017](https://www.jssm.org/jssm-16-154.xml-Fulltext); [Walker et al., 2021](https://eprints.leedsbeckett.ac.uk/id/eprint/7810/1/KinematicFactorsAssociatedWithStartPerformanceInWorldClassMaleAM-WALKER.pdf) (both summary; neither page's table opened) | The run starts lean by their acceleration: the chest takes 60 % of `atan(a / g)` as pitch and the pelvis 30 %, the hips go ahead of the root and come down (`lean_fore`, `lean_low`) so the legs push from behind, the arms swing at the gait's size before the feet are the gait's (`arms`), and contacts shorten step by step to the gait's 4 or 6 frames (`air`). |
| How a person stops | To stop, the braking under the leading foot goes up and the push of the trailing foot goes down, over a step with both feet down before the last; a planned stop takes longer and brakes less hard than a sudden one; about 90 % of the speed has to go in the last step of a walk. | [Planned and unplanned gait termination, 2023](https://www.mdpi.com/2076-3417/13/12/7323/html); [Lower limb biomechanics of unplanned gait termination](https://www.jove.com/t/61558) (both summary) | A stop begins as a foot strikes and brakes from the second frame: the walk stops in two more landings (the other foot ahead on its standing place, then the first one closing beside it), the jog in four, the sprint in six, each brake step landing further ahead of the body than a steady step (up to 0.5 m). The last two landings are the idle's own places. |
| How many steps a run takes to stop | Not found in a source we could open. | | 0.48 m from a walk, 1.96 m from a jog and 4.82 m from a sprint in the grounded variant, braking at 3.5 to 5.4 m/s2 on average: declared choices. A body cannot lean back far enough to brake that hard without sliding, and the lean check says by how much (below). |
| After the stop | Not found as numbers. The plan asks that nothing stops on one frame. | `docs/tools/blender/own-animation.md#feel` | The root is at rest a few frames after the last landing but one (`halt`); the hips sink 20 to 50 mm as the legs take the stop and come back (`dip`); the lean follows the braking through a spring (`lean_lag`) and the chest, the head, the arms and the hands trail through the overlap pass, for 7 to 14 frames after the last landing (`settle`). |

### How the starts and stops are built

- **The root's speed and the footfalls are the inputs** (the kit's `docs/tools/blender/start-stop-clips.md#description`).
  `steps` is the frames from each landing to the next and `air` how long each foot outlasts the next landing (under
  0: a flight). A start's last two landings are the shipped gait's own contacts and its last frame is the gait's
  frame as a foot strikes (`joins.last_frame` in `locomotion.json`: 0 for the left foot, half the cycle for the
  right); a stop's first frame is the gait's frame as the foot it is named for strikes (`joins.first_frame`).
- **Every foot steps at least once.** The idle's feet stand 112 mm from the middle line and turned out 9 degrees;
  the walk's land 75 and 85 mm from it, turned out 4 and 10. A foot that stayed where the idle has it could not be
  the gait's contact within a millimetre, so the shortest start is two landings.
- **The clip's own steps** land where a steady step at the root's speed would, moved back (a start) or ahead (a
  stop) by `h * a / g`, no further than a leg reaches, and their foot numbers (heel strike, roll, the heel drawn up
  behind) are mixed from a slow step's to the gait's by `gait_like`. A foot that stays down while the body goes on
  over it lets its heel come up early (`heel_early`).
- **The body is the idle's, then the gait's.** The pelvis over the root, the trunk's wind, the arms and the hands
  are mixed from the shipped idle's first frame to the shipped gait's spec at the frame of its cycle the feet are
  in, on the windows `body` and `arms`. The arms open from the body in the middle of the change and while the hips
  are low (`arm_wide`).
- **The ends are the joined clips' own poses**, and a stop is solved with a cycle of the gait before its first
  frame (`Clip.lead`), so its arms and chest are trailing as the gait's are when it begins.
- **The feet are set down on the skin** of the template's two bodies frame by frame, as a gait's are, and the
  pelvis is lowered where a leg would be stretched past `stretch`.

### The starts' and stops' variants

A, grounded, takes the frames a body needs; B, loose, gathers longer, leans its trunk further and later and settles
longer; C, sharp, has fewer steps and shorter eases and pushes or brakes harder than a body can, which its lean
row shows. Measured by the build on `form_female` (frames are `_L`, `_R`):

| | A, grounded | B, loose | C, sharp |
| --- | --- | --- | --- |
| **`Idle_To_Walk`**: frames | 35, 32 | 38, 35 | 30, 27 |
| Seconds, metres travelled | 1.17 s, 1.14 m | 1.27 s, 1.23 m | 1.00 s, 1.03 m |
| Landings inside the clip | 1 | 1 | 1 |
| The frame the game may cut from (`free`) | 22, 19 | 25, 22 | 17, 14 |
| Lean off the acceleration's over a step, and its declared limit | 7.6 of 8 degrees | 5.9 of 9 degrees | 10.7 of 12 degrees |
| Fastest drop of the centre of mass with a foot down | 0.55 of gravity | 0.93 of gravity | 0.55 of gravity |
| A planted sole wanders, `form_female` and `form_male` | 2.56 and 2.7 mm | 2.56 and 2.71 mm | 2.56 and 2.71 mm |
| A planted sole off the floor, the same two | 0.4 and 0.4 mm | 0.4 and 0.4 mm | 0.4 and 0.5 mm |
| Limbs inside limbs, the worst of the four bodies | 2.1 mm | 2.1 mm | 2.1 mm |
| Largest change of a joint's speed in a frame | 23 degrees | 22 degrees | 19 degrees |
| First and last pose against the joined clips' | 0.0 mm, 0.09 degrees | 0.0 mm, 0.09 degrees | 0.0 mm, 0.09 degrees |
| Key bytes, the pair | 58 KB | 52 KB | 38 KB |
| **`Idle_To_Jog`**: frames | 44, 42 | 46, 44 | 31, 29 |
| Seconds, metres travelled | 1.47 s, 3.07 m | 1.53 s, 3.21 m | 1.03 s, 2.18 m |
| Landings inside the clip | 3 | 3 | 2 |
| The frame the game may cut from (`free`) | 34, 32 | 36, 34 | 21, 19 |
| Lean off the acceleration's over a step, and its declared limit | 10.5 of 12 degrees | 10.9 of 12 degrees | 21.5 of 23 degrees |
| Fastest drop of the centre of mass with a foot down | 0.86 of gravity | 0.85 of gravity | 0.83 of gravity |
| A planted sole wanders, `form_female` and `form_male` | 2.44 and 2.23 mm | 2.44 and 2.23 mm | 2.44 and 2.22 mm |
| A planted sole off the floor, the same two | 0.3 and 0.3 mm | 0.3 and 0.3 mm | 0.2 and 0.2 mm |
| Limbs inside limbs, the worst of the four bodies | 3.4 mm | 3.3 mm | 2.6 mm |
| Largest change of a joint's speed in a frame | 43 degrees | 45 degrees | 31 degrees |
| First and last pose against the joined clips' | 0.0 mm, 0.09 degrees | 0.0 mm, 0.09 degrees | 0.0 mm, 0.09 degrees |
| Key bytes, the pair | 79 KB | 84 KB | 56 KB |
| **`Idle_To_Sprint`**: frames | 58, 56 | 61, 59 | 47, 45 |
| Seconds, metres travelled | 1.93 s, 6.45 m | 2.03 s, 6.81 m | 1.57 s, 5.17 m |
| Landings inside the clip | 5 | 5 | 4 |
| The frame the game may cut from (`free`) | 49, 47 | 52, 50 | 38, 36 |
| Lean off the acceleration's over a step, and its declared limit | 15.1 of 20 degrees | 12.4 of 20 degrees | 25.5 of 28 degrees |
| Fastest drop of the centre of mass with a foot down | 0.89 of gravity | 0.81 of gravity | 0.89 of gravity |
| A planted sole wanders, `form_female` and `form_male` | 2.12 and 2.07 mm | 2.17 and 2.08 mm | 2.28 and 2.18 mm |
| A planted sole off the floor, the same two | 0.1 and 0.2 mm | 0.1 and 0.2 mm | 0.1 and 0.2 mm |
| Limbs inside limbs, the worst of the four bodies | 3.9 mm | 4.0 mm | 3.5 mm |
| Largest change of a joint's speed in a frame | 42 degrees | 42 degrees | 58 degrees |
| First and last pose against the joined clips' | 0.0 mm, 0.09 degrees | 0.0 mm, 0.09 degrees | 0.0 mm, 0.09 degrees |
| Key bytes, the pair | 106 KB | 114 KB | 87 KB |
| **`Walk_Stop`**: frames | 33 | 38 | 28 |
| Seconds, metres travelled | 1.10 s, 0.48 m | 1.27 s, 0.51 m | 0.93 s, 0.38 m |
| Landings inside the clip | 2 | 2 | 2 |
| The frame the game may cut from (`free`) | 23 | 24 | 21 |
| Lean off the acceleration's over a step, and its declared limit | 8.8 of 10 degrees | 9.5 of 10 degrees | 8.1 of 14 degrees |
| Fastest drop of the centre of mass with a foot down | 0.58 of gravity | 0.74 of gravity | 0.84 of gravity |
| A planted sole wanders, `form_female` and `form_male` | 2.56 and 2.78 mm | 2.56 and 2.78 mm | 2.56 and 2.76 mm |
| A planted sole off the floor, the same two | 0.4 and 0.4 mm | 0.4 and 0.4 mm | 0.4 and 0.4 mm |
| Limbs inside limbs, the worst of the four bodies | 2.1 mm | 2.1 mm | 2.1 mm |
| Largest change of a joint's speed in a frame | 23 degrees | 19 degrees | 26 degrees |
| First and last pose against the joined clips' | 0.0 mm, 0.09 degrees | 0.0 mm, 0.09 degrees | 0.0 mm, 0.09 degrees |
| Key bytes, the pair | 56 KB | 62 KB | 45 KB |
| **`Jog_Stop`**: frames | 50 | 54 | 37 |
| Seconds, metres travelled | 1.67 s, 1.96 m | 1.80 s, 2.08 m | 1.23 s, 1.37 m |
| Landings inside the clip | 4 | 4 | 3 |
| The frame the game may cut from (`free`) | 40 | 40 | 30 |
| Lean off the acceleration's over a step, and its declared limit | 15.2 of 17 degrees | 14.5 of 17 degrees | 23.7 of 24 degrees |
| Fastest drop of the centre of mass with a foot down | 0.73 of gravity | 0.72 of gravity | 0.54 of gravity |
| A planted sole wanders, `form_female` and `form_male` | 2.27 and 2.31 mm | 2.27 and 2.36 mm | 2.23 and 2.48 mm |
| A planted sole off the floor, the same two | 0.3 and 0.3 mm | 0.3 and 0.3 mm | 0.3 and 0.3 mm |
| Limbs inside limbs, the worst of the four bodies | 3.2 mm | 3.2 mm | 3.8 mm |
| Largest change of a joint's speed in a frame | 27 degrees | 27 degrees | 30 degrees |
| First and last pose against the joined clips' | 0.0 mm, 0.09 degrees | 0.0 mm, 0.09 degrees | 0.0 mm, 0.09 degrees |
| Key bytes, the pair | 93 KB | 99 KB | 70 KB |
| **`Sprint_Stop`**: frames | 67 | 71 | 55 |
| Seconds, metres travelled | 2.23 s, 4.82 m | 2.37 s, 5.01 m | 1.83 s, 3.95 m |
| Landings inside the clip | 6 | 6 | 5 |
| The frame the game may cut from (`free`) | 57 | 57 | 48 |
| Lean off the acceleration's over a step, and its declared limit | 15.0 of 16 degrees | 16.4 of 17 degrees | 17.5 of 22 degrees |
| Fastest drop of the centre of mass with a foot down | 0.58 of gravity | 0.6 of gravity | 0.59 of gravity |
| A planted sole wanders, `form_female` and `form_male` | 2.22 and 2.22 mm | 2.22 and 2.25 mm | 2.17 and 2.28 mm |
| A planted sole off the floor, the same two | 0.3 and 0.3 mm | 0.3 and 0.3 mm | 0.3 and 0.3 mm |
| Limbs inside limbs, the worst of the four bodies | 4.0 mm | 4.0 mm | 4.0 mm |
| Largest change of a joint's speed in a frame | 36 degrees | 36 degrees | 38 degrees |
| First and last pose against the joined clips' | 0.0 mm, 0.09 degrees | 0.0 mm, 0.09 degrees | 0.0 mm, 0.09 degrees |
| Key bytes, the pair | 120 KB | 130 KB | 99 KB |

**A is shipped for all six** (`picks.json`), as the recommendation until the maintainer picks a letter per type.

### What the starts' and stops' numbers do not say

- **The lean rows are over the 5 degrees of the plan in every run clip, and each variant declares its limit**
  (`lean_limit`). The row is how far the acceleration's lean is outside what the soles on the floor can hold,
  averaged over a step. To pass at 5 a jog start would take about 57 frames and a sprint stop over 3 s; the
  grounded clips are as long as we judged a game can wait, and C is shorter still.
- **A start does not reach the gait's cadence at once**: its first step is a slow one (a swing of 9 to 13 frames
  from a standing foot), and the walk's start is a whole second.
- **The clips are in place** and their travel is a curve in `locomotion.json`; the controller reaches its speed in
  under 0.25 s (28 m/s2) and stops in under 0.2 s. The tree (kit #1158, `GaitTransitions`) finds them by name
  (`GaitTransitionSet`: `gds/Idle_To_Walk` and the rest, `_L` or `_R`), plays each where its travel curve has
  covered the ground the body really covered, and hands a start over to the gait at its `end_foot` (`l` from 0,
  `r` from half the cycle, which is where each start ends). `tests/gameplay/test_own_moves.gd` holds that the
  player plays a walk start and a walk stop of ours.
- **The stops sit low** in the middle (the hips come down 5 to 11 cm in the sprint's) and the forearms are carried
  ahead of the body while the trunk comes back: the arms are mixed from the run's bent carriage to the idle's hang.

### Numbers for the code (the starts and stops)

- `joins` in `locomotion.json`: `{"first": "Idle", "last": "Walk", "last_frame": 13}` for a start, `{"first":
  "Walk", "first_frame": 0, "last": "Idle"}` for a stop. `Idle_To_Walk_L` ends as the right foot strikes (frame 13
  of `Walk`) and `_R` as the left does (frame 0); `Idle_To_Jog_L` and `Idle_To_Sprint_L` end on the other foot
  from their first (four and six landings), at frames 10 and 9, and their `_R` at 0. `Walk_Stop_L`, `Jog_Stop_L`
  and `Sprint_Stop_L` begin at frame 0 of their gait, the `_R` at half its cycle.
- `travel` is the root's curve (frame, metres forward, metres left), still on the idle's end and at the gait's
  speed on the gait's; `speed` is the clip's mean.
- `contacts` and `flat` are each foot's contacts as for a gait; a contact the clip begins inside starts at 0.
  `events` has a `footstep` per landing inside the clip and one `free`: from that frame the game may cut to new
  input (a start is on the gait's own feet from its last landing but one; a stop has only its settle left after
  its last landing).
- **Cost:** each start or stop keys the same tracks as the gaits (56 bones' rotations, the places of the pelvis and
  the four `ik_` targets). The library imports to 289,356 bytes for 43.7 s of clips at 32 KiB compression pages (6.6
  KB a second, inside the plan's budget of 7, which the maintainer set on 2026-11-13). Godot bakes a key a frame
  on import, so the build's key reduction does not make the import smaller; leaving the hands' `ik_` targets out of
  the twelve clips gave 275,564 bytes (6.3 KB a second).
