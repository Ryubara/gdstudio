# Prone and crawl clips

Four clips for a character that lies down and crawls, made by GDStudio from nothing (kit #1009) because the Universal
Animation Library has none, and three that aim the pistol lying down
([Prone aim clips](#prone-aim-clips)).
They are in `prone.glb`, which Godot imports as an `AnimationLibrary` the same way as
`assets/animation/universal/`: add it to an `AnimationPlayer` as the library `prone` and the clips are
`prone/Prone_Idle`, `prone/Crawl_Fwd`, `prone/Crouch_To_Prone` and `prone/Prone_To_Crouch` (the import drops `_Loop`
from a looping clip's name and makes it loop). The player scene does not hold the library yet: the prone stance
(kit #1012) adds it with the code that plays it.

| Clip in the file | Length | Loops | What it is |
| --- | --- | --- | --- |
| `Prone_Idle_Loop` | 3.0 s (90 frames) | yes | Lying on the belly, propped on the forearms, which point inward and rest on their outer edges, the hands closed into fists near the centre line in front of the head, the right a little ahead; one slow breath and a small drift of the head. |
| `Crawl_Fwd_Loop` | 0.933 s (28 frames) | yes | A crawl on the forearms, the body kept low: the right elbow and the left foot plant and the body is pulled over them, then the other pair. Each forearm lands pointing inward on its outer edge, its fist in front of the head and ahead of the other fist. In place. |
| `Crouch_To_Prone` | 0.9 s (27 frames) | no | From frame 0 of `ual1/Crouch_Idle`: the open hands reach for the floor ahead and catch the body, the feet go back one after the other, and as the elbows come down the forearms roll onto their outer edges and the hands close. Ends on frame 0 of `Prone_Idle_Loop`. |
| `Prone_To_Crouch` | 1.0 s (30 frames) | no | From frame 0 of `Prone_Idle_Loop`: the fists open and the hands come back beside the chest, push on flat palms, the knees draw under the body, the chest rises. Ends on frame 0 of `ual1/Crouch_Idle`. |

All four are at 30 frames a second, the library's rate, keyed on every frame, with no root motion (the game moves the
body), on the 65 bones of the Quaternius universal rig.

## Numbers for the code

Measured by the build on the female mannequin, the template's default (`build_prone_clips.py --report`):

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

On the male mannequin the same clips play (the rig is the same), but his upper arms are 5 cm longer and his limbs
thicker, so a planted elbow rolls up to 3 cm and he lies in the floor: the build measures his forearms 3.7 cm (lying
still) to 4.4 cm (crawling) and his fists 2.3 to 3.0 cm under it, and his thighs and shins about 3 cm (with flat palms
the forearms were 4.3 to 4.6 cm and the hands 3.1 to 3.5 cm under). One clip file cannot rest both bodies on the
floor; a set solved on his own body would (kit #1090). `tests/gameplay/test_prone_clips.gd` holds both models to the
bone numbers, the forearms' roll and the fists.

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
    --hold <aim_seat.json> --idle <prone.glb> --out <prone_aim.glb>
blender -b --factory-startup -P build_prone_aim_clips.py -- --body male --model <form_male.glb>
    --hold <aim_seat.json> --idle <prone.glb> --out <prone_aim_male.glb>
```

`tools/capture/prone_aim_tour.tscn` plays the aim in the game from the player's camera, or from the side, the front,
above and close on the hands (`PRONE_AIM_VIEW`), on either body (`PRONE_AIM_MODEL=male`); `PRONE_AIM_TOUR=looks`
holds the three looks, and `PRONE_AIM_FULL_UP=1` opens the look-up limit to the up clip's 20 degrees.

## Prone reload clip

One more clip of GDStudio's own, made from nothing (kit #1185), in `prone_reload.glb`: the `AnimationPlayer`'s
library `prone_reload`. `Prone_Reload_Pistol` (1.67 s, 50 frames, plays once) reloads the template's pistol lying
down and is named on the pistol's `WeaponDef` (`prone_reload_clip`); the game plays it on the reload layer from
`spine_01` up, stretched to the weapon's `reload_time`, in place of the library's standing `Pistol_Reload`, which
folds the arms under a lying chest.

| Share of the clip | What happens |
| --- | --- |
| 0 | The first pose of `Prone_Aim_Neutral_Loop`, to the bit. |
| 0 to 0.22 | The chest rolls 11 degrees onto the right side and the left shoulder lifts. The right elbow comes down to the floor ahead of and outside its shoulder and props the arm; the forearm rises 20 degrees and brings the pistol back 15 cm and up, in front of the face, the muzzle 24 degrees up and 8 to the left, the magazine well canted 45 degrees toward the left hand (the grip's foot 0.18 m over the floor). The left hand opens and lets go by 0.10, as the game's hold has it. |
| 0.10 to 0.26 | The left hand swings round the outside of its shoulder, back along the body to the belt at the left hip (there from 0.22 to 0.26), and closes on the new magazine. |
| 0.26 to 0.40 | It swings back the same way to the line under the grip, a magazine's length (10 cm) down it. |
| 0.40 to 0.54 | The heel of the palm pushes the magazine up into the grip; the head tips 7 degrees toward the well. At 0.54 the pistol gives 6 mm as the magazine seats. |
| 0.71 to 0.88 | The left hand drops off the magazine, goes round the grip's foot and takes its place on the pistol. |
| 0.74 to 0.96 | Both arms stretch out, the chest rolls back flat. |
| 1 | The first pose of the prone aim again. |

Numbers, measured by the build on the female mannequin (`build_prone_reload_clip.py --report`):

- **It joins the prone aim.** The first and the last pose are the aim's first pose (0.0 degrees, against this
  build's own solve and against the first frame of `prone_aim.glb`), and the lower body is the prone idle's on
  every frame, so the game's filter from `spine_01` up joins it lying still or crawling.
- **The left hand is where the game's hold wants it.** The shares are the standing reload's, read from `WeaponHold`
  (`tools/hold/dump_aim_seat.gd` writes them with the `MagazineHand` marker, the hand's way off the weapon and the
  approach under the magazine); `ReloadHold.plan` is `SupportHandPlan` in Python. Wherever the hold has the hand
  all the way (to 0.064 and from 0.40) the clip's bone is on the hold's place (0.0 mm in the build; in the game the
  hold moves the female's hand under 4 mm and her elbow under 10). Between, the clip's own arm goes to the belt.
- **The propped elbow** stays within 1 mm of its place while the pistol is reloaded (0.22 to 0.74), 4.7 cm over
  the floor at the joint.
- **Over the floor.** The pistol's foot is 2.2 cm up at the ends and 17.7 cm while it is reloaded, the muzzle
  16.7 to 35.8 cm; the female's hands get 3.9 mm into the floor at most (frame 48, the left hand coming back onto
  the pistol as it comes down; the limit is 5).
- **The wrists** are bent 21 to 24 degrees (right) and at most 60 (left, in mid-swing; 45 under the magazine, 28
  at the belt). The left arm is at most 0.97 of its length (the aim's own).
- **Nothing passes through anything:** 0.0 mm on both mannequins on all 51 frames (`../limb_overlap.py`; the two
  hands on each other are the game's hold, measured there), and the left hand is never within 5 cm of the
  barrel's line ahead of the muzzle.
- **In the game** (`tests/gameplay/test_prone_reload_hold.gd`, the skinned mesh of both mannequins after the hold's
  modifiers): the right hand holds within 2 mm in and 5 mm off at every 2 hundredths, the left hand on the pistol
  at the ends and under the magazine from 0.54 to 0.71 within the same limits and no deeper than 2 mm in anything
  on the way, at every hundredth it moves near the pistol.
- **On the male mannequin** the same clip plays inside the same limits: his upper arms are 5 cm longer, so his
  propped arm carries the pistol 7 to 9 cm from where the clip's left hand goes, which the hold's reach takes up;
  without the hold his left hand would be 13 mm into the floor as it lets go.

How a pistol is reloaded lying down (read before the clip was made):

| Source | What it says |
| --- | --- |
| US Marine Corps, Pistol Marksmanship (MCRP 3-01B), chapter 2, reloading the pistol (<https://gutenberg.org/ebooks/75995>) | The firing grip stays; the pistol is pulled in close to the body with the magazine well canted inboard about 45 degrees; the left hand takes a filled magazine from the ammunition pocket, the index finger along its front, turns it up to the well, and the heel of the hand seats it; both hands roll back into the two-handed grip and the pistol is presented again. |
| The same manual, chapter 4, the prone positions, and chapter 8, the one-handed reload lying down | Lying flat (isosceles prone) or rolled onto the firing side with the other knee drawn up; the head may rest against the firing arm. For the reload with one hand the shooter rolls onto a side and puts the pistol down or between the knees, the well facing out. |
| US Army, FM 3-23.35, appendix B (<https://www.globalsecurity.org/military/library/policy/army/fm/3-23-35/appb.htm>; read as a search summary, not the page) | A prone firing table with two five-round magazines and a rapid magazine change between them, in the position. |
| Shooting Illustrated, handgun reloads (<https://www.shootingillustrated.com/content/handgun-reloads-how-to-expert-tips>) | Lists reloads lying on the belly and on the back among the positions to practise (read as a search summary, not the page). |

What the clip takes from it: the right hand never leaves the grip; the pistol comes back close, canted 45 degrees
toward the left hand; the body rolls onto the firing side, which frees the left hip; the left hand goes to the belt
at the left hip, comes up under the grip and seats the magazine with the heel of the palm; both hands take the grip
again and the pistol goes back out. No source gives joint angles for it lying down: the prop on the right elbow,
the 11 degrees of roll and the muzzle's 24 degrees follow from the floor (the hand needs a magazine's length under
the grip) and from the hold's limits. The clip has no magazine in the hand and no slide to rack (the pistol's
`Magazine` does not move yet, as in the standing reload).

`build_prone_reload_clip.py` imports `build_prone_aim_clips.py` (the hold) and through it `build_prone_clips.py`. It
fails before it exports when the first or the last pose is not the prone aim's, a target is missed, the left hand
is more than 0.5 mm off the hold's place where the hold has it, the propped elbow moves more than 4 mm, the lower
body differs from the prone idle's, a hand or forearm of the female is more than 5 mm under the floor or the
pistol's foot or muzzle at it, the left hand is within 5 cm of the barrel's line ahead of the muzzle, a wrist is
bent more than 75 degrees, an arm is past 0.992 of its length, or a part of the body goes more than 5 mm into
another on either mannequin on any frame.

```text
godot --headless --path game -s res://tools/hold/dump_aim_seat.gd -- <aim_seat.json>
blender -b --factory-startup -P build_prone_reload_clip.py -- --model <mannequin_female.glb>
    --male <mannequin_male.glb> --hold <aim_seat.json> --aim <prone_aim.glb> --out <prone_reload.glb>
```

Run the dump and the build again after the seat, a marker, the hold's way or a share of its Reload group changes,
and after `prone_aim.glb` is rebuilt. `tools/capture/prone_aim_tour.tscn` with `PRONE_AIM_TOUR=reload` plays a shot
and the reload in the game, from the player's camera or the tour's own views.

## How they are made

`build_prone_clips.py` solves every frame from a few targets (where the pelvis lies, how the spine arches, where each
elbow, hand and foot rests on the floor), keys the result on the female mannequin's armature in the pinned Blender and
exports the armature with a one-triangle stand-in mesh, so the file has a skin for Godot's `Skeleton3D` and no copy of
the mannequin. The chest rides on the planted elbows: the spine pitches and rolls by the amount that keeps each
shoulder one upper arm from its elbow. The only pose read from the library is frame 0 of `Crouch_Idle_Loop`, where the
transitions join. The build fails before it exports when a loop does not close, a planted joint slides, the body sinks
more than 2 cm into the floor, a transition misses the pose it joins, a part of the body goes more than 5 mm into
another on either mannequin (`../limb_overlap.py`, the check the template's clip builds share), a hand of the
female goes more than 5 mm under the floor on any frame, or the fist does not fit on either mannequin (a finger
piece more than 3 mm inside the palm or another finger, or the thumb more than 5 mm off the fingers:
`fist_numbers`, on the mesh's own pieces). The report (`--report`) has every frame's lowest hand and forearm vertex
on both mannequins (`floor_mm`) and the fists' fit (`fist_mm`).

```text
blender -b --factory-startup -P build_prone_clips.py -- --model <mannequin_female.glb> --male <mannequin_male.glb> --library <ual1.glb> --out <prone.glb>
blender -b --factory-startup -P render_clip_sheets.py -- --model <mannequin.glb> --clips <prone.glb> --out <folder> --travel Crawl_Fwd_Loop=0.618
blender -b --factory-startup -P render_clip_sheets.py -- --model <mannequin.glb> --clips <prone.glb> --out <folder> --clip Crawl_Fwd_Loop --travel Crawl_Fwd_Loop=0.618 --views top --scale 1.35 --ahead 0.6 --frames 15 --wrap 5 --tile 420x360
```

`render_clip_sheets.py` renders any clip file on either mannequin the way Godot plays it, from the side, the front and
the top; the third line is the close-up of the arms from above over one cycle, and `--range 12-24` spreads the
frames over a part of a clip. `tools/capture/prone_clips_tour.tscn` plays the four clips on the mannequin in Godot
from the side, the front quarter, the game camera's place and close over the arms, for a clip or stills
(`PRONE_FISTS=<folder>`: one sheet of the forearms and fists at five moments of the crawl and in the idle, from the
game camera's place, the side, the front and above; `MODEL=male` for the other mannequin).

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
capture. The skeleton in `prone.glb` (bone names, parents and rest pose) is the Quaternius
universal rig's, CC0, taken
from `assets/characters/mannequin/mannequin_female.glb` (its `LICENSE.md` has the source); the skeletons in
`prone_aim.glb` and `prone_aim_male.glb` are GDStudio's own prototype bodies' (`assets/characters/prototype/`), which
keep that rig's bone names. The timing was set after
studying how shipped games and the army's low crawl are described (kit pull request of #1009).
