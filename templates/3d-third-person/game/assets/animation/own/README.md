# GDStudio's own clips

Clips made by GDStudio, by script, that replace the Universal Animation Library's one clip type at a time (the plan:
the kit's `docs/tools/blender/own-animation.md`; how to use the toolkit: `docs/tools/blender/animation.md#toolkit`).
Nothing here is copied from a library clip or from another game: a clip is a description that `gdsanim/` solves.

| File | What it is |
| --- | --- |
| `locomotion.glb`, `locomotion.json` | The shipped clips and what the game needs to know of each (`clips.json` of the plan): loop, length, speed, travel and turn curves, contact times per foot, the foot it starts and ends on, events. Godot imports the glb as an `AnimationLibrary`; the player's `AnimationPlayer` holds it as `gds`, so the clip is `gds/Idle`. |
| `picks.json` | Which variant each shipped clip is built from (`"Idle": "A"`). |
| `clips/<type>.py` | A clip type's description, with every number a style may set and what it means. |
| `styles/style_<letter>.json` | A variant: a vision, its numbers per clip type and its overlap numbers. |
| `review/<type>.glb`, `.json` | Every variant of a type under its letter (`Idle_A`), for review; the game does not import this folder. |
| `gdsanim/` | The toolkit: the solver, the contact plan, the overlap pass, the checks and the writer. |
| `build_own.py` | Builds a review file or a shipped file; refuses to write when a check fails. |
| `review_sheet.py`, `review_render.py` | The review sheet: the strip, the other bodies, the numbers, the notes. |

```sh
uv run --with numpy python -B build_own.py self-test
uv run --with numpy python -B build_own.py review <idle, walk, jog or sprint> --blender <the pinned Blender>
uv run --with numpy python -B build_own.py ship locomotion --blender <the pinned Blender>
uv run --with numpy --with pillow python -B review_sheet.py idle --blender <the pinned Blender> --out <folder>
```

A rebuild writes the same bytes (`--check` compares with the files on disk and writes nothing). The clip from the
game's camera is `tools/capture/own_clips_review.tscn`; the Godot test is `tests/gameplay/test_own_clips.gd`.

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

### How they are built

- **Footfalls first.** The left foot lands at frame 0 and the right at half the cycle in all three; a foot is on
  one place of the floor for a whole number of frames while the root travels at the game's speed. Cadence, planted
  share and speed are the style's numbers, and `locomotion.json` carries them (speed, contact frames, a footstep
  event per landing).
- **The centre of mass is the input.** It moves at the clip's speed, sways toward the carrying foot, and goes up
  and down as a body's does (highest over the standing leg in a walk; a free fall between a run's contacts). The
  pelvis is solved from it, and the whole path is set as high as the furthest-stretched leg allows (`stretch`), so
  no knee locks and no ankle is out of reach.
- **The feet are set down on every body's skin.** The two mannequins' soles are not one shape (the male's toes are
  24 mm longer), and the heel's skin follows the shin: each frame's ankle height is corrected until the lowest skin
  of both bodies is nearest the floor while planted and clear of it in the swing.
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
  higher and the left arm swings 8 % wider (`uneven`). The right arm is the one that carries a weapon: in the
  shipped jog and sprint it goes further out on its way back and turns in less, which keeps the carried pistol
  50 mm clear of both bodies (`tests/gameplay/test_pistol_clearance.gd`).

### The three variants of each

Measured by `../audit_clips.py` on the female mannequin; the review sheets print the whole table.

