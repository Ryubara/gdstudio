# The two-handed pistol grip

<!-- new section: nothing said how two hands hold a pistol together; the 3D Third Person pistol's hands each met
     their own targets and sat beside each other (gdstudio #1084) -->

How a pistol is held in two hands as it is taught today (the thumbs-forward grip), what each finger does, and how the
3D Third Person template's pistol hold was rebuilt to it (kit #1084). The rules every held model meets are on
[Weapons: hands on the weapon](../weapons.md#hands-on-the-weapon); the hold's parts in the game are on
[Weapons: the template's pistol](../weapons.md#the-third-person-template-pistol).

## How the grip is formed {#how-the-grip-is-formed}

<!-- new section: the research the rebuilt hold follows, finger by finger, with its sources (gdstudio #1084) -->

A hold solved one hand at a time puts the second hand where the first leaves room, beside it. A real grip is built the
other way round: the support hand is laid **over** the shooting hand, and every part of it has a place that the
shooting hand makes for it.

| Part | What it does | Source |
| --- | --- | --- |
| Shooting hand, web | High on the backstrap, under the tang; a hand set too low is the most common fault | [American Rifleman][ar] |
| Shooting hand, three fingers | Round the front strap, the middle finger tight under the trigger guard; the middle and ring fingers do most of the gripping | [Outdoor Life][ol], [Shooting Illustrated][si] |
| Shooting hand, index finger | Straight along the frame until the shot, then on the trigger | [Shooting Illustrated][si] |
| Shooting hand, thumb | Forward and high; with the support hand on the gun it rests on the root of the support thumb | [American Rifleman][ar], [Outdoor Life][ol] |
| The open side | The shooting hand leaves a gap on the grip's other panel, between its fingertips and the heel of its palm | [Shooting Illustrated][si] |
| Support hand, heel of the palm | Fills that gap: the pad under the thumb is rolled onto the bare panel | [Shooting Illustrated][si], [Outdoor Life][ol] |
| Support hand, four fingers | Wrap over the shooting hand's fingers, round the front of the grip, tight up against the trigger guard | [Outdoor Life][ol], [American Rifleman][ar] |
| Support hand, index finger | Under the trigger guard, as high as it goes; never hooked round the guard's front | [Athlon Outdoors][ao], [Outdoor Life][ol] |
| Support hand, cant | The wrist is bent forward (the little finger toward the ground), which puts the hand at about 45 degrees to the barrel and points the thumb at the target | [Athlon Outdoors][ao], [American Rifleman][ar] |
| Support hand, thumb | Forward along the frame under the slide, ahead of and below the shooting thumb; the thumbs never cross | [American Rifleman][ar], [Outdoor Life][ol] |

Sources differ on small things (how hard each hand squeezes, whether the support thumb presses on the frame); none
teaches the two hands side by side, the support fingers on the grip itself, or a support hand held like the shooting
hand mirrored.

[si]: https://www.shootingillustrated.com/articles/2011/11/18/thumbs-forward-handgun-grip
[ar]: https://www.americanrifleman.org/articles/2019/7/16/pro-shooter-advice-proper-handgun-grip
[ol]: https://www.outdoorlife.com/guns/how-to-hold-a-pistol
[ao]: https://athlonoutdoors.com/article/proper-pistol-grip-max-michel/

## The 3D Third Person pistol's hold {#the-template-pistols-hold}

<!-- new section: what of the taught grip the mannequin's hands do on the template's pistol, with the numbers
     (gdstudio #1084) -->

The pistol is the template's own (692 triangles, the muzzle along -X, up +Y, the gun's left +Z). The grip was
rebuilt on kit #1001's seat (kit #1084, the numbers below), and the seat then moved so the shooting hand's middle
finger lies under the trigger guard (kit #1213, [below](#the-seat-under-the-guard)); each body has a seat of its
own, and both hands, the rack's hand on the slide among them, were solved again on it:

| Part | In the template | Measured (female, male) |
| --- | --- | --- |
| Support hand, cant | Its knuckle line is 43 degrees from the gun's own down (16 before, the right hand mirrored); the wrist is 4 cm higher, level with the frame | `test_the_two_hands_hold_the_pistol_together`: 25 to 50 degrees |
| Support hand, four fingers | Over the right hand's ring and little fingers and round the front of the grip, their tips on the gun's right | each middle and last bone within 5 mm of the right hand's skin (at most 1.4 mm off it) |
| Support hand, index finger | Under the trigger guard, on the gun | at most 1.9 mm off the guard |
| Support hand, palm | On the right hand's fingertips, which cover the left panel; the heel reaches the bare panel on the male mannequin only (0.8 mm; the female's thinner palm is 13 mm off it) | 2.4 mm (female) and 1.8 mm (male) off the right hand |
| Support hand, thumb | Forward along the frame above the trigger guard, under the slide, its last joint 108 mm ahead of the right thumb's | 1.1 mm off the gun (female), 0.9 mm in (male) |
| Shooting hand, thumb | Lifted off the frame onto the root of the left thumb while the left hand is on the gun (`pistol_thumb_pose.tres`; the female body's is set by hand); on the frame when the gun is held in one hand | on the prototype bodies 0.9 mm in the left hand (female) and 0.4 mm off it (male), 4.7 and 4.1 mm from the skin of its thumb root (the test allows 12) |
| Depth | Each hand against the gun and against the other hand, both ways | at most 1.6 mm in |

What the rig cannot do, and where it differs from the taught grip:

- **The trigger finger grazes the guard on its way to the trigger** (3.7 mm at the guard's front strut, for a few
  twentieths of the way): the finger's last bone is 20 mm thick and the guard's opening 21 mm long, so no way in is
  clear, with the knuckle free to 40 degrees back either (kit #1212). It no longer touches the left hand.

**Poses set by hand** (kit #1084, on the prototype bodies of kit #1187). Where the solver's search ended in a pose
that passed no test or did not read as a hand, the finger's angles are set by hand in
`tools/hold/pistol_authored.json` (`{body: {pose: {finger: [angles]}}}`, the solver's own angles: a finger's spread
and three bends, the thumb's six), and `write_hold.gd` lays them over the solved hold, so a new solve keeps them
(`tools/hold/lay_authored.py` lays them into the solve's own file, for a stage run after it).
`tools/hold/pose_bench.gd` puts such a file on the tests' own stage and prints the game's measure in the tests' words
(every part against the gun and the other hand with `PARTS=1`, a bone's place in the gun's space with `JOINTS=`, an
OBJ of both hands and the gun with `OBJ=` for a look in Blender from any side), about ten seconds a look. What is set
by hand:

| Body | Pose | Fingers | Why |
| --- | --- | --- | --- |
| female, male | `support` | left index | The solver closed its tip onto the right index finger as it lies along the frame, which is on the trigger in the aim: the tip was 9.6 mm off there. It is set under the guard, on the gun |
| female, male | `grip` | right index | Along the frame, 20 mm or more from the trigger and clear of the left index finger set under the guard |
| male | `grip` | right little | Spread 8 degrees down the grip: the solver's tip was 2 to 4 mm inside the left hand under the magazine |
| female | `grip` | right thumb | High on the frame, where the two-handed pose leaves from: the solver's was 6.4 to 6.7 mm inside the left hand as it let go and came back (reload shares 0.04 and 0.86) |
| female, male | `thumb` | right thumb | On the root of the left thumb, within the test's 12 mm of its skin |
| female, male | `thumb_way` | right thumb | The pose between its two places ([below](#between-the-poses)) |

The poses set by hand on kit #1001's seat (the female's left middle, ring and little fingers, her right little
finger) put the fingers 3 to 8 mm inside on the new seat and are gone: those fingers are the solver's again and
pass. Every row passes the hold suite's limits (2 mm in, 5 mm off; the way poses 1.2 mm).

### The seat under the guard {#the-seat-under-the-guard}

<!-- new section: the seat moved after the grip was rebuilt, and what a moved seat costs every other solved thing
     had no place (gdstudio #1213) -->

Kit #1001's seat had the web under the tang and the middle finger beside the trigger guard, hooked round its front:
the hand is 41 mm from the web to the top of the middle finger where the gun is 63 mm from the tang to the guard's
underside. The seat of kit #1213 tips the hand instead of sliding it down the grip, so the web stays high:

| | female | male |
| --- | --- | --- |
| Seat, as a move from the reference (`SEAT`, `SEAT_MALE`: metres, then degrees) | 0.016, -0.025, 0.0069; 3, -8.5, -29 | 0.010, -0.021, 0.0075; -6, -12, -28 |
| Middle of the right middle finger's first bone, up the gun (the guard's underside is at 14 mm; the test wants 8 or less) | 5.5 mm (20.1 before) | 5.3 mm (about 42 before, inside the guard) |
| Thumb's root up the gun (the web under the tang) | 62 mm (64 before) | 63 mm (69 before) |
| Wrist bend | 31 degrees | 30 degrees |
| Left arm to spare at the worst pose | 9.3 mm | 7.3 mm |

A moved seat is a new hold: the left hand's place (the gun is 10 to 14 mm farther from the left shoulder), every
finger of both hands, the hand under the magazine, the way off the gun, the hand-set poses, the rack's hand on the
slide and its clip, `Weapon.no_muzzle_offset` (the muzzle moved 15 mm) and the carried pose of anything that hangs
on the hold were all solved or built again, in that order. The rifle's hold has its own solve and did not move.

## Between the poses {#between-the-poses}

<!-- new section: what moves between the solved poses of the two-handed hold, and how each move is kept clear
     (gdstudio #1078, #1079, #1084) -->

A solved pose is clear where it holds; the blend the game plays between two of them is not, unless it is solved too.

- **The trigger finger goes by a pose between** (kit #1079, `pistol_trigger_way_pose.tres`,
  `HandPoseModifier.second_way`). The straight blend from along the frame to the trigger left the guard on the gun's
  far side: 7.3 mm through the left thumb's tip and 7.0 mm through the gun. The pose between (the finger lowered and
  drawn out to its own side, nearly straight) is solved as the nearest to both ends that keeps the finger out of the
  left hand at every twentieth (never nearer than 3 mm now) and as little in the gun as it can be (3.7 mm, above).
- **The right thumb makes room while the left hand waits** (kit #1084, `SupportHandPlan.room`). The left thumb's
  root takes the right thumb's place on the frame, so the right thumb is lifted onto it; blended while the left hand
  came in, it was 16 mm inside that hand. The plan now has a step for it: the hold's arm takes the left hand to the
  far end of its way (the plan's `on` to 0.3), the hand waits there while the thumb moves (0.3 to 0.6), then comes in
  (0.6 to 1); the way's far end is solved clear of the thumb everywhere between its two poses.
- **The right thumb goes by a pose between too** (`pistol_thumb_way_pose.tres`, `HandPoseModifier.open_via`,
  `WeaponHold.thumb_way_pose`). Its two places are on either side of the frame's rear edge, and on the prototype
  bodies the straight blend took its middle bone 3.8 mm (male) and 2.6 mm (female; 5.2 mm to her hand-set place)
  through that edge; no end pose met both the way and the 12 mm to the left thumb's root. The pose between lifts the
  thumb clear first (set by hand: started at the middle of the two ends' angles and moved until the deepest of
  fifteen steps of the way read under 1 mm in the game's measure, going round by no more than that takes): 1.2 mm
  (male) and 1.0 mm (female) at every fortieth of the way
  (`test_the_right_thumb_passes_through_nothing_on_its_way_to_the_left_thumb`). A reload plays the whole move
  inside two hundredths of the clip (shares 0.064 to 0.082 on the way off), so the reload's samples see one moment
  of it.
- **The left hand's fingers press the right hand as they open and close** over it: 2.1 mm at the right little
  finger's tip on both mannequins, for two hundredths of a reload (it is 1.5 mm in the palm that lies on it while both
  hold). The test allows 2.5 mm there by name (`LEFT_HAND_PASSING`), and only while the fingers are between their
  two poses.
- **An arm too short backs the hand off along its way** (kit #1078, `HoldArm.retreat`). While the aim comes up the
  gun is still out to the side and the left arm 6 to 16 cm short of the hand's place; the hand stopped short with the
  place's turn, its fingers 13 to 18 mm through the gun and the right hand. The arm now puts the hand on the line of
  its way, at the first place it reaches, opened (`HoldArm.backed_off`), so it comes in only as far as the arm
  reaches: 0.8 mm (female) and 0.9 mm (male) deep at most on the live player, every update, both mannequins.
- **The gun is not held out during a reload.** `carry_arm_out` (8 degrees, for the thigh) stayed on through a reload
  started with the gun carried and took the gun 13 mm out of the male mannequin's reach from the new place; it now
  fades with the reload's weight as it does with the aim's.

## The left hand through the reload {#the-left-hand-through-the-reload}

<!-- new section: moved from the weapons page, which is near the size limit (gdstudio #1084) -->

- **The left hand follows the reload** (kit #1031). `Pistol_Reload` (1.67 s, stretched to the weapon's
  `reload_time`) has the left hand on the gun for its first 4 hundredths, down at the left hip for the new magazine at
  a quarter, under the grip from 0.54 to 0.71 and back on the gun from 0.88. After the solved seat moved the pistol
  about 10 cm in the hand, the clip's own left hand was 16 to 22 mm inside the gun or the right hand for a third of the
  clip on the female and 20 to 23 mm at its ends on the male, and under the grip it stood beside the gun's right side,
  not under the magazine. `WeaponHold` now takes the hand through the clip's steps by the clip's own time
  (`CharacterAnimation.reload_progress()`: how much of the body the one-shot holds, and the share played): on the
  `SupportHand` marker, opened and let go to the clip's arm (0.04 to 0.10), brought to the line under the magazine
  (0.30 to 0.40) one magazine's length down the grip, pushed up it (0.40 to 0.54) to the `MagazineHand` marker, where
  the heel of the palm is on the magazine's base as a real reload seats one, then down, round the grip's foot and
  onto the gun (0.71 to 0.88). Where the hand holds, it is within the 2 mm and 5 mm (the palm 1.6 to 3.1 mm off the
  base, nothing more than 1.2 mm in). The trigger finger is off the trigger for the whole reload. Where the hand
  should be at each moment was decided from the clip and from how a reload is taught: the magazine is fetched at the
  belt, guided in and seated firmly with the support palm, and the
  grip is taken again ([Shooting Illustrated](https://www.shootingillustrated.com/articles/2012/10/25/semi-automatic-handgun-reloading),
  [AmmoLand](https://www.ammoland.com/2023/03/4-pistol-reload-methods-9-magazine-tips)). The clip has no rack of the
  slide and no magazine in the hand, and the pistol's `Magazine` node does not move yet.
- **The left hand has one way on and off the gun** (kit #1051). #1031 let the hand go by fading its arm to the
  clip's, so it left along whatever line lay between its place and the clip's hand, its little finger still on the
  grip: 5.1 to 5.2 mm through the gun at shares 0.05 to 0.055 on the female mannequin, and 9.1 mm (female) and 5.7 mm
  (male) at 0.7875 on the swing back from the magazine, between two hundredths. Now the fingers open where the hand
  holds (`pistol_open_pose.tres`: each finger the nearest pose that lifts it 5 mm off every surface with nothing
  deeper than 1 mm in the sixteen poses between, blended as the game blends them; the little finger, which lies on
  the grip's left panel, curls its middle joint in), then the opened hand leaves along a straight 6 cm line
  (`WeaponHold.support_way`: of the directions 10 degrees apart in which the whole hand stays clear, and its
  neighbours too, the one nearest the way to the belt; 26 degrees off it, down, back and to the left), and only at
  the line's far end does the clip's arm take it. Coming on is the same way backwards, for the aim and from the
  magazine alike: from under the magazine the hand drops, crosses to the line's far end bowed 4 cm down and out
  (`return_clearance`) while its fingers open, and comes in. `SupportHandPlan` holds this as one number (how far on
  the gun the hand is) and the reload's phases (`HELD`, `LET_GO`, `AWAY`, `REACH`, `INSERT`, `SEATED`, `RETURN`), for
  whatever moves with the hand next. Measured at every hundredth of the reload and at every quarter of a hundredth
  of the moving spans, the left hand is at most 1.2 mm in on both mannequins; on the live player reloading while it
  aims, on every update, the same (before: 5.9 to 8.5 mm over five frames of the let-go and 7.4 mm on the way back).
  Two faults the live measure found were not the left hand's way: the arm too short while the aim comes up (kit
  #1078) and the trigger finger through the left thumb (kit #1079), both [above](#between-the-poses).

## Solving two hands against each other {#solving-two-hands}

<!-- new section: what the solver had to learn to measure one hand against the other (gdstudio #1084) -->

- **Approach:** Research how a real grip is formed, finger by finger with sources, before solving a second hand, and
  give the solver a cost for each thing the grip teaches (the cant, the fingers over the other hand's and round to
  the far side, the index finger under the guard, the thumbs). **Watch out for:** a second hand solved as the first one
  mirrored and moved until its fingers touched something met every contact limit and sat beside the first hand, its
  thumb along the trigger guard's opening; the maintainer's look at the game found it, the numbers did not.
  **Seen:** gdstudio #1084, 2026-11-11 (fix: the table above; cant 16 to 43 degrees).
- **Approach:** Measure each hand against the other, both ways, in the solver and in the test, and sample a part
  with large faces (the palm: 199 triangles, edges to 5 cm) all over its faces, not only at its vertices; measure the
  other hand's vertices against a finger taken as three capsules. **Watch out for:** the left hand's vertices against
  the right hand's skin read 1.2 mm while the right little finger's tip was 3.3 mm inside the left palm, and at the
  first canted place the right thumb's tip 17.5 mm; a capsule's middle line is 4 to 9 mm off the bone's, and its
  radius is the outer vertices' (the median is pulled in by the joint balls inside). **Seen:** gdstudio #1084,
  2026-11-11 (fix: `Hand.palm_points`, `Hand.finger_depth`, `measure("r", true)` in the test).
- **Approach:** Say in the cost where a finger must end, not only what it must touch. **Watch out for:** asked to
  lie on the other hand, the support fingers curled into their own palm (they touched the other hand's fingertips
  there), and the shooting thumb crossed to the gun's far side to lie on the support hand's fingertips, a place it
  could only reach through the gun. **Seen:** gdstudio #1084, 2026-11-11 (fix: the support fingers' last bones on the
  gun's far side, the thumb's on its own).
- **Approach:** Close a hand's skin where its selection ends before counting a point inside or out of it, each
  ring of open edges joined to its own middle, in the solver and in the game's measure alike, and look at the hold
  from above after every solve. **Watch out for:** the palm's piece is open at the wrist, and the shooting thumb
  turned sideways behind the gun and put its tip in that opening: the solver read it 0.7 mm off, the game's measure
  2.2 mm off in the level aim and 19.4 mm in once the aim turned the hands up (two of its three rays left through
  the hole). One fan for all the hand's open edges joins its pieces into one, where a point inside two counts as
  outside. **Seen:** gdstudio #1084, 2026-11-11 (fix: `hold_field.ring_caps`, `HandContact._open_rings`; the test
  checks the thumb's tip within 12 mm of the left thumb's root).
- **Approach:** Search a finger's pose from many starts (the grid, then some thousands of random ones, the best four
  refined each on its own), and aim it at a place a wide search proved it reaches. **Watch out for:** refined from the
  grid's best start alone, four different targets gave the same sideways thumb; a target the thumb could not reach
  (3 cm ahead of where its joints end) pulled it there as well. Its root is behind the grip, so its tip gets no
  further forward than the left thumb's root joint. **Seen:** gdstudio #1084, 2026-11-11 (fix: `solve_finger`'s
  `wide`, `THUMB_OVER`).
- **Approach:** Trace every blend the game plays between two solved poses at twentieths against the gun and the
  other hand before wiring it, and give a part that must move through another's place a step of the plan in which
  that other is away. **Watch out for:** the thumb's straight blend between its two poses passed 16.9 mm through the
  gun (the poses were on opposite sides); lifted as the other hand came in, it was 16 mm inside that hand at two
  hundredths of the reload. **Seen:** gdstudio #1084, 2026-11-11 (fix: `SupportHandPlan.room`).
- **Approach:** Measure a way's room before promising it clear: the part's thickness against the opening it enters.
  **Watch out for:** the trigger finger (20 mm) into the guard's opening (21 mm) grazes the guard's strut by 3.6 mm
  whatever pose it goes by; four searches (other trigger poses, a wider knuckle) found the same. **Seen:** gdstudio
  #1079, 2026-11-11 (the test allows that graze by name; the guard is #1212).
- **Approach:** Measure the other arm's reach on each mannequin's own skeleton, in the reload clip's first pose as
  well as the aim poses, after moving a hand's place. **Watch out for:** the solver's merged rig is the female
  skeleton with both skins, so the male arm was never measured: the canted place, 4 cm higher, was 6.5 mm out of
  its reach where the reload starts with the gun carried, and the hand stood off the gun with its fingers open.
  **Seen:** gdstudio #1084, 2026-11-11 (fix: `reach` on both rigs; no carry swing during a reload).
- **Approach:** Measure the left arm's reach again after the right hand's seat moves, and make the last
  millimetres of reach cost far more than contact wins. **Watch out for:** the seat under the guard holds the gun
  10 to 14 mm farther from the left shoulder: the male's old left place was 0.6 mm from the arm's end, and a search
  that paid a millimetre for a millimetre took one 4.6 mm out of reach for the palm's sake. **Seen:** gdstudio
  #1213, 2026-11-12 (fix: `REACH_LEAST`, `REACH_SHORT`; 7.3 mm to spare).
- **Approach:** On a low-poly body, measure the other hand at points on its faces too, not only its vertices, and make
  each limit the test holds cost more than the place search can win by breaking it. **Watch out for:** on the
  prototype bodies (eight vertices a ring) the right ring finger's face lay 2.6 mm in the left one, read 0.9 mm from
  vertices; a tighter finger limit moved nothing, since the place sets it. A cant at 0.3 mm a degree went to 51
  degrees, and the palm's vertices (what the test reads) stayed 6.5 to 8.3 mm off. The solver's log printed all three.
  **Seen:** gdstudio #1084 after #1299, 2026-11-11 (fix: `FACE_SAMPLES`, `PALM_WEIGHT`, the cant at 2 mm a degree).
- **Approach:** When a re-solve fails on several bodies, keep every solve with its suite result, take the best hold
  per body on its own and freeze it, and move only the failing hand by a few placements scored on the failing cases;
  stop after two rounds and hand the pose to an artist. **Watch out for:** retuning the cost shared by both bodies
  fixed one finger and broke another each time (6 failures, then 13); the female's little finger sat at its 12 degree
  spread limit in every placement, 6 mm off the right hand at best. **Seen:** gdstudio #1084 after #1299, 2026-11-11.
- **Approach:** Trace a blend at every step the game can show (forty parts of its own weight, not shares of a clip
  that plays it in a moment), with the game's blend (a slerp of rotations) and the game's measure, in a test of its
  own. **Watch out for:** the right thumb's move was checked half-way, then at fifths, then at tenths of the angles'
  straight line, and each finer check found it deeper nearer an end (1.9, then 2.8, then 3.7 to 4.8 mm); the reload
  test sampled it once, at 0.07 of its way, and read 2.7 mm where the deepest was 3.8. **Seen:** gdstudio #1084
  after #1299, 2026-11-11 (fix: the thumb's own way test, forty steps; the pose between).
- **Approach:** Take a limit's measure from the test's own code: the same point, the same surface, the same
  vertices. **Watch out for:** the solver held the thumb's tip bone within 11 mm of the left thumb's root bone line;
  the test measures from whichever skin point of the tip is nearest any surface to the nearest vertex of the root's
  skin, and read 12.5 to 15.4 mm on poses the solver had passed. **Seen:** gdstudio #1084 after #1299, 2026-11-11
  (fix: poses judged on `pose_bench.gd`, which calls `HandContact` as the test does); gdstudio #1213, 2026-11-12
  (the cost for the middle finger under the guard read another point of the finger than the test, and at a
  millimetre a millimetre the seat search stopped 0.5 mm over the test's limit; fix: the middle of the first bone
  between its two joints, as the test has it, at `UNDER` 3).
- **Approach:** After running one stage of a solve again, run every hold suite again, and keep the file from before
  beside the new one. **Watch out for:** the way-out stage run again for one finger wrote a new opened pose and a new
  line off the gun, and reload cases that had passed failed; nothing but the full suites showed it. **Seen:**
  gdstudio #1084 after #1299, 2026-11-11 (fix: each solve kept with its suite result; hand-set poses live in their
  own file and are laid over whatever the solve wrote).
- **Approach:** When a finger will not reach a surface, look at which layer its neighbours lie in before turning it
  further, and compare with a body on which the same grip passes. **Watch out for:** the female body's left little
  finger was pushed toward the right hand until it sank into its own ring finger (at 30 degrees three fingers
  showed); the ring finger lay on the grip between the two, where the male body's lies over the right little
  finger. Lifting the ring finger out made the place. **Seen:** gdstudio #1084 after #1299, 2026-11-12.
- **Approach:** After changing one hand's pose for the two-handed grip, measure every other pose that hand is in:
  one-handed, the reload's shares, the other hand at the magazine. **Watch out for:** the right little finger spread
  6 degrees for the left one's sake was 2.4 mm inside the left hand under the magazine for a fifth of the reload;
  2.25 degrees holds both. **Seen:** gdstudio #1084 after #1299, 2026-11-12 (the bench's `reload:0:1:0.01`).
- **Approach:** Give a posing search a place said in the weapon's own space (where the tip and the last joint should
  be, in millimetres) and many starts, then look at the result from above. **Watch out for:** walked downhill from
  the solved pose on the test's limits alone, the female thumb met them with its tip bend changed by 16 degrees and
  still hooked down behind the palm. **Seen:** gdstudio #1084 after #1299, 2026-11-12.
- **Approach:** When a hold's plan gains a step, build again every clip that hands a hand to that hold, key the
  clip's own hand where the plan gives it up (the far end of the hand's way, not the grip), and measure both
  hands, each against the other, on every passing frame. **Watch out for:** the slide rack (#1103) had its left
  hand at the support grip on the frames the hold lets it go; this hold takes the hand out along its way, then
  lays the right thumb back on the frame, so the hand snapped back under the thumb (7.1 to 8.0 mm, female, arm
  in). The rack's test measured only the left hand; its right-hand case read the thumb on the left thumb's root
  as 7.5 to 10.1 mm off the gun. **Seen:** gdstudio #1084 after #1103, 2026-11-12 (fix: `build_pistol_rack.py`'s
  `ARM_UNTIL` keys; `test_pistol_rack.gd` measures the right hand against the left).
- **Approach:** After the seat or a pose of the hand that keeps the grip changes, solve again every other grip
  that was solved against that hand, then build its clip. **Watch out for:** the rack's hand on the slide is solved
  against the right hand: with the female's right thumb set higher on the frame, the left thumb was 4.0 mm in it
  while the slide was pulled (frames 12 to 13). **Seen:** gdstudio #1213, 2026-11-12 (`solve_rack_hand.py` for
  each body, then `build_pistol_rack.py`; 1.5 mm at most).
- **Approach:** Rest a support finger on a surface that is there in every pose the hands hold: the gun, or a part
  of the other hand that does not move. **Watch out for:** the shooting hand is a surface with its trigger finger
  in both places at once (along the frame and on the trigger), and the left index fingertip was closed onto the
  finger along the frame; in the aim that finger is on the trigger, and the tip read 9.6 mm off (female) in
  every aim and shoot clip. **Seen:** gdstudio #1213, 2026-11-12 (the left index finger set by hand under the
  guard on both bodies, `pistol_authored.json`).
- **Approach:** Lay the hand-set poses into the solve's own file before a later stage runs on it
  (`tools/hold/lay_authored.py`, then `--magazine-only` or `--way-only`). **Watch out for:** `write_hold.gd` lays
  them over the files it writes, which the solver never reads: the way off the gun was solved round the solver's
  right thumb, and the opened left hand went 5.7 mm through the hand-set one at reload shares 0.04 and 0.86
  (female). **Seen:** gdstudio #1213, 2026-11-12.
- **Approach:** Read the other hand's skin against a finger's own skin (`Hand.skin_field`: a distance grid in each
  bone's space), at every point of it, and once a pose is solved measure both hands' meshes against each other,
  each way, before taking a pose from an older solve. **Watch out for:** a capsule's end is round where a low-poly
  fingertip is blunt, and every other point of a hand whose knuckle is one vertex leaves that vertex out: the
  male's right little knuckle lay 4.8 mm inside the left middle fingertip under the magazine (5.0 in the game),
  0.6 mm in its capsule on all the points and outside it on every other one. **Seen:** gdstudio #1213, 2026-11-12
  (fix: `Hand.finger_depth` reads the skin; the male magazine hand is the solver's again).
- **Approach:** Write a long solve's output after every stage. **Watch out for:** the file was written once at the
  end, and a run stopped by its time limit in the last stage lost forty minutes of solved stages; the writer then
  wrote the old file into the project. **Seen:** gdstudio #1084, 2026-11-11 (fix: `save` after each stage).
