# Rifle clips

Six clips of GDStudio's own for a character holding the template's rifle in both hands (kit #1082), because the
Universal Animation Library has pistol clips and no rifle clip. Keyed from nothing by `build_rifle_clips.py` on
the prototype mannequin rig (`form_female.glb`, the player's body), at the library's 30 frames a second. Licence:
[LICENSE.md](LICENSE.md).

| Clip | Length | What it is |
| --- | --- | --- |
| `Rifle_Idle` | 3.0 s, loops | The low ready: the trunk 6 degrees forward, the shoulders rounded, the head up, one slow breath |
| `Rifle_Aim_Neutral` | 2.0 s, loops | At the shoulder, the view level: the trunk leant into the rifle, the right shoulder up behind the butt, the head canted toward the stock with the eye by the sights |
| `Rifle_Aim_Up`, `Rifle_Aim_Down` | 2.0 s, loop | The same with the view 45 degrees up and down (`CharacterAnimation.aim_pitch_range`) |
| `Rifle_Shoot` | 0.4 s | A shot's recoil in the body: the upper spine rocks back 1.1 degrees a bone in one frame, the right collarbone is pushed back, the head stays by the sights; back by frame 4, a small sway forward, still from frame 9. It starts and ends on `Rifle_Aim_Neutral`'s first pose |
| `Rifle_Reload` | 2.2 s | The body through a magazine change: the eyes go down to the magazine well (0.14 of the clip), follow the left hand to the belt as the left shoulder drops (0.42), come back for the new magazine, a jolt as it seats (0.62) and as the bolt runs home (0.86), level again at the end. It starts and ends on `Rifle_Idle`'s first pose |

The game plays them on the upper body (`spine_01` and everything under it) over its own locomotion:
`gameplay/weapon/rifle.tres` names them, the idle as the grip clip, the three aims by the view's pitch, the shot
added on top of the aim (`WeaponDef.shoot_additive`: the clip less its own first frame, so the recoil rocks the
body at any pitch) and the reload stretched to the weapon's `reload_time`. The legs and the pelvis in the file
are the game's own standing idle (`gds/Idle`) on its steadiest frame, held: the frame the game holds the legs on
under a standing aim (`AimStance`), named in `rifle_clips.json` (`base`). A clip keys each bone in its parent, so
the arms in the file are the hold's own over that pelvis and no other.

No pose is the same on both sides: the chest stands turned 30 degrees with the left shoulder forward, the right
collarbone is up and forward behind the butt and the left one forward with the reach, the head is rolled and
turned onto the stock, the right hand holds the grip and the left the hand guard, and in the reload only the left
side moves.

## The rifle is not in the clip

The rifle is carried by `TwoHandHold` (`gameplay/weapon/two_hand_hold.gd`), not by a bone: after the clip it
turns the chest (and raises one that leans past `aim_lean_limit` while the rifle is up), puts the butt in the
shoulder's pocket from the chest bone's place in the chest's frame, brings the left shoulder toward the hand
guard and the butt to the torso's skin (kit #1177; out of the pocket level while the muzzle is down, kit #1346),
reaches both arms to their places on the rifle and closes the fingers, on whichever body plays the clip, with the
places and the finger poses solved on that body
(the scene's own for the female, `rifle_fit_male.tres` for the male). The build works the same hold out in Python
(`Hold`, from the numbers in the hold's script and scenes, each body's fit and the five finger poses, none typed
in the build; the torso's skin for the butt from each body's own mesh, `Hold.measure_chest`), shapes the body
round the rifle where the game will draw it, and keys the hold's own arms and fingers, so the file alone shows
two hands on the rifle. On the female body the clip's own hands are within 1.6 mm of where the game's hold puts
them (`tests/gameplay/test_rifle_clips.gd`; the game settles the butt's push over frames, to within 3 mm); on
the male, whose arms are longer and whose hands are bigger, the hold's reach does the work, as it does for every
clip. **When the hold's numbers, a body or the solved hands change, run the build again.**

The left hand's way to the magazine, the belt and back, and the magazine's move, are the hold's (by the weapon's
reload share); the reload clip moves the body at the same shares. After the magazine the hand goes to the
charging handle, hooks the latch, pulls the `Bolt` node back 6 cm and lets it go (the hold's `ChargePull` of kit
issue 1266, ported to the build's `Hold`, so the clip's own left arm follows it); the clip has the body's beat for it,
the head lifting from 0.72 and the jolt at 0.86 where the bolt's sound is.

## How the body is shaped

The trunk stands upright from the pelvis and is leant; in the idle and the reload the neck and the head are
stood in the character's space (so a breath or a jolt under them does not move where the head looks).

In the three aims and the shot the head is not the clip's to choose: the game sets it after the clip, for every
weapon (`AimHeadModifier`, kit #1334). The rifle asks for the eye behind its sights (`rifle.tres`: `aim_head`
is `SIGHT`, `aim_eye` the `AimEye` marker of `rifle_held.tscn`, on the sight line behind the rear sight): from
the level look along the aim, one more turn, shared between the neck and the head, brings the right eye toward
that place for what a nod, a turned face and a cant of the head cost (`sight_nod`, `sight_face`, `sight_cant`).
The build runs the same steps with the same numbers, read from the modifier's script and the scene
(`sight_head`), and keys that head, so the file alone shows what the game draws; a small search leans the trunk
(12 degrees at most) so the eye comes nearer and the head's and the neck's skin of both bodies stay off the
stock. The eye is 32 mm right of the rig's `socket_camera`, in the middle of the visor.

What it reaches: the eye ends 61 mm off the sight line with the view level, 60 mm with it up and 66 mm with it
down (73, 61 and 78 mm on the male), the face 10, 4 and 12 degrees off the line and the head canted 30 degrees
toward the stock. In the game, standing and walking, it is 60 to 67 mm at 30 degrees down, level and 20 up, and
77 to 79 mm crouched (`tests/gameplay/test_aim_head.gd`, limit 81). Before the game held the head it was the
clips' own search: 53, 81 and 51 mm (65, 79 and 63) with the face 22 to 28 degrees off the line. The hold's
pocket is at the shoulder joint's height and at the deltoid's edge, 16 cm from the spine (kit #1177: nearer the
neck the stock lay across the sternum), so the sight line runs beside and under an upright eye, farther than a
neck gives without the face leaving the aim; a level head (the pistol's and the fists' rule) leaves the eye 158
to 167 mm off. From the game camera the head reads as tipped onto the rifle.

The trunk's lean also moves the rifle now: the butt comes forward to the skin of a chest that leans over it, by
45 mm with the view level, 1 mm with it up and 103 mm with it 45 degrees down (there the pitched stock's top edge
meets the chest, with or without these clips' lean: the hold's tests go to 30 degrees).

What was read first, for the mechanics only:

| Source | What the clips take from it |
| --- | --- |
| [American Rifleman, AR Basics: Shooting Positions](https://www.americanrifleman.org/articles/ar-basics-shooting-positions) | A bladed standing stance, the support side forward (the hold's chest turn), the weight forward |
| [UF Pro, rifle shooting fundamentals: stance and grip](https://ufpro.com/blog/shooting-stance-grip) | An athletic stance, not a relaxed one; the cheek on the stock and the stock's place on the shoulder as checkpoints; the support hand steadies the muzzle |
| [Guns & Ammo, shooting stance](https://www.gunsandammo.com/editorial/standing-your-ground-shooting-stance/247979) | Squared and bladed stances are both taught; the template's hold is bladed 30 degrees |
| [Pew Pew Tactical, how to reload an AR-15](https://www.pewpewtactical.com/how-to-reload-ar-15/) | The rifle stays up near the body's middle, the eyes go to the magazine well, the support hand fetches and seats the magazine and tugs it, then the bolt is sent home (the bolt release, or the charging handle pulled all the way and let go) |
| [Athlon Outdoors, emergency reload of the AR-15](https://athlonoutdoors.com/article/emergency-reload-of-the-ar-15/) | The order of the beats and that the firing hand keeps the grip |

## Numbers

The build measures every frame of every clip on both bodies (`form_female`, `form_male`), posed as the game
draws them (the clip, then the hold solved on that body, then the twist bones as `MannequinTwist` turns them),
and fails before it exports over a limit:

| Check | Limit | Female | Male |
| --- | --- | --- | --- |
| A loop's last pose against its first; the shot's ends against the aim, the reload's against the idle | 0.01 degrees | 0.000 | (one file) |
| An arm short of its place on the rifle | 0.5 mm | 0.0 mm | 0.0 mm |
| The head's skin inside the rifle | 5 mm | 0.0 mm | 0.0 mm |
| The right eye off the sight line: level, up, down | reported (the game's test holds 81 mm) | 61.7, 59.9, 65.8 mm | 73.1, 61.3, 78.4 mm |
| A limb inside another (`../limb_overlap.py`): idle, the aims, the shot | 5 mm, or what the hold alone does plus 3 mm | 0.0 mm | 1.9 mm (his thighs meet by that at rest) |
| The same in `Rifle_Reload` | the same | 0.0 mm | 8.2 mm (the left hand in the right, frame 10) |

The floor is the hold run on the idle pose with no rifle clip: 0 mm on the female and 1.9 mm on the male at the
low ready and aimed, and 10.6 and 18.2 mm through the reload (27.0 mm at the low ready and 38.9 and 35.8 mm
through the reload before the butt was brought to the skin, kit #1177). Under the clips only the male's reload is
over nothing: his opened left hand passes 8.2 mm through the fingers of the right on its way to the magazine,
which is the hold's way (`reload_clearance`, `magazine_approach`), the same under any clip.

Reported and not failed, since they are the hold's pocket and not the clip's:

| Deepest in the rifle's butt | Female | Male |
| --- | --- | --- |
| The chest: idle, aim level, up, down, shot, reload | 0 mm in every clip | 0 mm but the shot: 3.2 mm at frame 3 (the kick) |
| The neck's base | 0 mm | 0 mm |

Before the hold brought the butt to the skin the chest was 5 to 22 mm in the butt and the male's neck base 12 mm.

In Godot (`tests/gameplay/test_rifle_clips.gd`): with each clip on the upper body over the standing and the
crouched legs, at every eighth of the clip, on both bodies, each hand's bone is on its place and the skin is
within the hold's limits (2 mm in, 5 mm off). In the game (`tools/capture/rifle_hands.tscn`, both bodies, every
state): each hand's bone 0.0 mm from its place, the right hand 1.2 mm in at most on both bodies, the left 1.2
and 0.9 mm, no holding part off the rifle; on its way through the reload the left hand passes 2.8 mm.

## Building and looking

```text
blender -b --factory-startup -P build_rifle_clips.py -- --out <abs>/rifle_clips.glb --data <abs>/rifle_clips.json
    [--report <numbers.json>] [--preview <folder>] [--only <clip> ...]
```

with the pinned Blender (`gds tool path blender`); about 90 seconds. `--preview` writes a sheet a clip and body
(the right side, the front left, above, behind the right shoulder; six frames) with the rifle where the hold has
it. In the game: `tools/capture/rifle_clip_closeups.tscn` (a picture a pose: the body from the right, above, the
front and the player's camera, and each hand from both its sides, both bodies), `tools/capture/rifle_hands.tscn`
(the player through every state, six close-ups of the hands; `RIFLE_HANDS_BODY=male` for the other body) and
`tools/capture/rifle_tour.tscn` (the game camera).
