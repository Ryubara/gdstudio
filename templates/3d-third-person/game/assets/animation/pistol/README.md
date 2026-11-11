# Pistol clips

One clip of GDStudio's own for the pistol, made from nothing (kit #1081) because the Universal Animation Library's
`Pistol_Reload` has no rack of the slide. It is in `pistol_rack.glb`, which Godot imports as an `AnimationLibrary` the
same way as `assets/animation/universal/`: add it to an `AnimationPlayer` as the library `pistol` and the clip is
`pistol/Pistol_Rack`. The player scene does not hold the library yet: the reload that plays it (kit #1052) adds it
with the code that moves the slide.

| Clip | Length | Loops | What it is |
| --- | --- | --- | --- |
| `Pistol_Rack` | 0.933 s (28 frames) | no | An overhand rack of the slide. The right hand brings the pistol 12 cm in, in front of the right shoulder, and cants it 28 degrees (the top to the right); the left hand leaves its support grip round the gun's left side, comes over the top of the slide just in front of the rear sight, closes on it, and pulls it back 4.5 cm while the right hand pushes the frame 3 cm forward; it lets go at the rear, follows through toward the chest and goes back to the support grip the way it came. Starts and ends on the last frame of `Pistol_Reload` (which is also its first, and the aim pose). |

At 30 frames a second, the library's rate, keyed on every frame, in place, on the 65 bones of the Quaternius universal
rig (the import drops the ten tracks that never leave the rest pose). The right hand keeps the grip through the clip
and the trigger finger stays off the trigger.

## The beats (for the code that plays it)

`gameplay/weapon/hold/pistol_slide_rack.tres` (a `SlideRack`) holds them as shares of the clip, written by the build:

| Frames | Share | What happens |
| --- | --- | --- |
| 0 to 1 | 0 to 0.036 | The left hand is on its support grip (the hold's `SupportHand`). |
| 1 to 2.5 | `leave` | It opens and lets go. |
| 2.5 to 7 | | Off the grip sideways, round the gun's left side, over the slide, opened. |
| 7 to 9 | `grip` | It comes down on the slide and closes: the palm on the top, four fingers down the right side over the serrations, the thumb down the left. |
| 10 to 13 | `pull` | It pulls the slide back by `travel` (0.045 m); the pistol is pushed 3 cm forward against it. |
| 13 to 15 | `release` | The hand opens and leaves the slide; the slide runs home within `slam` (one frame), and the pistol nods 3 degrees. The slide's sound belongs at frame 13 to 14 (share 0.46 to 0.5). |
| 15 to 17 | | The hand follows through, 7.5 cm back off the slide's rear. |
| 17 to 25.5 | | Back round the gun's left side to the support grip. |
| 25.5 to 27 | `back` | It closes on the support grip; the last frame is the reload's. |

What plays the clip does three things, as `tests/fixtures/rack_stage.gd` does for the test and the captures:

- **Reach the left hand** to `SlideRack.hand_place(share)` (the hand bone's place in the pistol's space) with a
  `HoldArm` weighted by `hand_weight(share)`, elbow at `elbow`. The clip keys the hand onto the slide on the female
  mannequin with the pistol where the clip's own right hand has it; on the male (upper arms 5 cm longer) the same
  rotations leave the hand 7 to 9 cm from the slide, and the hold moves the pistol after the clip on both (the wrist's
  turn is in the clip's reckoning, the carried arm's 8 degrees out from the thigh is not), so the hand is reached
  the way `WeaponHold` reaches `SupportHand`. The fingers are the clip's own.
- **Hold the support grip at the ends**: `support_weight(share)` is how far the hold has the left hand on
  `SupportHand` (the stage tells the hold it is at a reload's end by that much). Keep the hold's reload weight up
  through the rack, so the trigger finger stays off the trigger while the character aims.
- **Move the slide**: the pistol's `Slide` node by `travel * slide_pull(share)`.

## Numbers

Measured in Godot on the skinned meshes, on every frame, on both mannequins (`tests/gameplay/test_pistol_rack.gd`,
`tools/capture/rack_closeups.tscn`; the limits are the hold's, 2 mm in and 5 mm off):

| | Female | Male |
| --- | --- | --- |
| Right hand on the grip, every frame | 1.2 mm in, 2.7 mm off | 1.1 mm in, 4.4 mm off |
| Left hand on the slide (frames 9 to 13) | 0.9 mm in, 4.1 mm off (the palm) | 1.0 mm in, on the surface |
| Left hand on the way (deepest in the gun or the right hand) | 0.0 mm | 1.4 mm |
| Left hand's bone from its place on the slide | 0.0 mm | 0.0 mm |
| Limbs through each other (`../limb_overlap.py`, the build) | 4.8 mm | 2.2 mm |

The limb check's 4.8 mm and 2.2 mm are the support grip itself at the clip's ends (the left fingers lying over the
right ones, which the hold's own measure reads as 1.2 mm); between the ends it reads 0. The left wrist bends 23 to 26
degrees from the forearm's line while it grips and at most 51 on the way.

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
downrange. What it does not take: the pistol at the body's middle line. There the right shoulder hides it from the
camera, so it stays in front of the right shoulder, 12 cm closer than the aim pose.

## How it is made

```text
<godot> --headless --path game -s res://tools/hold/dump_hold_rig.gd -- <abs>/rig.json
uv run --no-project --with numpy --with scipy python assets/animation/pistol/solve_rack_hand.py <abs>/rig.json assets/animation/pistol/rack_hand.json
blender -b --factory-startup -P assets/animation/pistol/build_pistol_rack.py -- --out <abs>/assets/animation/pistol/pistol_rack.glb --data <abs>/rack_clip.json
<godot> --headless --path game -s res://tools/hold/write_slide_rack.gd -- <abs>/rack_clip.json
```

`solve_rack_hand.py` works out where the left hand grips the slide (the hand bone's place in the pistol's space and
every finger bone's rotation) on both mannequins' skinned hands at once, against the pistol and the right hand as the
hold has it; it uses the hold tools' rig, skinning and distance grid and changes nothing of the hold. `--search`
searches the place again (ten minutes); with no option it closes the fingers at the place it ships (four minutes, most
of it two distance grids it keeps beside the dump). Its result, `rack_hand.json`, is committed, so the clip builds
without it. Run it again after the hold's right hand or the pistol changes.

`build_pistol_rack.py` keys the clip in the pinned Blender from a few targets (the pistol's way, the left hand's way
in the pistol's space, where the elbows point, the beats above) and solves both arms to them; the only pose read from
the library is the last frame of `Pistol_Reload`. It fails before it exports when the clip does not start and end on
that pose, an arm cannot reach, the left wrist bends more than 45 degrees while it grips, the clip's own hand is off
the slide on the mannequin it is keyed on, or a part of the body goes more than 5 mm into another on either
mannequin posed as the game draws it (`../limb_overlap.py`). `write_slide_rack.gd` writes the `SlideRack` file.
`tools/capture/rack_closeups.tscn` prints the hands' numbers on every frame and films the moments.

## Where it comes from

The motion is GDStudio's own work, under this repository's licence ([LICENSE.md](LICENSE.md)); nothing in it is copied
from another game, pack or capture. The skeleton in `pistol_rack.glb` (bone names, parents and rest pose) is the
Quaternius universal rig's, CC0, taken from `assets/characters/mannequin/mannequin_female.glb`.
