# Prone and crawl clips

Four clips for a character that lies down and crawls, made by GDStudio from nothing (kit #1009) because the Universal
Animation Library has none, and three that aim the pistol lying down ([Prone aim clips](#prone-aim-clips)). Each `prone`
file here holds the four, and Godot imports it as an `AnimationLibrary` the same way as `assets/animation/universal/`:
add one to an `AnimationPlayer` as the library `prone` and the clips are `prone/Prone_Idle`, `prone/Crawl_Fwd`,
`prone/Crouch_To_Prone` and `prone/Prone_To_Crouch` (the import drops `_Loop` from a looping clip's name and makes it
loop). The character scene (`gameplay/character/character_dressed.tscn`) holds them: the `AnimationPlayer` has
`prone_form_female.glb`, the file of the body the scene wears, as its library `prone`, and the `Animation` node's
`prone_libraries` names the file of each other body, swapped in when the game sets that model (kit #1012, #1090, #1293).

**One file a body** (kit #1090, #1293). The library is always named `prone` and holds the same four clip names,
lengths and crawl speed; which file it is loaded from follows the model:

| Model | The library `prone` is |
| --- | --- |
| `assets/characters/prototype/form_female.glb` (the template's body: the player, friendlies, online puppets) | `res://assets/animation/prone/prone_form_female.glb` |
| `assets/characters/prototype/form_male.glb` (the enemies) | `res://assets/animation/prone/prone_form_male.glb` |
| `assets/characters/mannequin/mannequin_female.glb` | `res://assets/animation/prone/prone.glb` |
| `assets/characters/mannequin/mannequin_male.glb` | `res://assets/animation/prone/prone_male.glb` |

Each file has its limb overlap report beside it (`<file>_overlap.json`, written by `../limb_overlap.py --brief` on
the body that plays it), which `tests/gameplay/test_prone_clips.gd` reads with the file's SHA-256: a rebuilt file
that was not measured again fails.

A clip holds the pelvis's height and every joint angle that sets an elbow's or a knee's height, so one file cannot
rest both bodies on the floor: in `prone.glb` the male, whose upper arms are 5 cm longer (0.27 m against 0.22 m) and
whose limbs are thicker, lay with his forearms 3.7 to 4.4 cm, his fists 2.3 to 3.0 cm and his thighs and shins about
3 cm under it, and the `form` bodies with their forearms 3.3 to 5.5 cm under it. A model that is none of the four
takes the file of the nearest upper arm (`upperarm_l` to `lowerarm_l` in the rest pose: 0.262 m and 0.280 m on the
`form` female and male, 0.221 m and 0.274 m on the Quaternius pair) and is measured with
`tests/fixtures/skinned_parts.gd` before it ships; the `joint` and `facet` looks of a prototype body share its
skeleton, so they take its `form` file (add the model to `prone_libraries`).

| Clip in the file | Length | Loops | What it is |
| --- | --- | --- | --- |
| `Prone_Idle_Loop` | 3.0 s (90 frames) | yes | Lying on the belly, propped on the forearms, which point inward and rest on their outer edges, the hands closed into fists near the centre line in front of the head, the right a little ahead; one slow breath and a small drift of the head. |
| `Crawl_Fwd_Loop` | 0.933 s (28 frames) | yes | A crawl on the forearms, the body kept low: the right elbow and the left foot plant and the body is pulled over them, then the other pair. Each forearm lands pointing inward on its outer edge, its fist in front of the head and ahead of the other fist. In place. |
| `Crouch_To_Prone` | 0.9 s (27 frames) | no | From frame 0 of `ual1/Crouch_Idle`: the open hands reach for the floor ahead and catch the body, the feet go back one after the other, and as the elbows come down the forearms roll onto their outer edges and the hands close. Ends on frame 0 of `Prone_Idle_Loop`. |
| `Prone_To_Crouch` | 1.0 s (30 frames) | no | From frame 0 of `Prone_Idle_Loop`: the fists open and the hands come back beside the chest, push on flat palms, the knees draw under the body, the chest rises. Ends on frame 0 of `ual1/Crouch_Idle`. |

All four are at 30 frames a second, the library's rate, keyed on every frame, with no root motion (the game moves the
body), on the 65 bones of the Quaternius universal rig.

## Numbers for the code

Measured by the build on the female mannequin, the template's default (`build_prone_clips.py --report`); the
male's file is [below](#the-males-file):

- **Crawl speed: 0.618 m/s** at the clip's own rate. A planted elbow travels 0.30 m under the body in 52 % of the
  cycle; one cycle (two pulls) covers 0.577 m. Play the clip at `speed / 0.618` and nothing slides. A foot is planted
  for the first 30 % of its half of the cycle and then drags straight behind the body.
- **What is planted:** each forearm (elbow and fist) and each pushing foot stay within 0.1 mm of their place on the
  floor while planted. The knee is not planted: it rolls 7 cm outward as the leg straightens, as a real knee does.
- **Where the body lies:** the origin is under the middle of the lying body. It reaches 0.96 m ahead of the origin
  lying still (the fists), 1.07 m while the open hands land going down and 1.03 m behind it (the toes); the crawl
  reaches 1.08 m ahead. The body is 0.59 m wide lying still, 0.72 m with a knee drawn up in the crawl and
  up to 0.96 m in the transitions (a knee goes out to the side as it bends under the body).
- **Height:** the top of the head is 0.49 m over the floor in the idle and at most 0.52 m in the crawl; the back and
  the hips stay under 0.30 m in the idle and 0.34 m in the crawl.
- **The arms:** a planted forearm points 40 degrees inward of straight ahead in the crawl (29.5 in the idle), with
  the elbow 8.5 cm outside its shoulder and the wrist 7 cm from the body's centre line (12.5 cm in the idle), the
  knuckles on the centre line. A fist plants 0.29 m ahead of the other, and the swinging forearm opens to 14
  degrees so its fist passes outside the planted one. Why these numbers: the research below.
- **Forearms on their outer edge, hands in fists:** a resting forearm is rolled 45 degrees onto its outer edge (the
  little finger's side down, the thumb's side up, the palm facing down and in toward the other arm) and its hand is
  a fist in line with it, the thumb wrapped outside the index and middle fingers. The weight is on the forearm's
  edge near the elbow and on the fist's edge, not on a flat palm: a forearm turned palm down is twisted as far as
  it goes and a flat hand bends the wrist back, which nobody keeps up for long. The elbow joint is 4.1 cm and the
  wrist joint 6.6 cm over the floor; the female's forearm and fist skin press 0.6 and 1.2 mm into it. A carried
  fist loosens by an eighth. The fist is one pose for both mannequins, set between their hands: on the female no
  finger is more than 1.3 mm into another piece of the hand (the thumb on the index finger) and the fingertips are
  1 to 5 mm short of the palm; on the male the fingertips are 2 to 2.6 mm in the palm and the thumb 4 mm off the
  fingers.
- **Transitions:** 0.9 s down and 1.0 s up at the clip's own rate; the hands land at 0.33 s going down and leave the
  floor at 0.43 s (the left) and 0.47 s (the right) coming up. Both start and end on the exact poses they join, so
  no blend is needed at either end. Going down, the open hands land flat (0.30 to 0.40 s), lift 4 cm and close while
  the forearms roll (0.40 to 0.63 s); coming up, the fists open between 0.10 and 0.23 s on the way to the push.
- **Nothing passes through anything:** on every frame of the four clips, on both mannequins' skinned meshes, no part
  of the body is more than 5 mm inside another (0.0 mm everywhere but the male's left knee against his upper arm
  going down, 0.8 mm on one frame), and the female's lowest vertex is 1.4 cm under the floor (a shoulder in the
  crawl, where the chest presses on the ground); her hands are never more than 2.7 mm under it (the flat palms in
  the transitions).
- **Backing up and turning:** there is no backward or turning clip. Play `Crawl_Fwd` backwards to back up, and turn
  the body while it plays to turn (the shipped games studied do the same or turn without a clip).

`tests/gameplay/test_prone_clips.gd` holds both models, each in its own file, to the bone numbers, the forearms'
roll, the fists and the floor under the skin.

## The male's file

`prone_male.glb` is the same four clips solved on the male mannequin's own skeleton and skin
(`build_prone_clips.py --body male`; the build's `BODIES` holds every number that differs from the female's, with
why). The look is the female's: the forearms 40 degrees inward in the crawl and 29.5 lying still, rolled 45 degrees
onto their outer edges, the hands in fists, the same timing, stride and **crawl speed (0.618 m/s)**, so the code needs
one set of numbers for both.

| Measured by the build | Female in `prone.glb` | Male in `prone.glb` (before) | Male in `prone_male.glb` |
| --- | --- | --- | --- |
| Forearms' lowest skin, lying still and crawling | 0.5 and 0.6 mm under the floor | 37.1 and 44.3 mm | 1.1 and 1.2 mm |
| Fists' lowest skin, lying still and crawling | 1.2 mm | 23.0 and 30.1 mm | 1.5 mm |
| Flat hands in the transitions | 2.7 mm | 36.3 mm | 1.7 mm |
| Thighs, lying still | 3.0 mm | 30.8 mm | 3.1 mm |
| Shins, at their lowest (the back knee going down) | 5.0 mm | 28.4 mm | 4.2 mm |
| A planted elbow's slide in the crawl | 0.0 mm | 30 mm | 0.0 mm |
| Limbs inside each other, at most | 0.0 mm | 0.8 mm | 0.1 mm |
| The fist: deepest finger piece, thumb off the fingers | 1.3 mm, 0.0 mm | 2.6 mm, 4.0 mm | 1.4 mm, 2.0 mm |
| Top of the head, lying still and crawling | 0.48 and 0.52 m | | 0.51 and 0.55 m |
| Wrist from the centre line, lying still | 12.5 cm | 16.5 cm | 12.3 cm |

Godot's import drops keys that are within half a degree of their neighbours, so in the game a planted hand reads up
to 3 mm lower than the build's number (4.1 mm under the floor at most, on both mannequins); the Godot test measures
what is played and holds the male to 5 mm.

What had to differ, and why:

- **Thicker limbs.** His elbow joint rests 5.7 cm over the floor (hers 4.1), his wrist 6.7 cm under a fist and 5.1 cm
  under a flat hand, his ankle 4.4 cm, and his toes bend at 2.3 cm. His knees are 2.5 cm thicker: with her leg, which
  hangs the knee 5 cm under the line from hip to ankle, he lay on his knees and elbows with the belly 5 cm off the
  floor, so his lying leg is straighter (0.998 of its length against 0.992) and his belly rests 1 cm over the floor.
- **Longer upper arms.** On elbows placed as hers his shoulders rode 7 cm higher and the back arched up to the head
  (10 cm higher than hers). His collarbones draw back instead (16 degrees lying still, 12 crawling, where hers push 4
  and 11 toward the floor): the chest hangs between the shoulders, as it does on anyone propped on the elbows. His
  elbows rest 11 cm outside the shoulders (hers 9.5 lying, 8.5 crawling) and, lying still, 8 cm ahead of them
  (hers 3.5). His head is then 3.5 cm higher than hers, the difference of the two bodies' thickness.
- **The transitions.** The pelvis passes 3.5 cm higher where the back knee comes just over the floor going down, the
  feet lift 2 cm more as they come onto their toes to get up, and the elbows (going down) and the left hand (coming
  up) pass 10 cm and 4 cm further outside the front knee, which his longer arm otherwise met by 9 mm.
- **The fist.** His fingers are longer: the middle joints curl 4 degrees less, which puts his fingertips on the palm
  (0.1 to 1 mm off it) where the shared fist had them 2 to 2.6 mm inside it. The female's file keeps the shared fist.

## The form bodies' files

`prone_form_female.glb` and `prone_form_male.glb` are the same four clips solved on GDStudio's prototype bodies in
the `form` look (`build_prone_clips.py --body form_female` and `--body form_male`; kit #1293), the bodies the
template wears since kit #1187. The crawl is the Quaternius files': forearms 40 degrees inward, rolled 45 degrees
onto their outer edges, fists, the same timing, stride and **crawl speed (0.618 m/s)**. The file keeps the
library's 65 bones: a prototype body's twist bones, sockets and IK targets are not in it, and the build and
`../limb_overlap.py` turn the twist bones as the game's `MannequinTwist` does before they measure the skin.

| Measured in Godot on each body's skin (`test_prone_clips.gd`) | `form_female`, in `prone.glb` (before) | `form_female`, own file | `form_male`, in `prone.glb` (before) | `form_male`, own file |
| --- | --- | --- | --- | --- |
| Forearms' lowest skin, lying still and crawling | 33 and 38 mm under the floor | 2.3 and 1.3 mm | 48 and 55 mm | 2.4 and 2.0 mm |
| Fists' lowest skin, lying still and crawling | 30 and 37 mm | 2.4 and 1.1 mm | 41 and 49 mm | 2.3 and 3.6 mm |
| Thighs, knees (the shins' skin) and feet, lying still | 15 to 16 mm | 4.1, 3.6 and 0.7 mm | 16 to 22 mm | 2.5, 3.7 and none |
| Thighs, shins and feet at their lowest in any clip | | 4.5, 3.6 and 4.9 mm | | 4.3, 4.5 and 2.3 mm |
| A planted elbow's roll at the crawl speed | 19 mm | 1.5 mm | 32 mm | 1.7 mm |
| Lowest bone | a pinky tip 30 mm under | 4 mm over | 42 mm under | 3 mm over |
| Limbs inside limbs, `Crouch_To_Prone` and `Prone_To_Crouch` | 18.1 and 16.9 mm | 0.0 and 0.0 mm | 0.5 mm | 0.0 and 2.2 mm |
| Wrists from a mirror of each other, at their nearest in the two transitions | 22 mm (six frames of the push up, in the first form files) | 96 mm | 22 mm | 96 mm |
| Shoulders from a mirror of each other, at their nearest in the two transitions | 0 mm (ten frames going down, eight coming up) | 31 mm | 0 mm | 36 mm |

The build's own numbers (every key, before Godot's import drops keys within half a degree of their neighbours) are
1 to 2 mm shallower at the forearms and fists (1.2 and 0.8 mm on the female, 1.7 and 1.3 mm on the male) and read
the planted elbows, fists and feet still to 0.0 mm. The fists: no finger piece inside another, the thumb 4.8 mm
(female) and 4.0 mm (male) off the fingers, the fingertips 0.3 to 2.5 mm short of the palm. The top of the head is
0.52 m (female) and 0.53 m (male) over the floor lying still and 0.53 m crawling; the wrists lie 8.5 and 11 cm
(female), 9 and 11.5 cm (male) from the centre line lying still and 9 to 10 cm planted in the crawl.

What had to differ from the Quaternius female's numbers, and why (`BODIES` in the build has every number):

- **Thinner forearms, smaller hands.** The elbow joint rests 3.3 cm over the floor on the female and 4.0 cm on the
  male (the Quaternius female's 4.1), the wrist 5.05 and 5.5 cm under a fist (6.55) and 3.7 and 4.0 cm under a flat
  hand (4.5). Their fingers are a person's length (the hand 0.18 and 0.195 m against the library rig's 0.23), so the
  shared fist left the fingertips 12 to 20 mm short of the palm: each body's fist curls 5 to 12 degrees more at the
  middle joints and 20 to 27 more at the last.
- **A flat belly and round knees.** With the library leg, which hangs the knee 5 cm under the line from hip to
  ankle, the knees held the pelvis 4.4 cm off the floor. The lying leg is as straight as the solver allows (0.999
  of its length; 0.996 while it drags in the crawl), so the belly and the thighs both rest on the floor, and the
  toes bend at 3.3 and 3.6 cm, the feet being thicker.
- **Longer upper arms, shorter forearms** (0.262 and 0.280 m, 0.248 and 0.265 m; the Quaternius female's 0.221 and
  0.273 m). On elbows placed as hers the upper arms stood upright under the shoulders and the fists lay 14 to 15 cm
  from the centre line. The elbows rest 7 cm outside the shoulders (hers 9.5) and 9 cm (female) and 12 cm (male)
  ahead of them (hers 3.5), the forearms 31 and 38 degrees inward, and the collarbones push less (2 degrees
  crawling on the female; the male's draw back 4 lying and 12 crawling), which keeps the head at the height it has
  lying still when the crawl starts.
- **The transitions.** Going down, the pelvis passes 1.5 cm higher where the back knee comes over the floor, the
  left hand reaches 12 cm less far back over the front knee (the longer upper arm went 29 to 36 mm through the
  shin), the knees stay out to the side until the feet are down (pointing down as they lie, they went 22 mm into
  the floor) and the ankles are still 1.2 cm up on the frame they used to arrive. Coming up, the elbows' hint
  leaves the floor by frame 2 (the forearms dipped 8 mm as the chest sank), the feet lift 2 cm more and the left
  hand waits 12 cm further outside the front knee (the thigh went 11 to 17 mm into the upper arm).

**The lying pose is not a mirror of itself** on these two bodies (`IDLE_SIDES`, `IDLE_HEAD`, `IDLE_STAGGER`): the
left leg lies straight, 12 cm from the centre line, on its instep; the right leg lies 19 cm out with the knee
turned out and a little bent, on the inner edge of its foot, which points 10 degrees less; the right elbow lies
8 cm ahead of the left with its forearm 31 degrees inward against the left's 38; the head is turned 7 degrees to
the left and tipped 3, and drifts about that. The Quaternius files keep their even legs (their elbows are staggered
5 cm).

**Neither transition passes through a mirror of itself** on these two bodies (`DOWN_HANDS`, `UP_HANDS`,
`DOWN_TURN`, `UP_TURN`, `UNDER_KNEE`). The first form files moved both arms from one table with a flipped sign
under a square chest: the hands landed on the same frame going down, and coming up they pushed 22 mm from a mirror
of each other for six frames with the shoulders exactly level. Now, going down, the left hand is flat on the floor
at frame 8 and has rolled onto its fist by 18 while the right, which lies 10 cm further ahead, lands at 11 and
has rolled by 21; the chest turns 8 degrees to its left and rolls 6 as it dives. Coming up, the left
hand opens first and is planted 5 cm behind its shoulder's line by frame 7, the right 6 cm ahead of it and 5 cm
wider by frame 9; the chest turns 8 degrees to its left again and rolls 6 the other way as it pushes, the right
knee draws in under the body and the left swings wide. The build measures every frame of every clip (each left joint against
the right one's place mirrored across the body's middle, `mirror` in its report) and fails under 90 mm at the
wrists and 25 mm at the shoulders (`MIRROR_LIMIT`; a crawl's shoulders pass level twice a stride and are not
held); `test_prone_clips.gd` holds the same in Godot. The Quaternius files keep their even transitions, byte for
byte.

## Weapon

The four clips above are **weapon-free**: both hands are fists on the floor and carry weight, so a weapon in the
hand would be dragged through the floor. The code hides the weapon while the body lies and brings it back when it
aims, with the clips below.

## Prone aim clips

Three more clips of GDStudio's own, made from nothing (kit #1111), one file a body: `prone_aim.glb` solved on
`form_female` (the body the character scene wears; the `AnimationPlayer`'s library `prone_aim`) and
`prone_aim_male.glb` solved on `form_male` (the Animation's `prone_aim_libraries` gives it to that body). They aim
the template's pistol lying down and are named on the pistol's `WeaponDef` (`prone_aim_clip`, `prone_aim_up_clip`,
`prone_aim_down_clip`); the game plays them over the prone idle and the crawl from `spine_01` up and blends them by
the look.

| Clip in the file | Look | Length | What it is |
| --- | --- | --- | --- |
| `Prone_Aim_Neutral_Loop` | level | 3.0 s (90 frames), loops | Flat on the belly behind the pistol, the chest on the floor, both arms ahead (the right, the firing arm, at 0.95 of its length; the left at 0.89), both hands on the pistol in front of the right eye, the grip's foot 6 to 9 mm over the floor, the left forearm resting on the floor, the head low and tipped a little to the left. One slow breath that leaves the pistol still. |
| `Prone_Aim_Up_Loop` | 20 degrees up | the same | The arms lift the pistol 8 cm, the head comes up with the look. |
| `Prone_Aim_Down_Loop` | 25 degrees down | the same | The hands rise 1 cm so the muzzle clears the floor (6 cm over it) and the wrists point the pistol down. |

**No side mirrors the other** (kit page `tools/blender/own-animation.md#feel`). The left shoulder is pushed ahead and
the chest turned after it (8 degrees on `form_female`, 7 on `form_male`), as a two-handed hold turns the support
side toward the target; the right arm is the straighter one, the left elbow lies lower and wider, on the floor; the
pistol is 35 to 40 mm to the right of the body's middle; the head is turned and tipped to the left. Each side has
its own numbers in the build's `BODIES`, and the build fails when the left elbow is less than 30 mm, or the left
shoulder less than 8 mm, from the right one's reflection (they are 52 to 69 mm and 94 to 96 mm).

**Why one file a body.** The first set was solved on the Quaternius female and played on every body. On the
prototype bodies (kit #1187), whose arms and hands differ, the hold had to move the left elbow 58 to 100 mm, the
left hand stopped 3 to 27 mm short of its marker with its fingers 3 to 17 mm inside the pistol, and the magazine
was 8 to 26 mm under the floor. Each file is now solved on its body's own skeleton and skin, with that body's own
hold (`HoldFit`).

Numbers, measured by the build on each body's own skin as the game shows it: the grip pose's wrist turn on, the
hold's fingers closed, the twist bones turned as `MannequinTwist` turns them (`build_prone_aim_clips.py --report`;
the Godot suite reads the same poses to 0.1 mm):

| | `form_female` | `form_male` |
| --- | --- | --- |
| Barrel off the look, left hand off its marker | 0.0 degrees, 0.0 mm | 0.13 degrees, 0.0 mm |
| Left arm's stretch (down, level, up); the right is 0.95 | 0.87, 0.89, 0.89 | 0.87, 0.90, 0.90 |
| Left arm's stretch between two clips, at most | 0.89 | 0.90 |
| Grip's foot over the floor (down, level, up) | 17, 9, 85 mm | 15, 6, 90 mm |
| Muzzle over the floor (down, level, up) | 62, 154, 291 mm | 59, 151, 296 mm |
| Lowest skin of the left and the right hand, level | 2.9, 29.8 mm | 4.5, 38.0 mm |
| Lowest hand or finger bone, down and level | 9.0 mm | 10.5, 11.1 mm |
| Lowest skin of the left and the right forearm, level | 1.0, 17.8 mm | 1.0, 4.6 mm |
| Wrists bent from the forearm, left and right (down, level, up) | 63 and 54, 35 and 25, 25 and 10 degrees | 52 and 42, 32 and 14, 23 and 7 degrees |
| A part of the body in another, at most | 0.0 mm | 0.9 mm |

- **In the game**, after the hold's modifiers, the hands are at most 1.1 mm (female) and 1.2 mm (male) inside the
  pistol or each other and the holding parts at most 2.8 and 1.7 mm off, the left hand's bone is 0.0 mm from its
  marker, and the hold moves the left elbow 0.0 mm (`tests/gameplay/test_prone_aim_hold.gd`, which also holds each
  hand's skin over the floor). On the live player the left hand is 0.0 to 0.1 mm from its marker at every look.
- **The chest's** skin presses 3 mm into the floor, the hands' skin stays 2 mm or more over it, and an elbow whose
  arm would lie in the floor is turned up until the arm rests 1 mm over it.
- **The lower body is the prone idle's** first pose, read from the prone library the body plays in the game
  (`--idle`): the game's filter from `spine_01` up lays these clips on that pelvis, so the chest and the hands are
  solved on it. **When a body's prone idle changes (kit #1293 solves the prone clips on the prototype bodies), build
  its aim clips again with the new file**, or the hands ride higher or lower by what the pelvis moved.
  The files here are built on `prone_form_female.glb` and `prone_form_male.glb` (kit #1323 lowered the `form`
  female's pelvis 42 mm; on the files built on `prone.glb` the live prone reload of gdstudio #1265 read the left
  hand 14 mm and the magazine 28 mm under the floor). They hold the library's 65 bones: the twist bones are turned
  for every measure and never keyed (the game's `MannequinTwist` turns them after the clip).
  They were built again on the two-handed grip of gdstudio #1171 (the `SupportHand` marker moved and the right thumb
  rests on the left thumb's root): on the old files the left elbow moved 18 mm (`form_female`) and 45 mm
  (`form_male`) to reach the new marker. And again on the seat of gdstudio #1262 (the middle finger under the guard):
  on the files before it, a little finger went 6.4 to 9.0 mm under the floor.
  The reload is built after the aim, since it joins the aim's first pose.
- **Past 25 degrees down** the pose stays on the down clip and the aim layer stops there too
  (`ProneTuning.aim_limits`, `pitch_down` 25): turned on to the 40 degrees of the look-down limit, the spine put the
  muzzle 21 cm under the floor.
- **The Quaternius mannequins** have no solved hold since kit #1187 and no aim clips of their own: a game that wears
  them plays the default file, unmeasured.

Why the arms are stretched (read before the clips were made):

| Source | What it says |
| --- | --- |
| US Army, FM 23-35 Combat Training with Pistols (the prone position, paragraph 2-8; <https://biggerhammer.net/manuals/23-35/FM23-_3.htm>) | Lie flat facing the target, the arms extended in front with the firing arm locked; the arms may be slightly unlocked for high targets; rest the butt of the weapon on the ground for single well-aimed shots; wrap the other hand's fingers round the firing hand's; keep the head down between the arms and behind the weapon. |
| Shooting USA, a professional shooter's tip on prone pistol (<https://archive.shootingusa.com/PRO_TIPS/JULIE2022-5PRONE/julie2022-5prone.html>) | The grip is the standing one; the gun flat on the ground is the most stable position; a leg drawn up a little or a lean onto a shoulder when the target cannot be reached. |
| American Rifleman, alternative shooting positions (<https://www.americanrifleman.org/articles/2012/6/25/alternative-shooting-positions>) | Flat, or rolled slightly onto a side, by preference or cover. |
| PopMatters on Metal Gear Solid V (<https://www.popmatters.com/getting-to-know-the-ground-in-metal-gear-solid-v-2495486441.html>) | On the ground the character shimmies forward and shoots with the arms out in front. |
| PC Gamer on Ghost Recon Breakpoint (<https://www.pcgamer.com/ghost-recon-breakpoint-tips-guide>), GamesRadar on PUBG's aiming (<https://www.gamesradar.com/uk/playerunknowns-battlegrounds-aiming-scope-controls-pubg/>) | Prone costs horizontal turning; holding aim in third person pulls the camera to a tighter over-the-shoulder view. No game studied publishes its prone camera's numbers. |

What the clips take from it: flat and straight behind the pistol, arms stretched, the grip's foot on the ground
looking level, arms unlocked looking up, head low behind the sights. Elbows planted with raised forearms are a
rifle's position: the first version of these clips had them, and the pistol sat 10 cm in front of the face, hidden
by the head from the player's camera, with the wrists bent past 90 degrees to look down. The clips stop at 25
degrees down (a body flat on the ground cannot point a pistol further down); the game holds that pose for the rest
of the look.

`build_prone_aim_clips.py` imports `build_prone_clips.py` (the solver, the keying, the export) and places the
hands from the hold the game uses: `tools/hold/dump_aim_seat.gd` writes, for each body, the pistol's seat on `hand_r`,
the left hand's marker, the grip pose's wrist turn, the finger rotations of the grip, trigger and support poses and
every bone's rest, and once the muzzle and the grip's foot; the build puts each hand bone where that seat carries the
pistol along the look and keys the hold's fingers. Run the dump and both builds again after the seat, the marker, a
hand pose or the pistol changes. It fails before it exports when a loop does not close, the barrel is more than 0.3
degrees off its look, a wrist moves in the breath, the rig's rests differ from Godot's, the left arm is past 0.985 of
its length in a clip or between two, the pistol's foot or muzzle is at the floor, a hand's skin or a hand bone is
under the Godot test's floor limits, an arm's skin is more than 1 mm under the floor, the two sides mirror each
other, or a part of the body goes more than 5 mm into another. Blender exits 0 when the script raises: read the
output for `EXPORTED` and check the file's time.

```text
godot --headless --path game -s res://tools/hold/dump_aim_seat.gd -- <aim_seat.json>
blender -b --factory-startup -P build_prone_aim_clips.py -- --body female --model <form_female.glb>
    --hold <aim_seat.json> --idle <prone_form_female.glb> --out <prone_aim.glb>
blender -b --factory-startup -P build_prone_aim_clips.py -- --body male --model <form_male.glb>
    --hold <aim_seat.json> --idle <prone_form_male.glb> --out <prone_aim_male.glb>
```

`tools/capture/prone_aim_tour.tscn` plays the aim in the game from the player's camera, or from the side, the front,
above and close on the hands (`PRONE_AIM_VIEW`), on either body (`PRONE_AIM_MODEL=male`); `PRONE_AIM_TOUR=looks`
holds the three looks, and `PRONE_AIM_FULL_UP=1` opens the look-up limit to the up clip's 20 degrees.

## Prone reload clip

One more clip of GDStudio's own, made from nothing (kit #1185): the `AnimationPlayer`'s library `prone_reload`, one
file a body as the aim clips are, `prone_reload.glb` solved on `form_female` (the scene's own) and
`prone_reload_male.glb` on `form_male` (`CharacterAnimation.prone_reload_libraries` gives it to that body).
`Prone_Reload_Pistol` (1.67 s, 50 frames, plays once) reloads the template's pistol lying
down and is named on the pistol's `WeaponDef` (`prone_reload_clip`); the game plays it on the reload layer from
`spine_01` up, stretched to the weapon's `reload_time`, in place of the library's standing `Pistol_Reload`, which
folds the arms under a lying chest.

| Share of the clip | What happens |
| --- | --- |
| 0 | The first pose of `Prone_Aim_Neutral_Loop`, to the bit. |
| 0 to 0.22 | The chest rolls 11 degrees onto the right side and the left shoulder lifts. The right elbow comes down to the floor ahead of and outside its shoulder and props the arm; the forearm rises 26 degrees and brings the pistol back 15 cm and up, in front of the face, the muzzle 24 degrees up and 8 to the left (the grip's foot 0.15 to 0.19 m over the floor). The left hand opens, waits at the far end of its way while the right thumb comes back onto the frame, and lets go by 0.10, as the game's hold has it. |
| 0.07 to 0.26 | The magazine well cants 65 degrees toward the left hand, once that hand is off the pistol. |
| 0.10 to 0.26 | The left hand swings round the outside of its shoulder, back along the body to the belt at the left hip (there from 0.22 to 0.26). Its fingers open for the new magazine by 0.21, the magazine is in the hand at 0.25 and the fingers close on it by 0.29 (the hold's carry poses). |
| 0.26 to 0.40 | It swings back the same way to the line under the grip, the magazine's length (12 cm) down the grip's own line. |
| 0.40 to 0.54 | The magazine goes up the grip's line, the fingers opening off it as the grip's foot comes down over them, and the heel of the palm pushes it home; the head tips 7 degrees toward the well. At 0.54 the pistol gives 6 mm as the magazine seats. |
| 0.70 to 0.83 | The pistol turns upright again, before the left hand comes back onto it. |
| 0.71 to 0.88 | The left hand drops straight down off the magazine, goes round the grip's foot, waits at the far end of its way while the right thumb makes room, and takes its place on the pistol. |
| 0.74 to 0.96 | Both arms stretch out, the chest rolls back flat. |
| 1 | The first pose of the prone aim again. |

As the left hand lets go (to 0.09) the pistol rises 2 cm more for a moment, so the hand's way off it, which leads
down the grip, stays over the floor; the right index finger leaves the trigger for the frame by 0.06 and is back on
it from 0.94; from the grab at the belt on the left hand's fingers are the hold's own (`SupportHandPlan.fingers`), so
the clip keys the very poses the hold puts on them and the blend of the two is that pose at any weight.

Numbers, measured by each body's build on its own skin as the game shows it (the grip's wrist turn on, the fingers in
the hold's poses, the twist bones turned; `build_prone_reload_clip.py --report`):

| | `form_female` | `form_male` |
| --- | --- | --- |
| First and last pose off the body's prone aim (this build's solve, and the first frame of its aim file) | 0.0 degrees | 0.0 degrees |
| Left hand's bone off the hold's place wherever the hold has it (to 0.082 and from 0.40) | 0.0 mm | 0.0 mm |
| The propped elbow moves while the pistol is reloaded (0.22 to 0.74) | 0.9 mm | 0.9 mm |
| The propped elbow's joint over the floor (the arm's skin rests 1 mm over it) | 2.2 cm | 2.6 cm |
| Pistol's foot over the floor, at the ends and while it is reloaded | 0.8 and 14.8 to 17.2 cm | 0.6 and 16.6 to 19.1 cm |
| Muzzle over the floor | 15.3 to 31.6 cm | 15.1 to 33.4 cm |
| Lowest skin of the left hand, the right hand (both at the aim's pose) | 3.3 mm, 3.2 mm up | 5.8 mm, 12.0 mm up |
| The new magazine in the left hand, at its lowest (at the belt), and in the body at most | 12.9 mm up, 0.0 mm in | 14.1 mm up, 0.0 mm in |
| Lowest skin of either arm (they rest on the floor) | 0.9 mm up | 0.9 mm up |
| Chest's skin (pressed on the floor, as in the aim) | 3.0 mm in | 3.0 mm in |
| Right wrist bent | 17 to 22 degrees | 19 to 23 degrees |
| Left wrist bent: at most (leaving for the belt), under the magazine, at the belt | 67, 64, 33 degrees | 61, 58, 34 degrees |
| Left arm stretched, at most (the aim's own) | 0.91 of its length | 0.92 |
| A part of the body in another, on all 51 frames | 0.0 mm | 0.0 mm |

- **It joins the prone aim.** The lower body is the prone idle's on every frame, so the game's filter from
  `spine_01` up joins it lying still or crawling.
- **The left hand is where the game's hold wants it.** The shares are the standing reload's, read from `WeaponHold`
  (`tools/hold/dump_aim_seat.gd` writes them with each body's `MagazineHand` marker, the way its opened hand leaves
  the weapon, its opened, magazine and carry finger poses, its approach under the magazine, the shares over which
  the fingers let go of the new magazine and the magazine's own corners); `ReloadHold.plan` is `SupportHandPlan` in
  Python. In the game the hold moves either body's hand under 4 mm and its elbow under 10.
  Between, the clip's own arm goes to the belt.
- **Either arm rests on the floor where it would dip into it:** the right elbow on its way down to its prop and
  back up, the left one as the hand comes back onto the pistol; its pole is turned up frame by frame until the
  skin is 1 mm over the floor, as the aim clips do.
- **Nothing passes through anything** (`../limb_overlap.py`; the two hands on each other are the game's hold,
  measured there), and the left hand is never within 5 cm of the barrel's line ahead of the muzzle.
- **In the game** (`tests/gameplay/test_prone_reload_hold.gd`, the skinned mesh of both bodies after the hold's
  modifiers, each on its own file): the right hand holds within 2 mm in and 5 mm off at every 2 hundredths, the
  left hand on the pistol at the ends and under the magazine from 0.54 to 0.71 within the same limits and no deeper
  than 2 mm in anything on the way, at every hundredth it moves near the pistol; the new magazine is in the hand
  from 0.25 to 0.54, 5 mm or more over the floor, and within 1.5 mm of the grip's line as it goes in.
- **After the hold changed on main** (kit #1171's two-handed grip, #1262's seat, #1306's magazine in the left
  hand) the files solved on the old hold failed 279 checks of the two suites. The build was ported to the new plan
  and both bodies built again; with the magazine's new way in (12 cm down a line that leans with the grip) the
  pistol canted 45 degrees left the left hand 30 to 38 mm under the floor, and canted 65 degrees while that hand
  came back on, its wrist bent 86 to 90 degrees: hence the higher forearm and the cant held only while the hand
  is away.
- **Before each body had its own file** the clip solved on the Quaternius female played on both prototype bodies
  with the left hand 8.2 mm (`form_female`) and 25.1 mm (`form_male`) off its marker, fingers 7.8 and 17.9 mm in
  the pistol, finger bones up to 41 mm and the magazine 25 mm under the floor (322 failed checks of the two suites).

How a pistol is reloaded lying down (read before the clip was made):

| Source | What it says |
| --- | --- |
| US Marine Corps, Pistol Marksmanship (MCRP 3-01B), chapter 2, reloading the pistol (<https://gutenberg.org/ebooks/75995>) | The firing grip stays; the pistol is pulled in close to the body with the magazine well canted inboard about 45 degrees; the left hand takes a filled magazine from the ammunition pocket, the index finger along its front, turns it up to the well, and the heel of the hand seats it; both hands roll back into the two-handed grip and the pistol is presented again. |
| The same manual, chapter 4, the prone positions, and chapter 8, the one-handed reload lying down | Lying flat (isosceles prone) or rolled onto the firing side with the other knee drawn up; the head may rest against the firing arm. For the reload with one hand the shooter rolls onto a side and puts the pistol down or between the knees, the well facing out. |
| US Army, FM 3-23.35, appendix B (<https://www.globalsecurity.org/military/library/policy/army/fm/3-23-35/appb.htm>; read as a search summary, not the page) | A prone firing table with two five-round magazines and a rapid magazine change between them, in the position. |
| Shooting Illustrated, handgun reloads (<https://www.shootingillustrated.com/content/handgun-reloads-how-to-expert-tips>) | Lists reloads lying on the belly and on the back among the positions to practise (read as a search summary, not the page). |

What the clip takes from it: the right hand never leaves the grip; the pistol comes back close, canted toward the
left hand (65 degrees here, more than the manual's 45, so the magazine's way in clears the floor); the body rolls onto
the firing side, which frees the left hip; the left hand goes to the belt
at the left hip, comes up under the grip and seats the magazine with the heel of the palm; both hands take the grip
again and the pistol goes back out. No source gives joint angles for it lying down: the prop on the right elbow,
the 11 degrees of roll and the muzzle's 24 degrees follow from the floor (the hand needs a magazine's length under
the grip) and from the hold's limits. The magazines and the slide are the hold's, as in the standing reload (kit #1052):
the old magazine drops, the new one rides the left hand, the slide runs forward at the reload's last sound.

`build_prone_reload_clip.py` imports `build_prone_aim_clips.py` (the hold, the trunk, the measures) and through it
`build_prone_clips.py`; what differs between the bodies is in its `BODIES`. It fails before it exports when the
first or the last pose is not the prone aim's, a target is missed, the rig's rests differ from Godot's, the left
hand is more than 0.5 mm off the hold's place where the hold has it, the propped elbow moves more than 4 mm, the
lower body differs from the prone idle's, a hand's or an arm's skin is more than 1 mm under the floor, the chest's
more than 6, or the pistol's foot or muzzle at it, the new magazine in the left hand is under 2 mm over the floor
or more than 5 mm in the body, the left hand is within 5 cm of the barrel's line ahead of the muzzle, a wrist is bent
more than 75 degrees, an arm is past 0.992 of its length, or a part of the body goes more
than 5 mm into another on any frame. Blender exits 0 when the script raises: read the output for `EXPORTED`.

```text
godot --headless --path game -s res://tools/hold/dump_aim_seat.gd -- <aim_seat.json>
blender -b --factory-startup -P build_prone_reload_clip.py -- --body female --model <form_female.glb>
    --hold <aim_seat.json> --idle <prone_form_female.glb> --aim <prone_aim.glb> --out <prone_reload.glb>
blender -b --factory-startup -P build_prone_reload_clip.py -- --body male --model <form_male.glb>
    --hold <aim_seat.json> --idle <prone_form_male.glb> --aim <prone_aim_male.glb> --out <prone_reload_male.glb>
```

Run the dump and both builds again after the seat, a marker, a hand pose, the hold's way or a share of its Reload
group changes, and after a body's aim file is rebuilt; when the hold's plan itself changes (`SupportHandPlan`,
`WeaponHold.refresh`), port the change to `ReloadHold` first.
`tools/capture/prone_aim_tour.tscn` with `PRONE_AIM_TOUR=reload` plays a shot
and the reload in the game, from the player's camera or the tour's own views.

## How they are made

`build_prone_clips.py` solves every frame from a few targets (where the pelvis lies, how the spine arches, where each
elbow, hand and foot rests on the floor), keys the result on the armature of the mannequin it is given (`--model`, with
`--body` naming whose numbers to use) in the pinned Blender and
exports the armature with a one-triangle stand-in mesh, so the file has a skin for Godot's `Skeleton3D` and no copy of
the mannequin. The chest rides on the planted elbows: the spine pitches and rolls by the amount that keeps each
shoulder one upper arm from its elbow. The only pose read from the library is frame 0 of `Crouch_Idle_Loop`, where the
transitions join. The build fails before it exports when a loop does not close, a planted joint slides, the body sinks
more than 2 cm into the floor, a transition misses the pose it joins, a part of the body goes more than 5 mm into
another (`../limb_overlap.py`, the check the template's clip builds share), a hand of the
female (in the male's file: a hand, forearm, thigh or shin of the male; in a `form` body's file: its hands,
forearms, thighs, shins and feet) goes more than 5 mm under the floor on any
frame, or the fist does not fit (a finger
piece more than 3 mm inside the palm or another finger, or the thumb more than 5 mm off the fingers:
`fist_numbers`, on the mesh's own pieces). The female's file is held to the overlap and fist limits on both
mannequins, as it was made; the male's and each `form` body's on that body, the only one that plays it. The
report (`--report`) has every
frame's lowest hand, forearm, thigh and shin vertex on both mannequins (`floor_mm`) and the fists' fit (`fist_mm`).
A rebuild writes the same bytes, so `cmp` against the committed file proves a change to the script left a file alone.

```text
blender -b --factory-startup -P build_prone_clips.py -- --model <mannequin_female.glb> --other <mannequin_male.glb> --library <ual1.glb> --out <prone.glb>
blender -b --factory-startup -P build_prone_clips.py -- --body male --model <mannequin_male.glb> --other <mannequin_female.glb> --library <ual1.glb> --out <prone_male.glb>
blender -b --factory-startup -P build_prone_clips.py -- --body form_female --model <form_female.glb> --other <form_male.glb> --library <ual1.glb> --out <prone_form_female.glb>
blender -b --factory-startup -P build_prone_clips.py -- --body form_male --model <form_male.glb> --other <form_female.glb> --library <ual1.glb> --out <prone_form_male.glb>
blender -b --factory-startup -P ../limb_overlap.py -- --clips <prone_form_female.glb> --model <form_female.glb> --brief --json <prone_form_female_overlap.json>
blender -b --factory-startup -P render_clip_sheets.py -- --model <mannequin.glb> --clips <prone.glb> --out <folder> --travel Crawl_Fwd_Loop=0.618
blender -b --factory-startup -P render_clip_sheets.py -- --model <mannequin.glb> --clips <prone.glb> --out <folder> --clip Crawl_Fwd_Loop --travel Crawl_Fwd_Loop=0.618 --views top --scale 1.35 --ahead 0.6 --frames 15 --wrap 5 --tile 420x360
```

`render_clip_sheets.py` renders any clip file on any of the four bodies the way Godot plays it (a prototype body's
twist bones turned, its full level of detail only), from the side, the front and
the top; the third line is the close-up of the arms from above over one cycle, and `--range 12-24` spreads the
frames over a part of a clip. `tools/capture/prone_clips_tour.tscn` plays the four clips on the mannequin in Godot
from the side, the front quarter, the game camera's place and close over the arms, for a clip or stills
(`PRONE_FISTS=<folder>`: one sheet of the forearms and fists at five moments of the crawl and in the idle, from the
game camera's place, the side, the front and above; `MODEL=male`, `quaternius_female` or `quaternius_male` for
another body, each playing its own file).

## How people crawl (the research behind the arms)

Read before the arms were reworked (kit pull request #1020): the first version had the right limbs moving together
and the right speed, but both forearms pointed almost straight ahead, shoulder-width apart, which nobody does.

| Source | What it says |
| --- | --- |
| US Army, low and high crawl (FM 21-75, 1984, chapter 3; task 071-326-0502 of STP 21-1-SMCT; an ROTC course text that restates them, <https://www.uakron.edu/armyrotc/MS1/9.pdf>) | Low crawl: the body flat; both arms pushed forward and one leg drawn up together, then a pull with both arms and a push with that leg; legs switched when tired. High crawl: the trunk off the ground on the forearms and lower legs, knees kept behind the buttocks; the right elbow moves with the left knee, then the left elbow with the right knee. |
| Skvortsov, Anisimov and Aizenshtein, Experimental Study of Military Crawl as a Special Type of Human Quadripedal Automatic Locomotion, Applied Sciences 11(16), 7666, 2021 (<https://doi.org/10.3390/app11167666>): eight adults crawling 4 m on their bellies, optical motion capture | A cycle takes 2.2 s (plus or minus 0.8) and covers 1.2 m at 0.5 m/s. The other side starts half a cycle later (48 to 52 %). Seen from above, the knee bends through 117 degrees and the hip through 79, both peaking at 33 to 36 % of the cycle; the elbow bends through about 90 degrees and the shoulder through 75 to 78, peaking at 51 to 59 %: the arm of a side follows its own leg by about a fifth of a cycle, so it moves with the other side's leg. The shoulder line turns against the hip line by up to 56 degrees, one way at 32 % and the other at 79 %. |
| Vitali, Cain, Davidson and Perkins, Human crawling performance and technique revealed by inertial measurement units, Journal of Biomechanics 84, 2019 (<https://doi.org/10.1016/j.jbiomech.2018.12.030>): 33 people on a military obstacle course | The fast crawlers use a diagonal gait: an arm and the opposite leg move together. The slow ones have longer cycles and looser coupling. |
| Patrick, Noah and Yang, Interlimb Coordination in Human Crawling Reveals Similarities in Development and Neural Control With Quadrupeds, Journal of Neurophysiology 101, 2009 (abstract) | Adults on hands and knees pair the diagonal limbs like a trot; at low speeds the four limbs move at even intervals. |
| Twelve public-domain photographs of soldiers in the low and the high crawl on Wikimedia Commons (search: low crawl soldier, high crawl soldier; among them four soldiers side by side in a 25 m high crawl and a low crawl sequence of three), kept in the workspace's reference folder | Every one has the elbows outside the shoulders and the forearms pointing inward, 45 to 80 degrees from the body's long axis, the hands or fists under the chin on the centre line. The reaching arm's hand lands in front of the face, across the centre line or on it; the pulling arm's forearm ends lying nearly across under the chest. One hand is always ahead of the other. Nobody has parallel forearms. |

What the clips take from it:

| What | In people | In the clips |
| --- | --- | --- |
| Forearm to the body's long axis | 45 to 80 degrees inward on the planted arm (photographs) | 40 degrees planted in the crawl, 29.5 in the idle: a stronger angle with wider elbows put the forearm 5 to 11 mm into its own shoulder at the end of the pull and the chest 2 cm into the floor on this rig |
| How far the hands come in | fists under the chin, on the centre line or across it | wrist 7 cm from the centre line, knuckles on it (crawl); wrists 12.5 cm out, knuckles 6 cm short of it (idle) |
| How the forearm and hand rest | the forearm on its outer edge, the thumb's side up, the hand a fist or closed on the weapon (four of the photographs looked at again for the hands, eleven soldiers: none has a palm flat on the ground) | rolled 45 degrees onto the outer edge, the hand a fist in line with the forearm, the thumb outside |
| One hand past the other | the reaching hand lands ahead of the other, in front of the face | a hand plants 0.29 m ahead of the other (the whole stride), and passes outside it on the way, the forearm opened to 14 degrees |
| Which limbs move together | an elbow with the opposite knee (high crawl, the fast crawlers, the motion capture) | the right elbow with the left foot, then the other pair, half a cycle apart |
| The elbow's path | lifts a few centimetres, travels forward outside the shoulder, lands ahead of it and stays put while the trunk passes over it, ending beside the ribs | lifts 5 cm, swings 3 cm outward, lands 17 cm ahead of the shoulder and 8.5 cm outside it, stays put for 52 % of the cycle and ends 13 cm behind the shoulder |
| Stride and time | 1.2 m and 2.2 s a cycle, 0.5 m/s, in people who do not practise it | 0.58 m and 0.93 s, 0.618 m/s: a shorter, quicker pull, since the forearm is planted whole (a person also slides the hand); the game slows the clip for a slower crawl |

## Where it comes from

The motion is GDStudio's own work, under this repository's licence; nothing in it is copied from another game, pack or
capture. The skeleton in `prone.glb` and in `prone_male.glb` (bone names, parents and rest pose) is the Quaternius
universal rig's, CC0, taken from `assets/characters/mannequin/mannequin_female.glb` and `mannequin_male.glb` (their
`LICENSE.md` has the source); the one in the `form` files is GDStudio's prototype rig's 65 library bones (the same
names, parents and rest rotations, the bodies' own bone lengths), from `assets/characters/prototype/`; so are those in
`prone_aim.glb`, `prone_aim_male.glb`, `prone_reload.glb` and `prone_reload_male.glb`.
The timing was set after
studying how shipped games and the army's low crawl are described (kit pull request of #1009).
