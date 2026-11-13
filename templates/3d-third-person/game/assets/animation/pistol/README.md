# Pistol clips

One clip of GDStudio's own for the pistol, made from nothing (kit #1081) because the Universal Animation Library's
`Pistol_Reload` has no rack of the slide. It is in `pistol_rack.glb`, which Godot imports as an `AnimationLibrary` the
same way as `assets/animation/universal/`: add it to an `AnimationPlayer` as the library `pistol` and the clip is
`pistol/Pistol_Rack`. The dressed character holds it (`character_dressed.tscn`), and a reload of an empty pistol
ends with it (kit #1337: `RackLayer`, `WeaponHold.rack`).

| Clip | Length | Loops | What it is |
| --- | --- | --- | --- |
| `Pistol_Rack` | 0.933 s (28 frames) | no | An overhand rack of the slide. The right hand brings the pistol 16 cm in, in front of the right shoulder, cants it 36 degrees (the top to the right) and turns the muzzle 15 degrees to the left; the left hand leaves its support grip round the gun's left side, comes over the top of the slide just in front of the rear sight, comes straight down on it opened, closes on it, and pulls it back 4.5 cm while the right hand pushes the frame 3 cm forward; it lets go at the rear, follows through toward the chest and goes back to the support grip the way it came. Starts and ends on the last frame of `Pistol_Reload` (which is also its first, and the aim pose). |

At 30 frames a second, the library's rate, keyed on every frame, in place, on the 65 bones the template's bodies
share with the Universal Animation Library (the import drops the ten tracks that never leave the rest pose; the
prototype rig's 17 leaves get no key). It is keyed on the body the player wears, `form_female`
(`CharacterBodies.FEMALE`), and each body has its own hand on the slide (below). The right hand keeps the grip through
the clip
and the trigger finger stays off the trigger.

## The beats (for the code that plays it)

`gameplay/weapon/hold/pistol_slide_rack.tres` (a `SlideRack`) holds them as shares of the clip, written by the build:

| Frames | Share | What happens |
| --- | --- | --- |
| 0 to 1 | 0 to 0.036 | The left hand is on its support grip (the hold's `SupportHand`). |
| 1 to 2.5 | `leave` | It opens and lets go. |
| 2.5 to 7 | | Off the grip sideways, round the gun's left side, over the slide, opened. |
| 7 to 9 | `grip` | It comes straight down on the slide, opened (frame 8, `fingers_close`), and closes where it lies: the palm on the top, four fingers down the right side with the index finger's pad on the serrations, the thumb's pad on the left side's serrations. |
| 10 to 13 | `pull` | It pulls the slide back by `travel` (0.045 m); the pistol is pushed 3.2 cm forward against it. |
| 13 to 15 | `release` | The hand opens and leaves the slide; the slide runs home within `slam` (one frame), and the pistol nods 3 degrees. The slide's sound belongs at frame 13 to 14 (share 0.46 to 0.5). |
| 15 to 17 | | The hand follows through, 7.5 cm back off the slide's rear. |
| 17 to 25.5 | | Back round the gun's left side to the support grip. |
| 25.5 to 27 | `back` | It closes on the support grip; the last frame is the reload's. |

What plays the clip does four things, as `tests/fixtures/rack_stage.gd` does for the test and the captures:

- **Take the rack of the model's body**: `SlideRack.fit(<the model's file name>)`. `pistol_slide_rack.tres` is the
  female's and lists the male's (`pistol_slide_rack_male.tres`) in `fits`, as `WeaponHold.fits` lists a `HoldFit` a
  body. The two hands are a person's size and differ (0.181 m and 0.195 m), so each has its own place on the slide,
  its own way there and its own fingers; the shares are the clip's and the same for both.
- **Reach the left hand** to `hand_place(share)` (the hand bone's place in the pistol's space) with a `HoldArm`
  weighted by `hand_weight(share)`, elbow at `elbow`. The clip keys the hand onto the slide on the female body with
  the pistol where the clip's own right hand has it; on the male (longer arms, another seat) the same rotations
  leave the hand centimetres from the slide, and the hold moves the pistol after the clip on both (the carried arm's
  8 degrees out from the thigh), so the hand is reached the way `WeaponHold` reaches `SupportHand`. While the hand
  grips, its place is its place on the closed slide moved by exactly what the slide has moved.
- **Put the body's fingers on**: `set_fingers(<a HandPoseModifier after the hold's>, <WeaponHold.open_pose>, share)`.
  From the hold's own opened hand (as it left the support grip) to the rack's `open_pose` over the slide
  (`fingers_over`), closed to `grip_pose` from `fingers_close` to the end of `grip`, opened again through `release`
  and back (`fingers_away`). The clip keys the female's fingers the same way, so a game that leaves this out still
  closes her hand; the male's needs it.
- **Hold the support grip at the ends**: `support_weight(share)` is how far the hold has the left hand on
  `SupportHand` (the stage tells the hold it is at a reload's end by that much). Keep the hold's reload weight up
  through the rack, so the trigger finger stays off the trigger while the character aims.
- **Move the slide**: the pistol's `Slide` node by `travel * slide_pull(share)`.

## Numbers

Measured in Godot on the skinned meshes of the two bodies the template's characters wear, on every frame
(`tests/gameplay/test_pistol_rack.gd`, `tools/capture/rack_closeups.tscn`; the limits are the hold's, 2 mm in and
5 mm off):

| | `form_female` | `form_male` |
| --- | --- | --- |
| Right hand on the grip, every frame | 1.0 mm in, 3.1 mm off (the thumb's tip) | 1.2 mm in, all on the surface |
| Left hand on the slide (frames 9 to 13): deepest part | 1.4 mm in (the thumb, frame 12) | 0.9 mm in |
| Left hand on the slide: the palm, the four fingertips and the thumb's tip | all on the surface (0.6 to 1.1 mm in) | all on the surface (0.7 to 0.9 mm in) |
| Index finger's pad and thumb's pad from the middle of the serrations (limit 20 mm) | within it | within it |
| Left hand on its support grip (the ends) | 1.5 mm in, 2.2 mm off | 1.6 mm in, 1.8 mm off |
| Either hand on the way, every half frame, the pistol carried (deepest in the gun or the other hand) | 1.5 mm (closing on the support grip, frame 27) | 2.3 mm (as it lets go, frame 13.5) |
| The same with the pistol where the clip has it (the arm in, as when aiming) | 1.5 mm (frame 27) | 2.3 mm (frame 13.5) |
| Left hand's bone from its place on the slide | 0.0 mm | 0.0 mm |
| Limbs through each other where the rack moves the hand (`../limb_overlap.py`, the build; limit 5 mm) | 1.7 mm (frame 12) | 0.0 mm |

These are on the two-handed grip of kit #1084 (the support hand canted over the shooting hand, the right thumb on
the left thumb's root while that hand holds) and the seat of kit #1213 (the right middle finger under the trigger
guard), for which each body's hand on the slide was solved and the clip built again: on that seat the clip built
for the seat before had the female's left thumb 4.0 mm in her right thumb while the slide was pulled (frames 12 to
13). On the clip's ends the right thumb lies on the left hand (the male's 15.4 mm off the gun), and the test
measures the right hand against the left one there.

Before each body had its own hand (the place and the fingers solved on the Quaternius mannequins' hands, 0.232 m,
played on these bodies): the female's palm was 13.9 mm off the slide, her index fingertip 18.9 mm inside it and her
thumb's tip 6.0 mm off; the male's palm 12.3 mm off, his index fingertip 13.1 mm inside and his thumb's tip 3.7 mm
off.

The limb check does not judge the frames on which the hold has the left hand on its support grip (0, 1, 27 and 28):
there the hands touch by the hold's own solve, which the check reads as 4.2 mm (female) and 1.6 mm (male) and the
hold's test as 1.5 and 1.6 mm; while the slide is pulled the check reads the female's left hand 1.7 mm in her right
one (frame 12). The left wrist bends 36 to 40 degrees from the forearm's line while it grips (the
build fails over 45) and is held to 40 over the slide; on the frames it leaves the support grip along the hold's
clear line, turned as it held, it bends 69 to 93 degrees (frames 2 to 4; 82 at most on the way back). The canted
support hand of kit #1084 costs that: on the grip before it the same frames bent 66 to 71 degrees. Easing the
wrist from the way's far end instead of from the clear line's end brought it to 81 and put the left fingertips
18 mm into the right hand, so it is not done.

## Why an overhand rack

There are two ways to rack a slide. In the **slingshot** the support hand pinches the rear serrations between thumb
and forefinger from behind and the two hands pull apart. In the **overhand** grip the support hand comes over the top
of the slide, palm down, the heel of the hand on the slide's left side and all four fingers over the top onto the
right side, just in front of the rear sight; the slide is pulled to the rear while the firing hand drives the frame
forward, and the hand opens at the rear so the slide runs home on its spring (riding it forward is the fault every
source warns about).

| Source | What it says |
| --- | --- |
| Guns & Ammo, the best slide serration technique (<https://www.gunsandammo.com/editorial/whats-the-best-slide-serration-technique/248342>) | Overhand: palm down, the heel on the slide's left, the fingers over the top just in front of the rear sight, all fingers pulling; let go at the rear. Slingshot: thumb and forefinger pinch, the pistol held close and punched forward. Keep the muzzle downrange: the overhand motion can swing it to the left. |
| GunGoddess, racking the slide (<https://gungoddess.com/blogs/fundamentals/racking-the-slide>) | Overhand is the strongest for most people: the hand behind the ejection port, the pistol at the body's middle line pointed downrange, the gun punched forward while the hand holds the slide; open the hand at the rear so it does not go forward with the slide. |
| RallyPoint, how to manipulate the slide (<https://www.rallypoint.com/answers/is-there-a-proper-way-to-manipulate-the-slide-on-a-semi-automatic-pistol>) | Opposing force: the firing hand pushes the frame while the support hand pulls the slide. |

The clip is the overhand rack because of what the third-person camera sees. The camera is behind the right shoulder
and above it, so it sees the top and the rear of the pistol and nothing behind the grip: a pinch of two fingers at
the slide's rear sits between the pistol and the chest and reads as nothing, while a whole hand over the top of the
slide, a forearm across the chest and an elbow that swings back at the release are a silhouette. From the research
the clip takes: the hand just in front of the rear sight and behind the ejection port, the push against the pull,
the hand open at the rear and well clear before the slide is home, and a muzzle that stays within 15 degrees of
downrange (it is turned exactly that far, so the forearm can lie along the hand: see the build's `GUN_KEYS`). What it
does not take: the pistol at the body's middle line. There the right shoulder hides it from the
camera, so it stays in front of the right shoulder, 16 cm closer than the aim pose.

## How it is made

```text
<godot> --headless --path game -s res://tools/hold/dump_hold_rig.gd -- <abs>/rig.json
uv run --no-project --with numpy --with scipy python assets/animation/pistol/solve_rack_hand.py <abs>/rig.json assets/animation/pistol/rack_hand.json --body=female
uv run --no-project --with numpy --with scipy python assets/animation/pistol/solve_rack_hand.py <abs>/rig.json assets/animation/pistol/rack_hand.json --body=male
blender -b --factory-startup -P assets/animation/pistol/build_pistol_rack.py -- --out <abs>/assets/animation/pistol/pistol_rack.glb --data <abs>/rack_clip.json
<godot> --headless --path game -s res://tools/hold/write_slide_rack.gd -- <abs>/rack_clip.json
```

`solve_rack_hand.py` works out, for one body at a time, where the left hand grips the slide (the hand bone's place in
the pistol's space and every finger bone's rotation) on that body's skinned hand, against the pistol and the right
hand as the hold has it on that body (`tools/hold/hold_files.py` reads the hold scene's own files for the female and
`pistol_fit_male.tres` for the male); it uses the hold tools' rig, skinning and distance grid and changes nothing of
the hold. It measures the gripping hand at eight places along the slide's travel against what stays behind (the
hammer, the right hand), and solves the opened hand: each finger the pose nearest its grip whose two outer parts are
10 mm off every surface where the hand lies, clear on the straight way down from over the slide, and never deeper
than 1.2 mm while it closes. With no option it closes the fingers at the body's place in `PLACES` (a minute, after
the two distance grids it keeps beside the dump); `--search` searches the place from there. The search knows the
contact and little of the arm, and walked the wrist up the barrel until the arm stopped short, so a place it finds
is taken only after the build's wrist and reach numbers and the test agree. Its result, `rack_hand.json` (one entry
a body), is committed, so the clip builds without it. Run it again, for each body, after the hold's right hand
(its seat or any pose of it) or the pistol changes, then build the clip again.

`build_pistol_rack.py` keys the clip in the pinned Blender on `form_female`'s skeleton from a few targets (the
pistol's way, the left hand's way in the pistol's space, where the elbows point, the beats above) and solves both
arms to them; the only pose read from the library is the last frame of `Pistol_Reload`. The hand leaves the support
grip along the line the hold solved clear for that body (`WeaponHold.support_way`), and the clip's own hand is at
that line's far end on the frames the hold gives it to the clip's arm and takes it back (`ARM_UNTIL`, the hold's
`SupportHandPlan`): the hold takes the hand out there itself and only then lays the right thumb back on the frame,
so a clip that had the hand at the support grip on those frames put it under the thumb (7.1 to 8.0 mm on the
female with the arm in). Build the clip again after the hold's plan, its way or its poses change. It fails before
it exports when
the clip does not start and end on that pose, an arm cannot reach, the left wrist bends more than 45 degrees while
it grips, the clip's own hand is off the slide on the body it is keyed on, or a part of the body goes more than 5 mm
into another on either body posed as the game draws it, each with its own hold, place and fingers
(`../limb_overlap.py`; `--arms-only` prints the arms' numbers and stops, for tuning). `write_slide_rack.gd` writes
the two `SlideRack` files. `tools/capture/rack_closeups.tscn` prints the hands' numbers on every frame and films
the moments from six sides (`RACK_CARRY=0` with the pistol where the clip has it, `RACK_FINGERS=0` with the clip's
own fingers).

## Where it comes from

The motion is GDStudio's own work, under this repository's licence ([LICENSE.md](LICENSE.md)); nothing in it is copied
from another game, pack or capture. The skeleton in `pistol_rack.glb` is the one the clip is keyed on, GDStudio's
prototype body `assets/characters/prototype/form_female.glb`: the bones the clip keys carry the names and parents of
the Quaternius universal rig, CC0, which that body is built on.
