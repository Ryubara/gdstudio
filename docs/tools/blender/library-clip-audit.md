# The library's clips, measured

<!-- new section: moved from own-animation.md#audit when that page reached 50 KB; the measurements of the library
clips the template plays, which every clip of our own has to beat -->

The audit behind [Our own animation set](own-animation.md): what each library clip the template plays measures, and
what the clips cost. Their crossings on the template's bodies are on
[Clip crossings on the template's bodies](body-crossings.md#library-clips).

## What was measured, and how {#audit}

<!-- new section: nobody had measured the library's clips; a replacement needs the number it has to beat -->

The template plays 27 of the libraries' 86 clips (`CharacterClips`, `pistol.tres`, `fists.tres`), four clips of our
own (`assets/animation/prone/`) and, since kit #1037, our three vault clips (`assets/animation/vault/`, made in
kit #1016, not yet measured here) in place of `NinjaJump_Start`. Every number below is from
`templates/3d-third-person/game/assets/animation/audit_clips.py`, which reads the glb itself and measures each frame
on the skinned mesh; its docstring defines each measure. The body is the library's own (the male mannequin); the
female, the template's default, is given where she differs. Limbs inside limbs are from `limb_overlap.py`.

```sh
uv run --with numpy python audit_clips.py --clips universal/ual1.glb --clip Walk --clip Jog_Fwd \
    --speed Walk=1.7 --join Walk=Jog_Fwd --markdown
```

### The gaits {#audit-gaits}

<!-- new section: the gaits are compared with each other and with the game's speeds, which one table shows best -->

| | Walk | Jog_Fwd | Sprint | Crouch_Fwd |
| --- | --- | --- | --- | --- |
| Frames at 30 a second (one stride) | 40 | 28 | 20 | 60 |
| Steps a minute | 90 | 129 | 180 | 60 |
| Ground the planted sole covers | 0.96 m/s (0.55 to 1.33) | 5.9 m/s (steady) | 8.9 m/s for three frames, after a frame on the floor still going forward | 0.45 m/s (0.04 to 0.96) |
| The game's speed for it | 1.7 m/s | 4.0 m/s | 6.5 m/s | 1.5 m/s |
| So the feet | cover 56 % of the ground | sweep 48 % faster than the ground | sweep 37 % faster | cover 30 % |
| A planted sole wanders, per contact | 57 mm | 12 mm | 288 mm | 574 mm |
| Planted share of the cycle, and the rest | 0.70, both feet down 40 % | 0.18, in the air 64 % | 0.25, in the air 50 % | 0.69, both down 38 % |
| Lowest sole vertex | 26 mm under the floor at toe-off (15 mm on the female), 5 mm at heel strike | on the floor | on the floor (4 mm under on the female) | 8 mm under (11) |
| Pelvis up and down | 53 mm | 245 mm | 138 mm | 61 mm |
| Shoulders turn, hips turn | 15 and 4 degrees, together | 76 and 1, opposed | 47 and 4, opposed | 3 and 5 |
| Trunk leans forward | 12 degrees | 26 | 39 | 48 |
| Forearm trails the upper arm, hand trails the forearm | 0.2 and 2.2 frames | 1.6 and none (the wrist never moves) | 0.3 and none | the arms hold still |
| Left and right, half a cycle apart, differ by | 2.5 degrees | 3.7 | 13.4 | 6.1 |
| Bones that move, fingers among them | 21, 0 | 19, 0 | 19, 0 | 16, 0 |
| Rotation keys a reducer keeps at half a degree | 35 % | 63 % | 74 % | 28 % |
| Limbs inside limbs | hand 11 mm in the thigh on the female | none | none | none |

What the table says:

- **No gait's feet match the speed the game moves it at.** The ground blend space puts each clip at a tuned speed
  and plays it at its own pace, so the walk's feet cover 56 % of the ground and the jog's sweep half as fast again
  as the floor under them. Our clips carry their measured speed, and the tree plays each at ground speed over clip
  speed ([replacing](own-animation.md#replacing)).
- **The jog and the sprint are bounds, not runs.** The jog is in the air for 64 % of its cycle with the pelvis
  going 245 mm up and down, at 129 steps a minute; a walking person's centre of mass rises 5 cm
  ([research](own-animation.md#research-weight)). The sprint steps faster, but its foot lands still
  travelling forward and then sweeps at 8.9 m/s.
- **The run's arm swing is the chest turning.** The shoulders turn 76 degrees in the jog while the upper arm moves
  26 degrees in its socket and the wrist not at all, and the neck and the head turn it all back: the head's facing
  changes by 0.0 degrees over the cycle, as if on a rail.
  `spine_01` never moves in any gait.
- **Nothing trails.** Hands, head and chest move on the frame their parent does, bar the walk's wrist. There is no
  finger motion in any gait and the two halves of a cycle are near mirror images.
- **The walk's seam shows.** Its last pose is its first, but the change of speed across the seam is twice the
  largest anywhere else in the cycle (the jog 1.0, the sprint 0.5).
- **The poses the gaits pass between are far apart.** Idle to Walk differs by 436 mm at a hand, Walk to Jog by
  681 mm at a foot, Sprint to Idle by 685 mm; a 0.15 s cross-fade is all that joins them, since the library has no
  start, stop or turn.

### Every clip {#audit-clips}

<!-- new section: the issue asks for each played clip's use, its strengths and faults by measure, and our answer -->

Length is at the clip's own pace. "Join" is the furthest any main joint is from the pose the clip hands over to.

| Clip | Used for | Does well | Does badly, by measure | Ours |
| --- | --- | --- | --- | --- |
| `Idle` 2.5 s | standing still, the ground blend's zero | feet fixed to 0.3 mm | 17 bones move, pelvis 8.5 mm, head 0.2 degrees: breathing only, no weight shift, no fingers; 90 % of its keys are redundant; the seam is 3 mm open; the hand is 17 mm in the thigh on the female | a weight shift from foot to foot, breath through the spine and collarbones, hands alive; longer loop from layered periods |
| `Walk` 1.33 s | walk speed | arms against legs (0.76), a real heel-to-toe roll | the gaits table: speed, toe 26 mm under the floor, seam | replacement at the game's speed, see [the feel](own-animation.md#feel) |
| `Jog_Fwd` 0.93 s | run speed | steady planted speed (12 mm of slide), clean loop | the gaits table: a bound, 245 mm of bob, the chest does the arms' work | replacement |
| `Sprint` 0.67 s | sprint speed | strong lean (39 degrees), reads as fast | foot lands moving forward, 288 mm of slide in a contact, halves differ by 13 degrees | replacement |
| `Crouch_Idle` 2.9 s | crouched and still | fingers posed (24 bones), feet fixed | 95 % of keys redundant; nothing but breath | replacement with a look-around variant |
| `Crouch_Fwd` 2.0 s | crouch walk | low and readable | planted speed 0.04 to 0.96 m/s, so a sole wanders 574 mm in a contact; the arms hold still (6 degrees) | replacement at 1.5 m/s with a steady sweep |
| `Jump_Start` 1.33 s | the take-off (the game's rise is 0.4 s) | ends exactly on the air loop (0 mm) | the crouch is frame 0 alone and the legs are straight by frame 2; 38 frames of drifting after | a take-off per speed (standing, running) whose push-off lasts the rise the game gives it |
| `Jump` 2.5 s | in the air | calm, loops | one pose for rising and falling; join to the landing 415 mm | rise, apex and fall poses blended by vertical speed |
| `Jump_Land` 1.27 s | landing (the game gives it 0.3 s) | a deep, heavy landing (pelvis drops 496 mm in 6 frames) | one depth for every fall, and its recovery takes 0.8 s where the game allows 0.3; ends 58 mm from the idle; no landing into a run | soft and hard landings chosen by fall speed, and a landing into each gait |
| `Push` 2.67 s | pushing a prop | leans into it (47 degrees) | planted sole wanders 125 mm; 8 mm under the floor; the hands are where the clip has them, not on the prop | hands planted by IK on the prop, steady feet |
| `Interact` 2.0 s | using things, over 0.7 s | simple reach | played 2.9 times too fast; the body does not turn or step toward the thing; 19 mm of hand in thigh on the female | reaches at three heights with the hand on the target |
| `Hit_Chest` 0.33 s | flinch, over 0.45 s | short enough to stay responsive | 10 frames with no settle; pelvis 21 mm, no step; one side | flinches from four sides with a settle, additive over the gait |
| `Death01` 2.4 s | death without a ragdoll | falls and settles (hand speed dies away over 10 frames) | one fall for every hit; 22 mm under the floor; hand 29 mm in the thigh | falls by hit side; the ragdoll stays the default |
| `Swim_Fwd` 1.33 s | stand-in for prone | none here | a swim stroke lifted and tipped | our prone clips exist (kit #1009, #1020); kit #1026 plays them |
| `Pistol_Idle` 1.67 s | the grip pose | hands held together | the two hands are 14 to 25 mm inside each other; 10 bones move | a pose per weapon class, hands placed by the hold solver |
| `Pistol_Aim_Neutral`, `_Up`, `_Down` 0.17 s | aim blend by pitch | three poses that blend cleanly (2 mm from the grip pose) | static (0 bones move); hands 14 to 31 mm inside each other; the forearm 23 mm in the pelvis aiming down on the male | aim poses with breath, five pitches |
| `Pistol_Shoot` 0.63 s | recoil | returns exactly to the aim pose | the whole kick is one frame, then 18 still frames: no rise and settle | recoil with a kick, an overshoot and a settle, sized by the weapon |
| `Pistol_Reload` 1.67 s | reload | reads as a reload; the head looks down (58 degrees) | hands 22 to 28 mm inside each other; nothing in the clip knows where the magazine is | reload keyed on the weapon's sockets |
| `Punch_Jab`, `Punch_Cross` 0.87, 1.0 s | the fists' two blows | the chest drives the blow (43 and 57 degrees) and hits in two frames (hand at 4 and 8.9 m/s) | no step or weight transfer (pelvis 2 and 27 mm); ends 631 mm from the idle; the hand is 19 to 28 mm in the head on the female | blows with a step, from a guard pose that the idle blends to |
| `Slide_Start`, `Slide`, `Slide_Exit` 0.83, 2.0, 0.5 s | the slide | start and exit meet the loop within 9 mm | 12 to 37 mm under the floor; one entry, whichever foot the sprint is on; the exit only stands up | start from each sprint foot, exit into a run or a crouch |
| `NinjaJump_Start` 0.97 s | stood in for the vault until kit #1037 | tucks the legs | not a vault: no hand on anything | the vault clips of kit #1016, played since #1037 |
| `ClimbUp_1m` 0.67 s | the mantle | quick | the chest is 23 to 32 mm in the thigh; the hands hold nothing; one height | mantles at two heights with planted hands, warped like the vaults |

The pistol clips' hands are closed on the gun by `WeaponHold` after the clip, so their overlap is what the solver
starts from, not what the player sees.

### What the clips cost {#audit-cost}

<!-- new section: the web build's cost of the libraries had one number (the pck); the plan needs it per clip -->

Measured by importing `ual1.glb` (43 clips) in Godot 4.7.2 with three settings:

| Import | Keys | Imported size |
| --- | --- | --- |
| The optimizer off | 113,624 | 1,560 KB |
| The default (the optimizer on) | 41,099 | 752 KB |
| The default and compression (`compression/enabled`, page size 8) | 43,504 | 275 KB |

Each clip keeps 56 tracks (55 rotations and the pelvis's position): the importer drops the scale tracks, the
positions that never change and ten rotation tracks that never leave the rest, and keeps a rotation track for every
other bone, moving or not. The glb holds 195 channels a clip, sampled on every frame. The
template ships both libraries, about 1.5 MB imported, and plays 27 of their 86 clips; of those 27, a clip moves 25
bones on average and a linear reducer at half a degree keeps 30 % of the moving bones' rotation keys.
