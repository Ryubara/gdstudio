# Our own animation set

<!-- new section: the Blender pages said how one clip is keyed; nothing held the plan to replace every library clip
the template plays with our own, the audit behind it, or how a clip is made, checked and reviewed (kit #1150) -->

GDStudio's goal is to depend on no downloaded animation. The Universal Animation Library (Quaternius, CC0) stays in
the template as a base and as stand-ins, and every clip the template plays gets a replacement that is our own work,
made by script. This page is the plan: what the library clips measure today, what good game animation is made of,
the set we will own, and how each clip is made, checked, reviewed and swapped in. It makes no clip; the clips are
the child issues [at the end](#waves). The skeleton they are keyed on is the prototype mannequins'
([The rig](#rig), kit #1149).

The feel to aim for is loose, fluid and natural, with transitions that are animated: a character that reverses
out of a sprint plays a turn of its own instead of snapping round ([the feel as numbers](#feel)).

## The library clips the template plays, measured {#audit}

<!-- new section: nobody had measured the library's clips; a replacement needs the number it has to beat -->

The template plays 27 of the libraries' 86 clips (`CharacterClips`, `pistol.tres`, `fists.tres`), four clips of our
own (`assets/animation/prone/`) and, since kit #1037, our three vault clips (`assets/animation/vault/`, made in
kit #1016, not yet measured here) in place of `NinjaJump_Start`. Every number below is from
`templates/3d-third-person/game/assets/animation/audit_clips.py`, which reads the glb itself and measures each frame
on the skinned mesh; its docstring defines each measure. The body is the library's own (the male mannequin); the
female, the template's default, is given where she differs. Limbs inside limbs are from `limb_overlap.py`, on every
key at the files' own 30 frames a second (kit #1035).

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
| Limbs inside limbs | hand 12 mm in the thigh on the female | none | none | none |

What the table says:

- **No gait's feet match the speed the game moves it at.** The ground blend space puts each clip at a tuned speed
  and plays it at its own pace, so the walk's feet cover 56 % of the ground and the jog's sweep half as fast again
  as the floor under them. Our clips carry their measured speed, and the tree plays each at ground speed over clip
  speed ([replacing](#replacing)).
- **The jog and the sprint are bounds, not runs.** The jog is in the air for 64 % of its cycle with the pelvis
  going 245 mm up and down, at 129 steps a minute; a walking person's centre of mass rises 5 cm
  ([research](#research-weight)). The sprint steps faster, but its foot lands still travelling forward and then
  sweeps at 8.9 m/s.
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
| `Walk` 1.33 s | walk speed | arms against legs (0.76), a real heel-to-toe roll | the gaits table: speed, toe 26 mm under the floor, seam | replacement at the game's speed, see [the feel](#feel) |
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
| `Death01` 2.4 s | death without a ragdoll | falls and settles (hand speed dies away over 10 frames) | one fall for every hit; 22 mm under the floor; hand 29 mm in the thigh on the female, 41 on the male | falls by hit side; the ragdoll stays the default |
| `Swim_Fwd` 1.33 s | stand-in for prone | none here | a swim stroke lifted and tipped | our prone clips exist (kit #1009, #1020); kit #1026 plays them |
| `Pistol_Idle` 1.67 s | the grip pose | hands held together | the two hands are 14 to 25 mm inside each other; 10 bones move | a pose per weapon class, hands placed by the hold solver |
| `Pistol_Aim_Neutral`, `_Up`, `_Down` 0.17 s | aim blend by pitch | three poses that blend cleanly (2 mm from the grip pose) | static (0 bones move); hands 14 to 31 mm inside each other; the forearm 23 mm in the pelvis aiming down on the male | aim poses with breath, five pitches |
| `Pistol_Shoot` 0.63 s | recoil | returns exactly to the aim pose | the whole kick is one frame, then 18 still frames: no rise and settle | recoil with a kick, an overshoot and a settle, sized by the weapon |
| `Pistol_Reload` 1.67 s | reload | reads as a reload; the head looks down (58 degrees) | hands 22 to 28 mm inside each other; nothing in the clip knows where the magazine is | reload keyed on the weapon's sockets |
| `Punch_Jab`, `Punch_Cross` 0.87, 1.0 s | the fists' two blows | the chest drives the blow (43 and 57 degrees) and hits in two frames (hand at 4 and 8.9 m/s) | no step or weight transfer (pelvis 2 and 27 mm); ends 631 mm from the idle; the hand is 19 to 29 mm in the head on the female | blows with a step, from a guard pose that the idle blends to |
| `Slide_Start`, `Slide`, `Slide_Exit` 0.83, 2.0, 0.5 s | the slide | start and exit meet the loop within 9 mm | 12 to 37 mm under the floor; one entry, whichever foot the sprint is on; the exit only stands up | start from each sprint foot, exit into a run or a crouch |
| `NinjaJump_Start` 0.97 s | stood in for the vault until kit #1037 | tucks the legs | not a vault: no hand on anything | the vault clips of kit #1016, played since #1037 |
| `ClimbUp_1m` 0.67 s | the mantle | quick | the chest is 26 to 32 mm in the thigh; the hands hold nothing; one height | mantles at two heights with planted hands, warped like the vaults |

The pistol clips' hands are closed on the gun by `WeaponHold` after the clip, so their overlap is what the solver
starts from, not what the player sees.

### Limbs inside limbs on the template's bodies {#audit-bodies}

<!-- new section: the audit measured the Quaternius bodies; since kit #1187 the template wears the prototype form
bodies, and a replacement has to beat the library on those -->

Every clip's deepest crossing on the prototype `form` bodies beside the Quaternius pair (kit #1286) is on its own page,
[Clip crossings on the template's bodies](body-crossings.md#library-clips), which this page left when it neared 50 KB.

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

## What good game animation is made of {#research}

<!-- new section: the plan's choices rest on how other studios solved the same problems; studied, never copied -->

Read for this plan on 2026-11-11; each finding names the page it came from. Other studios' work is studied for how
it solves a problem and never copied: no clip, curve or data of theirs is used. Where a claim had no source we could
open, it says so.

### Locomotion systems {#research-locomotion}

<!-- new section: which locomotion system the clips are made for decides how many clips there are -->

- **Motion matching** searches minutes of continuous motion capture, each frame, for the pose that best continues
  the current one toward the wanted path; starts, stops and turns are not organised by hand
  ([Clavet, GDC 2016](https://www.gdcvault.com/play/1022985/Motion-Matching-and-The-Road)). An hour of capture at
  30 Hz is 108,000 frames and a 24 MB feature table
  ([O3DE](https://docs.o3de.org/blog/posts/blog-motionmatching/)), and memory grows with the data
  ([Holden](https://theorangeduck.com/page/learned-motion-matching)).
- **A graph of authored clips with warping** is the other road. Paragon's heroes shared one animation template;
  blend spaces kept in step by sync markers; starts, stops and pivots as their own clips; stride warping in place
  of play-rate scaling, with hip motion smoothed by springs
  ([a write-up of Delayen's talk](https://gamedeveloper.com/programming/most-inspiring-game-animation-tech-talks-of-2016)).
  Unreal's stride warping scales the step by ground speed over the clip's speed, its orientation warping turns the
  lower body so one forward jog covers a half circle of directions
  ([pose warping](https://dev.epicgames.com/documentation/en-us/unreal-engine/pose-warping-in-unreal-engine)), and
  Lyra animates four directions and warps between them
  ([Lyra](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-in-lyra-sample-game-in-unreal-engine)).
- **Distance matching** plays a start, stop or pivot by distance travelled, not by time, from a curve baked from
  the clip's root travel
  ([distance matching](https://dev.epicgames.com/documentation/en-us/unreal-engine/distance-matching-in-unreal-engine)).
- **Sync** needs the same named markers in every clip of a group, and the heaviest clip leads
  ([sync groups](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-sync-groups-in-unreal-engine)).

**What we take.** Motion matching needs capture we do not have and memory the web build should not spend. We build
the authored graph: a few gaits whose cycles share a phase (left foot down at 0, right at half), each with its
measured speed, played at ground speed over clip speed; transitions with their travel as a curve, played by
distance; four directions and warping before eight. Our `clips.json` carries what those systems bake: speed, travel
curve, contact times.

### Transitions {#research-transitions}

<!-- new section: the library has no transition, so how games pick and play them had to be read -->

- Unreal's Game Animation Sample starts a pivot at about 45 degrees of direction change, a turn on the spot above
  50 degrees of difference while aiming, a start when the predicted speed is above the present one and a stop from
  the predicted speed; a pivot's second half is a start; landings are light or heavy by landing speed
  ([sample](https://dev.epicgames.com/documentation/en-us/unreal-engine/game-animation-sample-project-in-unreal-engine)).
- Lyra picks a turn on the spot by angle and waiting time and keeps the feet still by counting the turn the body
  has not yet shown
  ([Lyra](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-in-lyra-sample-game-in-unreal-engine)).
- A cross-fade from a clip that has run out of frames blends from a frozen pose, which reads as a stop, and long
  cross-fades swallow anticipation
  ([Delannoy](https://www.gamedeveloper.com/programming/common-mistakes-in-game-animation)).
- The opposite road is few poses and code: Overgrowth moves fluidly from very few key poses, with the in-betweens
  computed ([Rosen, GDC 2014](https://gdcvault.com/play/1020049/Animation-Bootcamp-An-Indie-Approach)).
- Not found in a source we could open: typical lengths of start, stop and pivot clips, or how games choose the
  planting foot. Each transition issue researches its own move (footage of people, coaching texts) before keying,
  as the crawl's did.

**What we take.** The triggers are the controller's own numbers (the angle between velocity and the wanted
direction, the predicted speed), so transitions are chosen by code from `clips.json`, not hard-wired in a state
machine; every transition exists for a left and a right planting foot and the tree picks by the gait's phase; a
transition ends on a gait's exact pose and speed, and is long enough to be seen through, since a cut one freezes.

### Weight, overlap and follow-through {#research-weight}

<!-- new section: weight has to become numbers for the checks; these are the numbers found -->

- People walking at a comfortable 1.32 m/s take 118 steps a minute, 0.67 m a step, with a foot on the ground for
  60.7 % of its cycle; walking fast at 1.87 m/s, 141 steps a minute and 58.5 %
  ([Shemmell et al., 2007](https://pmc.ncbi.nlm.nih.gov/articles/PMC1866234/)).
- The centre of mass goes about 5 cm up and down twice a stride and about 6 cm side to side once
  ([gait kinematics, OUHSC](https://ouhsc.edu/bserdac/dthompso/web/gait/knmatics/gait.htm)).
- In walking the trunk turns 13.7 degrees against the pelvis and 6.9 against the ground: the shoulders counter the
  hips ([Chung et al., 2010](https://pmc.ncbi.nlm.nih.gov/articles/PMC2843703)).
- With running speed the planted share falls and the step rate rises
  ([Patoz et al., 2021](https://www.frontiersin.org/articles/625557)); we found no page we could open with a run's
  rise, hip turn or arm swing in numbers, so the run ranges in [the feel](#feel) are working numbers that the
  loops' issue confirms from its own research before keying.
- In games, anticipation is paid for in response time: keep the wind-up short on what the player does, long on
  what an enemy does, and let follow-through play out after the frame where control returns, cut only by new input
  ([Cooper](https://www.gamedeveloper.com/production/the-12-principles-of-animation-in-video-games)).
- Animators' tempo rules of thumb: a brisk walk is a step every half second, a run a step every quarter second or
  less; in a walk the body is lowest just after the foot lands and highest as the legs pass
  ([notes on Williams](https://s184753.blogspot.com/2019/01/more-research-animators-survival-kit.html); a
  secondary summary).
- A crouched walk has no figures here: the crouch gait studies found
  ([one](https://pmc.ncbi.nlm.nih.gov/articles/PMC3233366/)) are about crouch as a gait fault, not a crouch someone
  chooses, and no page we found gave a healthy crouched walk's cadence and step length, or the time of a drop from
  standing to a crouch. The crouch clips' numbers are working ones until a crouch issue measures them (gdstudio #1160).

**What we take.** The walk ranges in [the feel](#feel) are these figures at the game's speed. The library's Walk
takes 90 steps a minute at 0.96 m/s where people take 118 at 1.32. Follow-through goes after the frame the game
needs (the stop's feet are down at once; the arms settle after), and each clip names that frame in `clips.json`.

### The loose feel of Final Fantasy XV {#research-ffxv}

<!-- new section: the maintainer named this game's locomotion as the feel to aim for -->

What Square Enix has published, read in reports of the talks (we could not read the slides themselves):

- Motion capture first, polished by hand; an in-house system (Luminous) whose stated goal was bodies that fit the
  terrain, with foot IK and hit reactions
  ([CEDEC 2015](https://cedec.cesa.or.jp/2015/session/ENG/3674.html)).
- The dash is three clips blended by heading and turn rate: a left curve, straight, a right curve. Sudden braking
  picks a stop by speed: a kick-stop at high speed, a stop with a hand to the ground lower, an ordinary stop
  below, and none of them in combat. A vault keeps the dash's speed
  ([4Gamer on Kawachi, CEDEC 2017](https://www.4gamer.net/games/075/G007535/20170911060/)).
- Steering is limited by a motion model made from the animation data: the character turns as fast as its clips
  can ([CEDEC 2017](https://cedec.cesa.or.jp/2017/session/ENG/s58d4e4d623f8d.html)).

We found no animator's analysis of why it reads as loose, so this is our reading of the game, to be tested in the
variants and not a fact: the body commits to its momentum (it curves and leans through a turn, and brakes over
steps); the turn rate is limited by the motion and not the other way round; changes of state are whole clips; and
cloth, hair and hands keep moving after the body has stopped.

**What we take.** Curved-run clips (a left and a right arc blended by turn rate) join the gaits in a later wave;
stops are chosen by speed; the template's turn speed while sprinting becomes a number the turn clips and the
controller share. We have no capture, so looseness comes from the overlap pass and the lean
([how a clip is made](#making)).

### Additive layers and procedural parts {#research-layers}

<!-- new section: what is not a clip must be named, or the clip count multiplies by every direction and slope -->

- A cross-fade evaluates two clips for its whole length; inertialization evaluates only the new one and decays the
  difference in pose and speed measured at the switch, so the motion keeps its momentum
  ([Bollo, GDC 2018](https://gdcvault.com/play/1025165/Inertialization-High-Performance-Animation-Transitions);
  [Holden](https://theorangeduck.com/page/inertialization-transition-cost)).
- Godot has the parts: `AnimationNodeAdd2` for additive layers, blend spaces with cyclic sync that scale time to
  keep phase, `LookAtModifier3D` with limits and easing (4.4), `SpringBoneSimulator3D` (4.5), and `TwoBoneIK3D`
  and the other IK modifiers (4.6)
  ([IK returns](https://godotengine.org/article/inverse-kinematics-returns-to-godot-4-6/),
  [SkeletonModifier3D](https://docs.godotengine.org/en/stable/classes/class_skeletonmodifier3d.html)). It has no
  inertial blend node; one is a `SkeletonModifier3D` of ours.

**What we take.** Computed in the game from a few poses, and never a clip per case: the lean (additive, by
acceleration and turn rate), the aim (poses by pitch), the look (a modifier on head and chest), feet on slopes and
steps (the `ik_foot` targets with a pelvis offset), hands on a weapon (the hold solver), recoil size. The momentum
blend is a modifier written in the Godot issue. All of it is cosmetic and never networked.

### Cost in the web build {#research-web}

<!-- new section: the web build is single-threaded; what compression and track counts buy had to be read and measured -->

- Godot's importer reduces keys by default (velocity and angular error 0.01) and can pack tracks into bit-width
  pages, said to be 5 to 10 times smaller; packed tracks cannot be edited and are lossy
  ([data redesign](https://godotengine.org/article/animation-data-redesign-40),
  [Animation](https://docs.godotengine.org/en/stable/classes/class_animation.html)). Our measurement on the
  library: 2.7 times smaller than the default, 5.7 times smaller than unreduced
  ([what the clips cost](#audit-cost)).
- Engines cap the bones that cost: Unreal's mobile path allows 75 bones a mesh section
  ([rendering paths](https://dev.epicgames.com/documentation/en-us/unreal-engine/skeletal-mesh-rendering-paths-in-unreal-engine)),
  and far characters are animated less often, about 10 updates a second with interpolation between
  ([budget allocator](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-budget-allocator-in-unreal-engine));
  the template's `AnimationThrottle` already does the second.
- Godot's web export is single-threaded by default and slower than native
  ([exporting for web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)). We found
  no published cost per blended track; the Godot issue measures it in the browser.

**What we take.** [The budget](#budget).

### One clip set on many bodies {#research-bodies}

<!-- new section: later games use other proportions; how engines carry clips across them decides what a clip may key -->

- Unreal retargets only translations: rotations always come from the clip, the pelvis's translation is scaled, the
  root and IK bones keep the clip's, every other bone keeps its own skeleton's. Hands miss props and feet miss the
  floor on other proportions, and both are put back by IK toward bones that carry the clip's intent
  ([retargeting](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-retargeting-in-unreal-engine)).
- Godot's retarget divides position tracks by the hips' height and multiplies by the playing skeleton's
  `motion_scale`, and can drop every position track but the root's and the hips'
  ([retargeting 3D skeletons](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html)).
- Not found in a source we could open: how games stop limbs entering a body with a large head or short arms, or
  per-body correction poses. The clearance pose in [other proportions](#proportions) is our own design and is
  proved on the chibi body before any clip depends on it.

**What we take.** The rig's rules are these ([the rig](#rig)): rotations everywhere, positions on the pelvis, the
root and the IK targets, one rest orientation for every body.

## The feel, as numbers {#feel}

<!-- new section: "loose and fluid" has to be a set of numbers a build can check, or every review argues taste -->

The targets our clips are built to and measured against, with the same script as the audit. Each variant may move
inside the ranges; a number outside one is a decision written in the variant's notes, not an accident.

| Measure | Walk | Jog | Sprint | Why |
| --- | --- | --- | --- | --- |
| Planted sole speed | the game's 1.7 m/s, within 2 % | 4.0 m/s | 6.5 m/s | the feet hold the floor at the speed the body moves |
| Steps a minute | 125 to 140 | 165 to 180 | 190 to 215 | a person's cadence at that speed (the walk's from [research](#research-weight); the runs' are working numbers) |
| Planted share | 0.57 to 0.62 | 0.30 to 0.40 | 0.22 to 0.30 | a walk always has a foot down; a run flies between steps |
| Pelvis up and down | 30 to 50 mm | 60 to 90 mm | 50 to 80 mm | weight without a bounce |
| Hips turn, shoulders turn | 6 to 10, 6 to 10 degrees, opposed (about 14 between them) | 8 to 14, 15 to 25 | 10 to 16, 20 to 30 | the trunk winds against the legs; the arms swing in their sockets |
| Pelvis tips toward the swinging leg | 4 to 8 degrees | 5 to 10 | 5 to 10 | the hip drops over the leg that carries nothing |
| Trunk lean at a steady pace | 2 to 5 degrees | 4 to 8 | 6 to 12 | the rest of the lean is acceleration's, added by the lean layer |
| Forearm behind upper arm, hand behind forearm | 1 to 2 frames each | 1 to 2 | 1 to 2 | each part starts after the part it hangs from |
| Chest behind hips, head behind chest | 1 to 3 frames | 1 to 2 | 1 to 2 | the turn travels up the spine |
| Halves of the cycle differ by | 1 to 4 degrees | 1 to 4 | 1 to 4 | alive, but no limp |
| Fingers | curl and open a few degrees with the arm swing | same | same | no dead hands |

What makes it loose is in the joins, more than in the loops:

- **Every change of speed or direction has its own clip** ([the set](#set)): starts, stops, pivots, the sprint
  reversal, turns on the spot, landings into a run.
- **The lean is acceleration.** Starting, stopping and turning lean the body by `atan(a / g)` of the acceleration
  the controller is really applying, as an additive layer over any gait, so a 6 m/s2 start leans 31 degrees for
  the moment it lasts and a steady run stands nearly upright.
- **Nothing stops on one frame.** After a stop the pelvis settles first, then the chest, then the arms and the head,
  each a frame or two later, each overshooting a little.
- **Blends carry momentum.** A new clip starts from the pose and the speed of the old one, not from a mix of two
  poses ([in the tree](#replacing)).

**No mirror poses.** A held pose is never the same on both sides: one foot ahead of the other and turned out
more, one knee lower, the weight more on one leg, the hips and shoulders tilted and turned a little against each
other, the hands at different heights and doing different things. Start a held pose from how a person rests in it
(the library's crouch idle has one heel up, the knees apart at different heights, one forearm on a knee), then
write each side's numbers on their own. A mirrored clip for the other foot is the build's job, not a reason to make
one clip symmetric about its own middle.

- **Approach:** Give every pose and loop its own numbers per side (stance, knee height, weight, hand place and
  task), check a capture from the front and from above for anything lined up, and compare it with the library clip
  it replaces before it goes to review. **Watch out for:** our crouch idle stood with the feet side by side and level
  and the hands placed evenly on both sides, which read as squatting on a toilet beside the library's staggered,
  relaxed crouch; the clip toolkit's style files and solved poses drift toward symmetry unless each side is asked
  for on its own. **Seen:** gdstudio #1160 (PR #1285), 2026-11-11, from the maintainer's review.
- **Approach:** Check a one-shot on the every-frame front sheet, not only on the key frames, for limbs that line up on
  the way out and back, and pose each hand from its own per-side table, never from one tuple with a flipped sign.
  **Watch out for:** the melee clips had the guard and the striking fist level at frames 4 and 12 to 14, between keys,
  so the key-frame sheet looked uneven while the move passed through a mirror pose; a flipped tuple mirrors the sides by
  construction. **Seen:** gdstudio #1254, 2026-11-11.

## The set we will own {#set}

<!-- new section: the issue asks for the grouped list, replacements told from new clips, and what depends on the body -->

R replaces a library clip the template plays; N is new (the library has none, or the template plays none). Body: I
plays on any proportions with no new keys; C needs its contacts carried by the `ik_` targets
([other proportions](#proportions)); B needs a pass per body, because limbs touch the body itself.

| Group | Clips | R or N | Body |
| --- | --- | --- | --- |
| Locomotion | `Idle`, `Walk`, `Jog`, `Sprint` | R | I |
| | `Walk_Back`, `Walk_Left`, `Walk_Right`, `Jog_Back`, `Jog_Left`, `Jog_Right` (aiming moves any way) | N | I |
| | `Crouch_Idle`, `Crouch_Walk` | R | I |
| | `Lean_Left`, `Lean_Right`, `Lean_Fwd`, `Lean_Back` (additive poses) | N | I |
| Transitions | `Idle_To_Walk`, `Idle_To_Jog`, `Idle_To_Sprint`, each left and right foot first | N | I |
| | `Walk_Stop`, `Jog_Stop`, `Sprint_Stop`, each on the left and the right foot | N | I |
| | `Jog_Turn_180`, `Sprint_Turn_180`, each planting left and right; `Jog_Turn_90_L/R` | N | I |
| | `Turn_In_Place_90_L/R`, `Turn_In_Place_180_L/R` | N | I |
| | `Stand_To_Crouch`, `Crouch_To_Stand`; `Crouch_To_Prone`, `Prone_To_Crouch` (ours since #1009) | N | I, the prone pair C |
| | `Jump_Start` (standing, running), `Jump_Rise`, `Jump_Apex`, `Jump_Fall`, `Land_Soft`, `Land_Hard`, `Land_To_Jog` | R, the split and the run landing N | I |
| | `Slide_Start_L/R`, `Slide`, `Slide_To_Jog`, `Slide_To_Crouch` | R | C |
| Combat and weapons | per weapon class (pistol, rifle, fists): `Hold`, `Aim` at five pitches, `Shoot`, `Reload`, `Raise`, `Lower`, `Switch` | R, the last three N | C: hands on the weapon's sockets |
| | `Punch_Jab`, `Punch_Cross`, a guard pose, each blow with a step | R | B |
| | `Throw` | N | I |
| Traversal | `Vault_Low`, `Vault_High`, `Vault_Mantle` (kit #1016), a second mantle height, `Push` | R | C |
| | `Prone_Idle`, `Crawl_Fwd` (ours since #1009), `Crawl_Back`, `Crawl_Left`, `Crawl_Right` | N | C: forearms on the floor |
| | `Climb_Ladder`, `Swim_Idle`, `Swim_Fwd` | N | C |
| Reactions | `Hit_Front`, `Hit_Back`, `Hit_Left`, `Hit_Right` (additive), `Knockback`, `Stagger` | R, three sides N | I |
| | `Death_Front`, `Death_Back` (when no ragdoll is allowed), `Get_Up_Front`, `Get_Up_Back` | R, the get-ups N | C |
| | `Interact_Low`, `Interact_Mid`, `Interact_High`, `Pick_Up` | R | C |
| Idles and emotes | three idle breaks (a look round, a stretch, a shift of weight), `Idle_Armed`, `Wave`, `Point`, `Nod`, `Shake_Head` | N | I, B for the stretch |

That is about 110 clips against the 27 played today. Left-and-right pairs are one authored clip and its mirror,
which the build makes ([how a clip is made](#making)); the first wave is the
locomotion rows and the transitions down to the jumps, without the prone pair.

Not clips: the look at a target, the lean's strength, feet on a slope, the hands on a weapon and the recoil's size
are computed in the game from a few poses ([additive and procedural](#research-layers)), and stay cosmetic, never
networked.

## How a clip is made {#making}

<!-- new section: clips had been solved one build script at a time; a hundred clips need one shared way -->

**By script, always.** A clip is a Python description that a build solves into keys, as the prone and vault clips
are ([Clips solved from targets](animation.md#solved-clips); the vault clips' section of that page, "A clip that
touches the world", lands with kit #1016).
Nothing is keyed by hand in Blender's interface: a hand-keyed clip cannot be rebuilt, compared byte for byte, made
in three variants from one description or rebuilt when the rig's proportions change. A library clip may be read as
a starting pose or a timing reference, never copied into ours.

The first child issue builds the shared toolkit (`templates/3d-third-person/game/assets/animation/own/gdsanim/`),
so a clip's own file holds only what is particular to it:

1. **Controls in the world.** The pelvis, each ankle and wrist, where each knee and elbow points, the chest's and
   the head's turn, each as a curve in the world of a reference floor, with the root moving at the clip's speed
   (a constant for a loop, a curve for a transition) that is taken out again on export. Planted feet are two keys
   at one place.
2. **A contact plan first.** A gait is written as its footfalls: which foot, when it lands, when it leaves, how
   far ahead it lands. Foot paths, the pelvis's height and the trunk's wind are derived from the plan, so cadence,
   planted share and speed are inputs, not things that happen.
3. **Solved, not posed.** Limbs by two-bone solves about the rig's own hinges, the trunk from pitch, yaw and roll,
   the pelvis from the centre of mass where the body leaves the ground or changes speed (segment masses on the
   bones; lean equals acceleration).
4. **Overlap as a pass.** Arms, hands, fingers, the chest and the head take their motion through a damped spring
   from the part they hang from, each with a delay and an overshoot that are the variant's numbers, then are baked
   to keys. Loops run the pass round the cycle until it closes.
5. **Mirrors and families.** The build mirrors a clip for the other foot or side, and makes a family (the stops
   from three gaits) from one description with other numbers.
6. **Variants are parameter sets.** A variant is the same description with another style file (`style_a.json`):
   cadence, bob, wind, lean, delays, overshoot, timing of the poses. Three visions cost three small files.
7. **Checked, then exported.** The build runs [the checks](#checks) before it writes anything, exports at 30
   frames a second with the frozen clip list, and writes `clips.json` beside the glb: per clip its loop flag,
   speed, root travel and turn as curves, contact times per foot, the foot it starts and ends on, and the event
   frames (footsteps).

Clips are **in place** with their travel in `clips.json`, as the rig's root section allows: the template's
controller moves the body (it is predicted and networked), and the tree fits the clip to it. A
game that wants root motion builds the same descriptions with the root keyed.

## The checks a clip passes {#checks}

<!-- new section: a clip of ours has to beat the library's by measure, so the measures and their limits are fixed -->

In the build, on every frame and on every shipped body's skinned mesh, before the export; a failure stops the build.

| Check | Limit |
| --- | --- |
| Loop seam | the last pose is the first to the bit; the change of speed across the seam is no more than the largest in the cycle |
| Floor | a planted sole's lowest vertex within 2 mm of the floor; no vertex more than 5 mm under it on any frame; a crouched clip under its capsule's height (`ceiling`) |
| Planted feet | a planted sole wanders at most 5 mm in a contact at the clip's speed; the speed in `clips.json` is the measured one within 2 % |
| Planted hands, forearms, knees | at most 1 mm of drift in the world while planted (as the vault clips, kit #1016) |
| Limbs inside limbs | at most 5 mm on every body (`limb_overlap.py`) |
| Gait | legs half a cycle apart within a frame; each arm with the other side's leg (correlation over 0.7); shoulders against hips; cadence, planted share and bob inside [the feel](#feel)'s ranges or the variant's declared ones |
| Overlap | the forearm, hand, chest and head each trail their parent by the variant's declared frames, within half a frame; no part moves more than 0.5 degrees on the frame a contact lands without its parent moving |
| Weight | in the air the centre of mass is on a free fall's arc within 15 mm; on the ground its lean is the acceleration's within 5 degrees; standing, it is over the feet; with a foot down it drops at no more than 1.05 of gravity |
| Joins | a transition's first and last pose are the poses it joins within 1 mm and half a degree, at the phase `clips.json` names, and its speed there is the joined clip's |
| Travel | a transition's root travel is the distance and the turn `clips.json` declares; a planted foot stays within 5 mm in the world while the root travels |
| Limits | no joint past a person's range ([the ragdoll's limits](../../engines/godot/ragdoll.md#limits)); no elbow or knee bending backward; no change of a joint's speed over a per-joint limit in one frame |
| Cost | [the budget](#budget): bones moved, keys kept, imported bytes |
| The frozen list | the build exports exactly the clips its issue names; a rebuild writes the same bytes |

In Godot (`tests/gameplay/test_own_clips.gd`, on every body): every track finds its bone, loops loop, joins meet
bone by bone, a planted foot stays put while the model moves along the clip's travel curve, and the tree plays the
clip where the library's played. Then the capture from the game's camera.

Passing every check is where review starts, not where it ends: the crawl passed every check with its forearms
wrong ([solved clips](animation.md#solved-clips)). Before keying a move, its motion is researched and written down
with sources (how real limbs do it), and each fault a capture shows becomes a check when a number can say it.

## Three variants and the review sheet {#review}

<!-- new section: the maintainer chooses between variants; what they are shown has to be the same for every clip -->

Every clip type ships in at least three variants, each a vision with its emphasis, for example for the gaits:
**A, grounded** (a person's numbers: low bob, true cadence, small overlap), **B, loose** (the hips lead, long
overlap on arms and head, more wind and lean, a later settle), **C, sharp** (stronger key poses, shorter eases,
fewer in-betweens; reads at a distance and on a small low-polygon body). The agent may propose others; the three
must differ in a number the sheet shows, not only in taste.

The pull request for a clip type carries one **review sheet** per type, made by the toolkit's `review_sheet.py`
(no hand step), attached with `gh pr create --attach`:

1. **A strip image:** one column per variant and a last column for the library clip it replaces (or "none"), every
   column the same frames of the cycle; rows for the side, the front and the top, over a 0.25 m floor grid moving at
   the game's speed, so a foot that slides is seen sliding.
2. **A clip (mp4):** the variants side by side in Godot from the game's camera, on the template's map: the loop for
   five seconds, then the moves that use it (start, turn, stop) driven by the same recorded input for each
   (`tools/capture/own_clips_review.tscn`; `OWN_ONLY=<clip>` films one variant, short enough for a GIF).
3. **The numbers:** the audit's table with one column per variant and the library's, the limits beside them.
4. **Notes:** two lines per variant: the vision, and what was tried and could not be done, with the number that
   shows it. A fault the agent can name in its own capture is fixed before review, not listed
   (learned on the vault clips, kit #1016).
5. **Other bodies:** the same frame of each variant on every shipped body (male, female, chibi).

The pull request carries `S-hold`; the maintainer answers with a letter per clip type, or with a change. The
variants live in `own/review/<type>.glb` under their letters (`Walk_A`) and are not imported by the game; the
chosen one is built again under its plain name into the shipped file by the same pull request once chosen, and the
other style files stay in the repository, so a game picks another vision by rebuilding.

- **Approach:** When a clip declares its own limits, read its numbers on the review sheet against those, and say so in
  the sheet's notes. **Watch out for:** the sheets print the checks' default limits even where a clip declares its own,
  so a 0.42 or a 17.99 (keys kept, key bytes a second, on a 22-frame stride) looks like a failure that passes. **Seen:**
  gdstudio #1160 (PR #1285), 2026-11-11.

## How a chosen clip replaces the library's {#replacing}

<!-- new section: swapping a clip touches the constants, the tree and the web build; the steps are the same each time -->

1. **A library of our own.** The shipped clips are `assets/animation/own/<group>.glb`, imported as animation
   libraries under one name, `gds` (`gds/Walk`), beside `ual1` and `ual2`. Today the library is the one file
   `locomotion.glb`; a second group's file needs the tree's issue to merge them under the name.
2. **The constant moves.** `CharacterClips.WALK` becomes `&"gds/Walk"`; the library's name stays in `ALL` and in a
   `STAND_INS` table, so a game or a test can put the library clip back in the inspector, and a test proves each
   stand-in still plays.
3. **The tree reads `clips.json`.** Blend points sit at the clips' measured speeds; each gait plays at ground speed
   over clip speed; transitions are picked by the gait, the planted foot and the turn asked for, and are played
   along their travel curve against what the controller really did. That is the Godot child issue, not a clip
   issue.
4. **The web build drops what nothing plays.** Once a group is replaced, the libraries' unused clips leave the
   exported game (an import script keeps the clips a list names; the full files stay in the repository for
   stand-ins and study), and the size before and after goes in the pull request.
5. **Docs.** The clip's row on `engines/godot/third-person/clips.md` and the template's inspector list change in
   the same pull request.

## The rig, and other proportions {#rig}

<!-- new section: the clips and the prototype mannequins are made at once and must agree on one skeleton -->

Clips are keyed on the prototype mannequins' skeleton (kit #1149, `mannequin-rig.md`): the library's 65 bones with
its rest orientations, plus twist bones, sockets and four `ik_` targets that no library clip keys. What the plan
takes from it:

- **Only rotations, and positions on `pelvis`, `root` and the `ik_` targets.** No scale keys. Twist bones and
  sockets are never keyed.
- **The reference body** is the one whose `pelvis` rests 0.9166 m up; position keys are in its metres and a body
  with other legs scales them by `motion_scale`.
- **In place**, with the travel in `clips.json` ([how a clip is made](#making)).
- **Our clips key the `ik_` targets** wherever a foot or a hand is planted, with a weight curve in `clips.json`
  that is 1 while it is planted.

What the clips need from the rig, asked of #1149:

- each body's sole points (heel, ball, toe tip, in the foot bone's space) and palm point in `rig_<body>.json`, so
  the floor and contact checks and the foot solve agree on where a sole is;
- segment masses per bone in `rig_<body>.json` for the centre-of-mass checks;
- each body's leg length (hip joint to sole) and arm length, for the speed a clip covers on that body;
- the part of each bone for the overlap check, twist bones with their limb;
- which bones a far level of detail drops, so a clip can ship without their tracks;
- `ball_l/r` hinged flat to the floor at the ball of the foot, so a heel can lift over planted toes.

### Other proportions {#proportions}

<!-- new section: later games use chibi and realistic bodies; the plan must say what carries over and what does not -->

A clip stores each bone's turn in its parent, so on a body with other bone lengths the joints turn the same and
the ends of the limbs land elsewhere. What is done about each consequence:

| What changes on another body | What carries it over |
| --- | --- |
| Step length, and so the ground a gait covers | `clips.json` speed times the body's leg length over the reference's; the game plays the clip at ground speed over that |
| Pelvis height, bob and travel | `motion_scale` scales the position keys |
| A planted foot's place | the `ik_foot` targets and a two-bone solve in the game, on while the clip's weight curve says planted |
| A hand on a weapon or an obstacle | the socket and the hold solver, or the `ik_hand` targets |
| Limbs meeting the body (a big head, short arms, wide hips) | a per-body clearance pose, made by the body's build from the overlap check: an additive offset on the collarbones and upper arms that the tree always adds |
| Weight (a heavy or a tiny body) | the style file: a body type may take its own variant numbers through the same descriptions |

Group I clips need nothing but the first two rows. The checks run on every shipped body, the chibi included, so a
clip that only works on the reference fails its build.

## The budget in the web build {#budget}

<!-- new section: cost counts in the web build; a clip set five times larger must not cost five times more -->

| What | Budget | How |
| --- | --- | --- |
| Tracks a gait clip keys | 22 body bones and the pelvis's position; fingers only where they move | fingers at rest come from one hand-pose clip under the gait; a clip names its bones and the export strips the rest |
| Keys | under 40 % of the frames on a moving bone at half a degree | curves solved at 30 a second, reduced by the build, checked against the full curve on the skinned mesh (1 mm at the hands and feet) |
| Imported size | 6 KB a second of clip, compressed import; the first wave under 250 KB | measured by importing in Godot in the build's test, per file (`Idle`: 3.9 KB a second, with the importer's optimizer off: [the libraries](../../engines/godot/third-person/clips.md#animation-libraries)) |
| Clips blended at once | four on a character near the camera (two gaits, a transition or an action, one additive); one on a far one | the tree's layers are counted in the Godot issue's bench, in the browser |
| Download | the web build's pack no larger after the first wave than before it | the libraries' unplayed clips leave the export ([replacing](#replacing)) |

## Waves and child issues {#waves}

<!-- new section: the plan files its own work; the order and the reason for it belong with the plan -->

The first wave is locomotion and its transitions, in this order (each issue names its clips and its checks, and
every clip pull request carries `S-hold` for the maintainer's choice of variant):

| Issue | Clips |
| --- | --- |
| #1154 the clip toolkit and the review sheet (done) | `Idle`, three variants, A shipped as `gds/Idle`; the shared build, the checks and their self-test, `review_sheet.py`, the first swap ([the toolkit](animation.md#toolkit)) |
| #1155 the loops | `Walk`, `Jog`, `Sprint` |
| #1156 starts and stops | `Idle_To_Walk`, `Idle_To_Jog`, `Idle_To_Sprint`; `Walk_Stop`, `Jog_Stop`, `Sprint_Stop`; left and right |
| #1157 the reversal, pivots, turns on the spot | `Sprint_Turn_180`, `Jog_Turn_180`, `Jog_Turn_90_L/R`, `Turn_In_Place_90_L/R`, `Turn_In_Place_180_L/R` |
| #1158 the tree (Godot) | speed matching, transitions by code from `clips.json`, the momentum blend, the lean layer, the browser cost |
| #1159 directions and lean | `Walk_Back`, `Walk_Left`, `Walk_Right`, `Jog_Back`, `Jog_Left`, `Jog_Right`; `Lean_Left`, `Lean_Right`, `Lean_Fwd`, `Lean_Back` |
| #1160 crouch (done) | `Crouch_Idle`, `Crouch_Walk`, `Stand_To_Crouch`, `Crouch_To_Stand`, A shipped; the prone transitions rebuilt on the new crouch |
| #1161 jumps | `Jump_Start` (standing, running), `Jump_Rise`, `Jump_Apex`, `Jump_Fall`, `Land_Soft`, `Land_Hard`, `Land_To_Jog` |

Later waves, filed when the first has landed and its toolkit has settled: the slide and the curved runs; combat
and weapons (per weapon class, with the hold solver); traversal (the second mantle, the push, the crawl's other
directions, a ladder, swimming); reactions (hits by side, knockback, deaths and get-ups, interactions at three
heights); idles and emotes.

- **Approach:** Measure a library's clips on the skinned mesh, at the speeds the game plays them, before planning
  what replaces them, and read the numbers against what the game does with each clip. **Watch out for:** the
  template's gaits looked acceptable in every capture since it shipped, while the walk's feet covered 56 % of the
  ground and the jog's swept 48 % faster than it; nobody had divided a clip's planted speed by the speed its blend
  point sits at. **Seen:** gdstudio #1150, 2026-11-11 (`audit_clips.py`; the fix is #1158).
