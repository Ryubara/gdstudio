# Rifle clips

Six clips of GDStudio's own for a character holding the template's rifle in both hands (kit #1082), because the
Universal Animation Library has pistol clips and no rifle clip. Keyed from nothing by `build_rifle_clips.py` on
the Quaternius universal rig, at the library's 30 frames a second. Licence: [LICENSE.md](LICENSE.md).

| Clip | Length | What it is |
| --- | --- | --- |
| `Rifle_Idle` | 3.0 s, loops | The low ready: the trunk 6 degrees forward, the shoulders rounded, the head up, one slow breath |
| `Rifle_Aim_Neutral` | 2.0 s, loops | At the shoulder, the view level: the trunk leant into the rifle, the right shoulder up behind the butt, the head down on the stock |
| `Rifle_Aim_Up`, `Rifle_Aim_Down` | 2.0 s, loop | The same with the view 45 degrees up and down (`CharacterAnimation.aim_pitch_range`) |
| `Rifle_Shoot` | 0.4 s | A shot's recoil in the body: the upper spine rocks back 1.1 degrees a bone in one frame, the right collarbone is pushed back, the head rides with the stock; back by frame 4, a small sway forward, still from frame 9. It starts and ends on `Rifle_Aim_Neutral`'s first pose |
| `Rifle_Reload` | 2.2 s | The body through a magazine change: the eyes go down to the magazine well (0.14 of the clip), follow the left hand to the belt as the left shoulder drops (0.42), come back for the new magazine, a jolt as it seats (0.62) and as the bolt runs home (0.88), level again at the end. It starts and ends on `Rifle_Idle`'s first pose |

The game plays them on the upper body (`spine_01` and everything under it) over its own locomotion:
`gameplay/weapon/rifle.tres` names them, the idle as the grip clip, the three aims by the view's pitch, the shot
added on top of the aim (`WeaponDef.shoot_additive`: the clip less its own first frame, so the recoil rocks the
body at any pitch) and the reload stretched to the weapon's `reload_time`. The legs and the pelvis in the file
are the library's `Idle` first pose, held.

## The rifle is not in the clip

The rifle is carried by `TwoHandHold` (`gameplay/weapon/two_hand_hold.gd`), not by a bone: after the clip it
puts the butt in the shoulder's pocket from the chest bone's place, turns the chest, reaches both arms to their
places on the rifle and closes the fingers, on whichever mannequin plays the clip. The build works the same hold
out in Python (`Hold`, from the numbers in the hold's script and scenes and the five finger poses, none typed in
the build), shapes the body round the rifle where the game will draw it, and keys the hold's own arms and
fingers, so the file alone shows two hands on the rifle. On the female mannequin the clip's own hands are within
1.2 mm of where the game's hold puts them (`tests/gameplay/test_rifle_clips.gd`); on the male, whose arms are
5 cm longer, the hold's reach does the work, as it does for every clip. **When the hold's numbers or the solved
hands change, run the build again.**

The left hand's way to the magazine, the belt and back, and the magazine's move, are the hold's (by the weapon's
reload share); the reload clip moves the body at the same shares. The hand does not go to the charging handle
yet, and the `Bolt` node does not move: the clip has the body's beat for it (the head lifting from 0.72, the
jolt at 0.88 where the bolt's sound is), and the hand and its fingers on the handle are a follow-up issue.

## How the body is shaped

The trunk stands upright from the pelvis and is leant; the neck and the head are stood in the character's space
(so a breath or a recoil under them does not move where the head looks). For the three aims a small search (a
damped least-squares over the lean, the neck's and the head's turns) brings the right eye toward the sight line
with the face along it, within what a body gives (`AIM_LIMITS`: 12 degrees more lean, 24 of neck) and with the
head's and the neck's skin of both mannequins kept off the stock.

