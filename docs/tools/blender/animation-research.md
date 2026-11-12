# What good game animation is made of

<!-- new section: moved from own-animation.md#research when that page went past 50 KB with the gaits' sourced
ranges; the plan's choices rest on how other studios and the gait studies solved the same problems, studied and
never copied (kit #1150, #1155) -->

The research behind [Our own animation set](own-animation.md): what the plan's numbers and choices rest on.

Read for this plan on 2026-11-11; each finding names the page it came from. Other studios' work is studied for how
it solves a problem and never copied: no clip, curve or data of theirs is used. Where a claim had no source we could
open, it says so.

## Locomotion systems {#research-locomotion}

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
  ([a write-up of Delayen's
  talk](https://gamedeveloper.com/programming/most-inspiring-game-animation-tech-talks-of-2016)).
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

## Transitions {#research-transitions}

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

## Weight, overlap and follow-through {#research-weight}

<!-- new section: weight has to become numbers for the checks; these are the numbers found -->

- People walking at a comfortable 1.32 m/s take 118 steps a minute, 0.67 m a step, with a foot on the ground for
  60.7 % of its cycle; walking fast at 1.87 m/s, 141 steps a minute and 58.5 %
  ([Shemmell et al., 2007](https://pmc.ncbi.nlm.nih.gov/articles/PMC1866234/)).
- The centre of mass goes about 5 cm up and down twice a stride and about 6 cm side to side once
  ([gait kinematics, OUHSC](https://ouhsc.edu/bserdac/dthompso/web/gait/knmatics/gait.htm)).
- In walking the trunk turns 13.7 degrees against the pelvis and 6.9 against the ground: the shoulders counter the
  hips ([Chung et al., 2010](https://pmc.ncbi.nlm.nih.gov/articles/PMC2843703)).
- Recreational runners at 2.75 m/s take 164 steps a minute with a foot down 39 % of the cycle and the centre of
  mass going 77 mm (SD 12) up and down; each m/s faster adds 11 steps and takes 5.9 points off the share, and the
  rise does not change ([reference values, 2023](https://pmc.ncbi.nlm.nih.gov/articles/PMC10588426/)). Elite
  sprinters at 10.6 m/s take 274 steps with 96 ms on the ground
  ([2021](https://pmc.ncbi.nlm.nih.gov/articles/PMC8008308/)). The sprint's 6.5 m/s lies between the two sets;
  no page we could open gave a shoulder's swing in degrees (the gaits' README has the whole table).
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

**What we take.** The walk ranges in [the feel](own-animation.md#feel) are these figures at the game's speed. The
library's Walk
takes 90 steps a minute at 0.96 m/s where people take 118 at 1.32. Follow-through goes after the frame the game
needs (the stop's feet are down at once; the arms settle after), and each clip names that frame in `clips.json`.

## The loose feel of Final Fantasy XV {#research-ffxv}

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
([how a clip is made](own-animation.md#making)).

## Additive layers and procedural parts {#research-layers}

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

## Cost in the web build {#research-web}

<!-- new section: the web build is single-threaded; what compression and track counts buy had to be read and measured -->

- Godot's importer reduces keys by default (velocity and angular error 0.01) and can pack tracks into bit-width
  pages, said to be 5 to 10 times smaller; packed tracks cannot be edited and are lossy
  ([data redesign](https://godotengine.org/article/animation-data-redesign-40),
  [Animation](https://docs.godotengine.org/en/stable/classes/class_animation.html)). Our measurement on the
  library: 2.7 times smaller than the default, 5.7 times smaller than unreduced
  ([what the clips cost](library-clip-audit.md#audit-cost)).
- Engines cap the bones that cost: Unreal's mobile path allows 75 bones a mesh section
  ([rendering
  paths](https://dev.epicgames.com/documentation/en-us/unreal-engine/skeletal-mesh-rendering-paths-in-unreal-engine)),
  and far characters are animated less often, about 10 updates a second with interpolation between
  ([budget
  allocator](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-budget-allocator-in-unreal-engine));
  the template's `AnimationThrottle` already does the second.
- Godot's web export is single-threaded by default and slower than native
  ([exporting for web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)). We found
  no published cost per blended track; the Godot issue measures it in the browser.

**What we take.** [The budget](own-animation.md#budget).

## One clip set on many bodies {#research-bodies}

<!-- new section: later games use other proportions; how engines carry clips across them decides what a clip may key -->

- Unreal retargets only translations: rotations always come from the clip, the pelvis's translation is scaled, the
  root and IK bones keep the clip's, every other bone keeps its own skeleton's. Hands miss props and feet miss the
  floor on other proportions, and both are put back by IK toward bones that carry the clip's intent
  ([retargeting](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-retargeting-in-unreal-engine)).
- Godot's retarget divides position tracks by the hips' height and multiplies by the playing skeleton's
  `motion_scale`, and can drop every position track but the root's and the hips'
  ([retargeting 3D
  skeletons](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html)).
- Not found in a source we could open: how games stop limbs entering a body with a large head or short arms, or
  per-body correction poses. The clearance pose in [other proportions](own-animation.md#proportions) is our own
  design and is
  proved on the chibi body before any clip depends on it.

**What we take.** The rig's rules are these ([the rig](own-animation.md#rig)): rotations everywhere, positions on the
pelvis, the
root and the IK targets, one rest orientation for every body.
