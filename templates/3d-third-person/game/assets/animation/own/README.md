# GDStudio's own clips

Clips made by GDStudio, by script, that replace the Universal Animation Library's one clip type at a time (the plan:
the kit's `docs/tools/blender/own-animation.md`; how to use the toolkit: `docs/tools/blender/animation.md#toolkit`).
Nothing here is copied from a library clip or from another game: a clip is a description that `gdsanim/` solves.

| File | What it is |
| --- | --- |
| `locomotion.glb`, `locomotion.json` | The shipped clips and what the game needs to know of each (`clips.json` of the plan): loop, length, speed, travel and turn curves, contact times per foot, the foot it starts and ends on, events. Godot imports the glb as an `AnimationLibrary`; the player's `AnimationPlayer` holds it as `gds`, so the clip is `gds/Idle`. |
| `picks.json` | Which variant each shipped clip is built from (`"Idle": "A"`). |
| `clips/<type>.py` | A clip type's description, with every number a style may set and what it means. |
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
game's camera is `tools/capture/own_clips_review.tscn`; the Godot test is `tests/gameplay/test_own_clips.gd`.

The clip types are `idle`, `crouch_idle`, `crouch_walk`, `stand_to_crouch` and `crouch_to_stand`. After `ship
locomotion` changes `Crouch_Idle`, rebuild the prone clips too (`../prone/`): their two transitions join its first
pose.

**Picking another variant:** set the letter in `picks.json`, run `ship locomotion`, run the test. The other styles
stay here, so a game picks another vision by rebuilding, or writes a `style_d.json` of its own.

## Idle

Replaces `ual1/Idle`, which stays in the game as its stand-in (`CharacterClips.STAND_INS`). The library's idle
breathes and nothing else: 17 bones move, the pelvis 8.5 mm, no weight shift, no finger moves, its seam is 3 mm open
and its hand is 17 mm inside the thigh on the female mannequin.

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
  curled fingers' tips are 127 mm from the thigh's line on both mannequins: the female's hip is 100 mm wide of the
  joint, and curled fingers reach 45 mm inward of their knuckles.
- **Overlap.** The chest, the head, the upper arms, the forearms and the hands each follow the part they hang from
  through a spring with the style's lag and overshoot, run round the loop until its seam closes.

### The three variants

Measured by `../audit_clips.py` on the female mannequin (the review sheet prints the same table):

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
- Imported with Godot's key optimizer off and track compression on: 39 KB for the 10 s clip (3.9 KB a second),
  and a planted foot's joints stay within 1 mm (`tests/gameplay/test_own_clips.gd`).
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
| How long a drop takes | No study with a time was found. Physics gives the floor: a body with a foot down cannot fall faster than gravity, and the centre of mass goes down 0.45 m, which a free fall takes 0.30 s over (9 frames) before any braking. | computed | 15 frames is the shortest drop here that stays under gravity (0.97 of it); the build fails one that does not (`checks.FALL`). The controller's `crouch_time` is 0.2 s (6 frames), which no drop of this depth fits. |
| The capsule | `CharacterTuning.crouch_height` is 1.1 m for a body 1.80 m tall. | the template | Every frame of the crouch idle and walk is under 1.1 m on both mannequins (the taller reaches 1.092 and 1.0971 m; the library's walk reaches 1.127 m), which is what folds the trunk 78 degrees. |

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
  thigh's and shin's on both mannequins, measured at each body's own joints, on every frame, so it stays there
  while the chest breathes and the weight moves; that arm is left out of the overlap pass. The right arm hangs
  24 degrees out from the body and keeps its hand 100 mm from its thigh's line, which is what keeps a pistol held
  in that hand out of the leg on both mannequins (`tests/gameplay/test_pistol_clearance.gd`).
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
  `Clip.meet` makes the ends the idles' first poses to the bit (0.0 mm and 0.09 degrees in the build's check,
  which reads 32-bit keys).

### The variants