What it reaches, and why not more: the eye ends 5 to 7 cm above the sight line (73 mm level and up, 51 mm down).
The stock's comb is 7 cm under the line and the mannequin's head is an egg with no cheek to press on it, so the
head rests on the comb; and the pocket is at the shoulder joint's height, 12 cm under where an upright head has
its eye (kit #1177 is about the pocket). From the game camera the head reads as down on the rifle.

What was read first, for the mechanics only:

| Source | What the clips take from it |
| --- | --- |
| [American Rifleman, AR Basics: Shooting Positions](https://www.americanrifleman.org/articles/ar-basics-shooting-positions) | A bladed standing stance, the support side forward (the hold's chest turn), the weight forward |
| [UF Pro, rifle shooting fundamentals: stance and grip](https://ufpro.com/blog/shooting-stance-grip) | An athletic stance, not a relaxed one; the cheek on the stock and the stock's place on the shoulder as checkpoints; the support hand steadies the muzzle |
| [Guns & Ammo, shooting stance](https://www.gunsandammo.com/editorial/standing-your-ground-shooting-stance/247979) | Squared and bladed stances are both taught; the template's hold is bladed 30 degrees |
| [Pew Pew Tactical, how to reload an AR-15](https://www.pewpewtactical.com/how-to-reload-ar-15/) | The rifle stays up near the body's middle, the eyes go to the magazine well, the support hand fetches and seats the magazine and tugs it, then the bolt is sent home (the bolt release, or the charging handle pulled all the way and let go) |
| [Athlon Outdoors, emergency reload of the AR-15](https://athlonoutdoors.com/article/emergency-reload-of-the-ar-15/) | The order of the beats and that the firing hand keeps the grip |

## Numbers

The build measures every frame of every clip on both mannequins, posed as the game draws them (the clip, then the
hold on that body), and fails before it exports over a limit:

| Check | Limit | Measured |
| --- | --- | --- |
| A loop's last pose against its first; the shot's ends against the aim, the reload's against the idle | 0.01 degrees | 0.000 |
| An arm short of its place on the rifle | 0.5 mm | 0.0 mm, every frame, both |
| The head's skin inside the rifle | 5 mm | 0.0 mm female, 1.2 mm male (the shot) |
| The right eye off the sight line, the aims | 80 mm | 73.6, 73.8 and 50.5 mm (level, up, down) |
| A limb inside another (`../limb_overlap.py`) | 5 mm, or what the hold alone does plus 3 mm | below |

The hold brings the grip close to the chest, so the right forearm passes through the ribs at the low ready with
any clip under it. The build measures that floor (the hold on the library's `Idle` pose) and holds each clip to
it:

| Right forearm in the chest, deepest | Female | Male |
| --- | --- | --- |
| The hold alone, low ready | 24.5 mm | 27.8 mm |
| `Rifle_Idle`, `Rifle_Reload` | 16.8, 17.7 mm | 20.3, 20.6 mm |
| The hold alone, aimed level, up, down | 15.8, 0, 16.2 mm | 0 mm |
| `Rifle_Aim_Neutral`, `Rifle_Aim_Up`, `Rifle_Shoot` | 0 mm | 0 mm |
| `Rifle_Aim_Down` | 18.5 mm | 0 mm |

Rounded shoulders and a raised right collarbone are what lift the forearm off the ribs (an upright chest read
28 and 44 mm at the low ready). What is left is the hold's pocket (kit #1177).

In Godot (`tests/gameplay/test_rifle_clips.gd`): with each clip on the upper body over the standing and the
crouched legs, at every eighth of the clip, on both mannequins, each hand's bone is on its place and the skin is
within the hold's limits (2 mm in, 5 mm off; measured 1.3 mm in and 4.4 mm off on the female, 1.4 mm in on the
male).

## Building and looking

```text
blender -b --factory-startup -P build_rifle_clips.py -- --out <abs>/rifle_clips.glb --data <abs>/rifle_clips.json
    [--report <numbers.json>] [--preview <folder>] [--only <clip> ...]
```

with the pinned Blender (`gds tool path blender`); about four minutes. `--preview` writes a sheet a clip and
mannequin (the right side, the front left, above, behind the right shoulder; six frames) with the rifle where the
hold has it. In the game: `tools/capture/rifle_clip_closeups.tscn` (a picture a pose from the right, above and the
player's camera, both mannequins) and `tools/capture/rifle_hands.tscn` (the player through every state, six
close-ups of the hands).