| | A, grounded | B, loose | C, sharp | the library's |
| --- | --- | --- | --- | --- |
| **Walk**: steps a minute, planted sole speed | 138, 1.71 m/s | 129, 1.71 | 138, 1.71 | 90, 0.95 |
| Pelvis up and down, side to side | 37, 48 mm | 43, 66 | 32, 50 | 53, 71 |
| Hips turn and tip, shoulders turn | 8 and 6, 8 degrees | 12 and 9, 12 | 6 and 5, 10 | 4 and 5, 15 |
| Left upper arm swings; forearm, hand, chest trail | 49 degrees; 1.4, 1.4, 1.3 frames | 65; 2.0, 2.0, 2.4 | 50; 0.9, 0.9, 0.8 | 33; 0.2, 2.2, 1.3 |
| Thighs' halves differ, lowest sole vertex, seam's step | 1.2 degrees, 0.4 mm, 0.18 | 1.7, 0.3, 0.16 | 0.6, 0.4, 0.17 | 2.5, 14.8 under, 2.01 |
| **Jog**: steps a minute, planted sole speed | 180, 4.07 m/s | 180, 4.07 | 180, 4.07 | 129, 5.91 |
| Pelvis up and down, side to side | 79, 37 mm | 90, 53 | 79, 33 | 245, 36 |
| Hips turn and tip, shoulders turn | 12 and 8, 19 degrees | 16 and 11, 25 | 9 and 5, 14 | 1 and 11, 76 |
| Left upper arm swings; forearm, hand, chest trail | 87 degrees; 0.8, 0.9, 0.8 frames | 108; 1.2, 1.4, 1.8 | 83; 0.9, 0.9, 0.8 | 86; 1.6, none, none |
| Thigh swings, trunk leans, halves differ | 78, 7.6, 1.3 degrees | 79, 7.6, 2.1 | 85, 8.9, 0.6 | 117, 25.5, 3.7 |
| **Sprint**: steps a minute, planted sole speed | 200, 6.50 m/s | 200, 6.50 | 200, 6.50 | 180, 5.79 |
| Pelvis up and down, side to side | 87, 26 mm | 90, 28 | 88, 23 | 138, 36 |
| Hips turn and tip, shoulders turn | 18 and 8, 25 degrees | 22 and 10, 31 | 14 and 5, 19 | 4 and 10, 47 |
| Left upper arm swings; forearm, hand, chest trail | 121 degrees; 0.9, 0.9, 0.8 frames | 138; 1.2, 1.5, 1.3 | 122; 0.9, 0.9, 0.8 | 78; 0.3, 0.1, none |
| Thigh swings, trunk leans, halves differ | 95, 9.6, 1.3 degrees | 94, 9.1, 2.0 | 100, 12.2, 0.6 | 113, 39.1, 13.4 |
| Planted sole wanders (the build, both bodies) | 4.5, 4.4, 2.3 mm (walk, jog, sprint) | 4.5, 4.7, 2.3 | 4.5, 4.2, 2.3 | 64, 10, 313 (the audit) |
| Limbs inside limbs, female and male | 0 and 0 mm in all three | 0 and 0 | 0 and 0 | walk: 12 mm |

**A is the one shipped for all three** (`picks.json`), as the recommendation: its numbers are a person's at the
game's speeds. B is the vision for a loose, long-limbed character; C for a small or stylised body seen from far.
The grounded and the sharp runs trail by the same frames; what tells them apart is the trunk (hips, shoulders,
lean) and the knee lift; the "halves differ" row follows the thighs only, and the sides differ most in the
arms, the feet's turn and the shoulders' set.

### What the numbers do not say

- **The walk's knee is 23 degrees bent as the heel lands** (a person's about 5) and the hips ride 2 to 6 cm under
  the standing height: the step is 0.74 m on 0.83 m legs and the rise and fall is held to 37 mm.
- **The runs sit low.** The pelvis goes down to 82 cm in the jog and 80 cm in the sprint (92 standing), and it is 7
  to 12 cm behind the centre of mass in the sprint because the trunk leans.
- **The audit reads the jog's planted sole wandering 7 mm.** It follows every vertex of the sole, and the heel's
  skin is weighted to the shin, which swings 25 degrees a frame over the planted foot. On the skin that only the
  foot and the toes move, the build reads 4.4 mm.
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
| Tracks: bones' rotations and the pelvis's place | 52 and 1 | 52 and 1 | 52 and 1 |
| Keys kept by the build, of every frame | 59 % | 77 % | 74 % |
| Keys a half-degree reducer keeps on moving bones (budget 40 %) | 30 % | 40 % | 48 % |
| Key bytes in the file | 14.1 KB | 13.9 KB | 12.1 KB |

- **Imported size:** the library file is 57.6 KB imported with all four clips (39 KB with the idle alone), 4.8 KB a
  second over its 12.1 s, inside the 6 KB a second budget the test holds the file to. The three gaits add 18.6 KB
  for 2.13 s, 8.7 KB a second by themselves: a short loop of fast motion has few frames a reducer can drop, and
  the sprint is over the 40 % key budget for that reason (declared in the description, `keys_kept`).
- **They are played at their own pace** by the ground blend space, as the library's were; since their speeds are
  the game's own, the feet hold the floor at the three tuned speeds. Between them the blend still slides: speed
  matching is kit #1158.
- **Footsteps** come from the feet's height as before (`Footsteps`), now seven a three seconds in a walk.
- **The pistol's hold** was solved on the library's gaits; `tests/gameplay/test_pistol_hold.gd` and
  `test_pistol_clearance.gd` pass on ours without a change.