Three stances, not one stance at three tempos. Measured on the female mannequin at the first frame by the build and
`../audit_clips.py` (the review sheets print the audit's tables).

| `Crouch_Idle` | A, grounded | B, loose | C, sharp | `ual1/Crouch_Idle` |
| --- | --- | --- | --- | --- |
| The right foot behind the left, and the feet apart | 0.53 m, 0.28 m | 0.65 m, 0.33 m | 0.41 m, 0.26 m | 0.68 m, 0.39 m |
| The feet turned out, left and right | 9, 26 degrees | 9, 35 | 9, 18 | 3, 21 |
| The right heel up | 46 degrees | 54 | 38 | 51 |
| Knees off the floor, left and right | 0.50, 0.25 m | 0.51, 0.26 m | 0.50, 0.36 m | 0.53, 0.27 m |
| Hips turned, and the right hip lower by | 12, 5 degrees | 18, 8 | 7, 3 | 3, and the left lower by 13 |
| Shoulders turned the other way | 11 degrees | 17 | 6 | 1 |
| The trunk folds, the head looks down | 78, 22 degrees | 84, 26 | 76, 20 | 80, 39 |
| The left arm | forearm on the left thigh, elbow 57 degrees, the hand drooping inside the knee | the same, the hand drooping further | the same, the fingers closed further | hangs outside the knee, elbow 47 |
| The right arm | hangs 24 degrees out from the body, outside the low knee, elbow 17 degrees, wrist 0.39 m up | the hand lies on the low knee, elbow 45, wrist 0.39 m up | bent 63 degrees, the hand held outside the knee at 0.43 m | held ahead of the knee, elbow 75 |
| Length | 8 s | 10.7 s | 8 s | 2.9 s |
| Pelvis side to side, hips turn, head turns | 33 mm, 3, 7 degrees | 34 mm, 6, 14 | 19 mm, 3, 29 (looks, holds, looks back) | 6 mm, 1, 4 |
| Highest vertex, female and male | 1.068, 1.092 m | 1.065, 1.089 | 1.062, 1.086 | 1.045 on the female |
| Limbs inside limbs, female and male | 0, 0 mm | 0, 3.9 | 0, 0 | none |

| `Crouch_Walk` | A, grounded | B, loose | C, sharp | `ual1/Crouch_Fwd` |
| --- | --- | --- | --- | --- |
| Stride | 22 frames | 24 | 20 | 60 |
| Steps a minute | 164 | 150 | 180 | 60 |
| Planted sole speed | 1.51 m/s | 1.51 | 1.51 | 0.46 (0.04 to 0.96) |
| A planted sole wanders (the build's measure) | 4.5 mm | 5.0 | 4.3 | 574 |
| Pelvis up and down | 16 mm | 24 | 8 | 61 |
| The trunk's turn the walk keeps, hips and shoulders | 6, 4 degrees | 6, 4 | 6, 4 | 8, 10, held still |
| The feet turned out, left and right; the right tracks wider by | 4, 11 degrees; 18 mm | the same | the same | 3, 3 at landing |
| The arms swing, left and right | 10, 18 degrees | 13, 22 | 7, 13 | the arms hold still |
| The elbows, left and right | 74, 36 degrees | the same | the same | 47, 75 |
| Arm with the other side's leg | 0.80 and 0.84 | 0.79 and 0.85 | 0.79 and 0.83 | none |
| Highest vertex on the male | 1.0970 m | 1.0963 | 1.0971 | 1.127 on the female |
| Limbs inside limbs, both bodies | 0 mm | 0 | 0 | none |

| Stance changes | A, grounded | B, loose | C, sharp |
| --- | --- | --- | --- |
| `Stand_To_Crouch` | 16 frames, 0.91 of gravity; the right foot in the air from frame 3 to 10 | 20 frames, 0.59; 4 to 13 | 15 frames, 0.97; 3 to 10 |
| `Crouch_To_Stand` | 16 frames, stops at 0.96 of gravity; the right foot in the air from frame 6 to 14 | 20 frames, 0.54; 7 to 16 | 15 frames, 1.05; 4.5 to 12 |
| First and last pose against the idles' | 0.0 mm, 0.09 degrees | the same | the same |
| A planted sole wanders | 3.2 and 2.8 mm | 3.2 and 2.8 | 3.0 and 2.8 |
| Limbs inside limbs, female and male | 3.1, 0 mm going down; 0 coming up | 3.4, 0; 0 | 0, 0; 0 |

**A is shipped for all four** (`picks.json`), as the recommendation. Every variant of a stance change joins the
shipped idles, so the letters can be picked apart: a `Crouch_Idle` of another letter rebuilds the stance changes
and the prone transitions on its pose. In every variant the left foot keeps its standing place, so one step of the
right foot makes the stance.

### The crouch's numbers for the code

- `Crouch_Walk` is in place at 1.5 m/s (`speed`), the left foot lands at frame 0 and the right half a stride later
  (`contacts`, `events`). `flat` in `locomotion.json` is each contact's frames with the whole sole down: from an
  entry's first frame to the end of its contact the ball of the foot stays on its place while the heel may rise.
- The stance changes do not travel. The left foot is down for the whole clip; the right has two contacts with its
  step between them (`contacts`), and a `footstep` event where it lands. `joins` names the shipped clips whose
  first poses the ends are, and the event `crouched` (frame 15 of 16) or `rising` marks where the legs' fold ends
  or begins. They are 0.53 s long against a `crouch_time` of 0.2 s: going down, the capsule and the camera get
  there first; coming up, the capsule is full height before the body is. The tree that plays them is kit #1158.
- The crouch stands behind the root: its pelvis is 0.38 m behind it and its rear heel 0.56 m (the library's are
  0.28 and 0.44 m), since the front foot keeps the standing idle's place.
- Each clip keys 52 bones' rotations and the pelvis's place; the walk's fingers move with the arm swing, so it
  carries their tracks. The cost per clip is in the pull request.
- The walk's sole wander is the heel's skin, which the shin shares: at an ankle bent this far it slides a few
  millimetres over a foot whose joints do not move (the Godot test holds the joints to 1 mm).
