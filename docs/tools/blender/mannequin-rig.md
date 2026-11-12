# The prototype mannequin rig

<!-- new section: GDStudio's own rig is a contract two issues build on (#1149 the bodies, #1150 the clips); the
rigging page is about cleaning and sharing the Quaternius kit rigs -->

GDStudio's own prototype bodies (kit #1149: a male, a female and a chibi body in three looks, under
`templates/3d-third-person/game/assets/characters/prototype/`) share one skeleton. This page is that skeleton's
contract: the clips of kit #1150 are keyed on it, the Universal Animation Library plays on it, and a game's own body
(any proportions) is built on it. The research behind the choices is on
[Prototype mannequins](prototype-mannequins.md).

## The skeleton {#skeleton}

<!-- new section: the rigging page covers the Quaternius kit rigs; nothing named the bones, rest pose and sockets of
GDStudio's own rig, which two issues (#1149 the bodies, #1150 the clips) build on at once -->

**82 bones: the Universal Animation Library's 65, unchanged, plus 17 leaves.** A clip made on this rig keys only the
65; the 17 are never keyed by a locomotion or action clip (the four `ik_` targets may be, see below).

| Group | Bones | Parent | Keyed by clips |
| --- | --- | --- | --- |
| Root | `root` | the armature | position and yaw only in root-motion clips; in-place clips leave it at rest |
| Trunk | `pelvis`, `spine_01`, `spine_02`, `spine_03`, `neck_01`, `Head` | a chain from `root` | rotation; `pelvis` also position |
| Arm (`_l`, `_r`) | `clavicle`, `upperarm`, `lowerarm`, `hand` | a chain from `spine_03` | rotation |
| Fingers (`_l`, `_r`) | `thumb`, `index`, `middle`, `ring`, `pinky`, each `_01`, `_02`, `_03` and a `_04_leaf` | chains from `hand` | rotation (`_04_leaf` never) |
| Leg (`_l`, `_r`) | `thigh`, `calf`, `foot`, `ball`, `ball_leaf` | a chain from `pelvis` | rotation (`ball_leaf` never) |
| Twist (`_l`, `_r`) | `upperarm_twist_01`, `lowerarm_twist_01`, `thigh_twist_01` | the limb bone it is named after | never: driven in the engine |
| Sockets | `socket_hand_r`, `socket_hand_l`, `socket_back`, `socket_hip_l`, `socket_hip_r`, `socket_head`, `socket_camera` | `hand_r`, `hand_l`, `spine_03`, `pelvis`, `pelvis`, `Head`, `Head` | never |
| IK targets | `ik_foot_l`, `ik_foot_r`, `ik_hand_l`, `ik_hand_r` | `root` | optional (below) |

Names are the library's, to the letter (`Head` has a capital, the sides are `_l` and `_r`, a finger's last bone is
`_04_leaf`). 58 bones carry skin: the 65 less `root` and the twelve `_leaf` bones, plus the six twist bones.

## The rest pose {#rest-pose}

<!-- new section: the rest pose is the one thing a clip cannot be moved across, so it is fixed here before any clip
is keyed -->

- **Axes.** In the exported file and in Godot: +Y up, +Z the way the character faces, +X the character's left, metres,
  the origin on the floor between the feet. (In Blender: +Z up, -Y the front.)
- **A T pose, with the library's rest orientations to the bit.** The arms lie straight out along X, palms down, the
  legs straight down, the feet pointing forward. Every one of the 65 bones has the library rig's rest rotation in its
  parent (the table is `skeleton.py`'s `REST_ROTATION`, read from the library and checked by the build against the
  file it writes, to 1e-4). A clip stores each bone's rotation in its parent, so this is what lets one clip play on
  every body, and it is why the rest is a T although the bodies are modelled in an A (below).
- **Bodies differ only in rest translations.** A body is a set of bone lengths and joint places (`bodies.py`); no bone
  is ever scaled, in the rest or in a clip. Scale keys are not allowed in a clip.
- **The shoulders and hips are balls in sockets, so the T rest costs the skin nothing.** A T rest is said to skin
  the shoulder badly once the arm hangs. The mannequins' upper arm and thigh end in a dome that turns inside the
  trunk's shell and is not blended into it, so the hanging arm is as clean as the raised one. A body with one
  continuous skin over the shoulder should be modelled with the arms 45 degrees down and its vertices stored on the T
  rest (each moved by the inverse of its own blended bone matrix).
- **Hips height and `motion_scale`.** The library keys `pelvis`'s position for a body whose `pelvis` rests 0.9166 m up.
  A body with other legs sets `Skeleton3D.motion_scale` to its own `pelvis` rest height over 0.9166 (the import script
  does it from the number the build writes), and Godot multiplies every bone position key by it. The male and the
  female keep 0.9166 (scale 1); the chibi's is in the table below. **A clip keys positions only on `pelvis`, `root`
  and the `ik_` targets,** always in the reference body's metres.

- **The library's files key a position on every bone; only the pelvis's may reach a body.** Both library files hold
  a translation channel for each of the 65 bones in each of their 43 clips. All but the pelvis's are constant and
  equal the library body's own rest (measured on the files: the only moving position is `pelvis`, in 34 and 42 clips),
  so they carry the library's proportions, and played on another body they pull its joints to the library's places
  and stretch it. Godot's import drops them while `animation/remove_immutable_tracks` is on (the template's
  setting for both libraries), and `tests/assets/test_prototype_mannequins.gd` fails if a position track on any bone
  but `pelvis` or `root` reaches the game. A tool that reads the files itself (a Blender script, another engine, a
  retarget step) must drop every position channel except `pelvis` and `root` before it plays a clip on a body of
  other proportions, and scale the pelvis's by the body's `motion_scale`.

## Twist bones {#twist}

<!-- new section: twist bones are new to GDStudio's rigs and are driven, not keyed -->

Each twist bone sits where its limb's roll must not show, has its limb bone's rest orientation, and is turned in the
engine by `MannequinTwist` (a `SkeletonModifier3D` the import script adds), never by a clip:

| Bone | Where | What the modifier does |
| --- | --- | --- |
| `upperarm_twist_01_l/r` | at the shoulder end of `upperarm` | takes the upper arm's roll about its own length back out, so the shoulder's skin stays with the chest |
| `lowerarm_twist_01_l/r` | at the wrist end of `lowerarm` | takes the hand's roll about the forearm's length, so the forearm's skin turns gradually from elbow to wrist |
| `thigh_twist_01_l/r` | at the hip end of `thigh` | takes the thigh's roll back out, so the hip's skin stays with the pelvis |

The skin's weights run from the limb bone to its twist bone along the limb's length. With no modifier the twist bones
stay rigid on their parents and the body skins as a rig with no twist bones does, so a far level of detail and a
dedicated server skip the modifier.

A check in Blender turns them too: no clip keys a twist bone, so a build or a measure that skins the clip's pose
alone reads the limbs' skin where no player sees it. `limb_overlap.apply_twist` (the template's
`assets/animation/limb_overlap.py`) does the modifier's swing-twist split on the posed armature, and can use the
modifier's own formula because Blender's glTF importer keeps the file's bone axes when it is called with
`bone_heuristic="BLENDER"` (the default for these scripts); a Godot test that reads bones straight after
`seek` calls `MannequinTwist.apply` itself ([solved clips](animation.md#solved-clips)).

## Sockets {#sockets}

<!-- new section: sockets are named bones on this rig, so a weapon or a camera is attached by name on every body -->

A socket is a bone with no skin: attach to it with a `BoneAttachment3D` by name. Body sockets rest with the model's
axes (+Y up, +Z front). Hand sockets rest with **-X along the fingers and +Y toward the thumb's side**, the kit's
weapon axes (the muzzle is -X, the top +Y: [Weapons](weapons.md#axes-origin-and-the-hold)), and sit in the middle of
the palm, one grip radius off its skin, so a kit weapon lies in either hand the same way with no turn of its own.

| Socket | For |
| --- | --- |
| `socket_hand_r`, `socket_hand_l` | held items |
| `socket_back` | a slung weapon, a pack (between the shoulder blades, on the skin) |
| `socket_hip_l`, `socket_hip_r` | a holster, a pouch (on the skin at the side of the hip) |
| `socket_head` | a hat, a name plate (the crown) |
| `socket_camera` | a first-person or over-the-shoulder camera (between the eyes, on the face's surface) |

## IK targets {#ik-targets}

<!-- new section: the ik bones are how a clip of our own carries its contacts to a body of other proportions -->

`ik_foot_l/r` and `ik_hand_l/r` are children of `root` that rest exactly on `foot_l/r` and `hand_l/r` (place and
orientation). A clip of our own may key them, in the reference body's metres, as the place the foot or hand is meant
to be: an engine-side two-bone IK toward them then plants that limb on a body of any proportions, because their
position keys scale with `motion_scale` like the pelvis. The library's clips do not key them; a clip that does not key
them must not be played with that IK on.

## The root {#root}

<!-- new section: what the root may do decides whether a clip is in place or root motion -->

`root` rests at the origin, on the floor. The template moves the character itself, so clips are **in place**: `root`
stays at rest and `pelvis` carries the body's bob and sway only. A root-motion clip keys `root`'s position and yaw
(never pitch or roll) and is played with the `AnimationMixer`'s `root_motion_track` on `root`.

## Bodies {#bodies}

<!-- new section: the numbers of each shipped body, written by the build -->

The numbers below are written by the build (`build_mannequins.py --report`); a body's whole rest is in the
`rig_<body>.json` beside the models.

| Joint (left side, metres: x, y, z) | `male` | `female` | `chibi` |
| --- | --- | --- | --- |
| `motion_scale` | 1.0 | 1.0 | 0.545 |
| Top of the head (`socket_head`) | 1.800 | 1.745 | 1.250 |
| `pelvis` | 0, 0.917, -0.050 | 0, 0.917, -0.050 | 0, 0.500, -0.027 |
| `spine_03` | 0, 1.315, -0.005 | 0, 1.290, -0.005 | 0, 0.715, -0.003 |
| `Head` | 0, 1.569, 0.005 | 0, 1.526, 0.005 | 0, 0.860, 0.003 |
| `upperarm_l` | 0.190, 1.441, -0.045 | 0.160, 1.404, -0.045 | 0.135, 0.790, -0.020 |
| `lowerarm_l` | 0.470, 1.441, -0.048 | 0.422, 1.404, -0.048 | 0.290, 0.790, -0.023 |
| `hand_l` | 0.735, 1.441, -0.045 | 0.670, 1.404, -0.045 | 0.440, 0.790, -0.020 |
| `thigh_l` | 0.089, 0.932, 0.001 | 0.092, 0.932, 0.001 | 0.070, 0.508, 0.000 |
| `calf_l` | 0.089, 0.532, -0.001 | 0.092, 0.532, -0.001 | 0.070, 0.290, -0.001 |
| `foot_l` | 0.089, 0.104, -0.036 | 0.092, 0.104, -0.036 | 0.070, 0.057, -0.020 |
| `socket_hand_r` | -0.794, 1.409, -0.049 | -0.725, 1.375, -0.049 | -0.492, 0.755, -0.024 |
| Hand length (wrist to middle fingertip) | 0.195 | 0.181 | 0.172 |
| `socket_camera` | 0, 1.680, 0.120 | 0, 1.632, 0.115 | 0, 1.048, 0.192 |

The male's and the female's legs are the library's own, so clips plant their feet as they do the library's mannequins;
the chibi's leg is the same leg at 0.545 ([why the leg keeps its ratio](prototype-mannequins.md#bodies-and-looks)).

## Clips on other proportions {#proportions}

<!-- new section: moved from own-animation.md#proportions when that page reached 50 KB; what carries a clip over to a
body with other bone lengths or another skin, and what one clip file cannot do for two bodies -->

A clip stores each bone's turn in its parent, so on a body with other bone lengths the joints turn the same and
the ends of the limbs land elsewhere. What is done about each consequence:

| What changes on another body | What carries it over |
| --- | --- |
| Step length, and so the ground a gait covers | `clips.json` speed times the body's leg length over the reference's; the game plays the clip at ground speed over that |
| Pelvis height, bob and travel | `motion_scale` scales the position keys |
| A planted foot's place | the `ik_foot` targets and a two-bone solve in the game, on while the clip's weight curve says planted |
| A hand on a weapon or an obstacle | the socket and the hold solver, or the `ik_hand` targets |
| Limbs meeting the body (a big head, short arms, wide hips) | a per-body clearance pose, made by the body's build from the overlap check: an additive offset on the collarbones and upper arms that the tree always adds |
| Where the toes rest (the prototype bodies' curl 7.3 mm up off the floor, the Quaternius mannequins' lie on it) | nothing in one file: a foot on its ball is set down by the reference body's own skin, and the other shape hangs or sinks by the difference, which the checks allow that body (`toes_off_mm`) |
| Weight (a heavy or a tiny body) | the style file: a body type may take its own variant numbers through the same descriptions |

Group I clips need nothing but the first two rows. The checks run on every shipped body, the chibi included, so a
clip that only works on the reference fails its build.

- **Approach:** Solve a clip on the body the game wears (the toolkit's `REFERENCE` is `CharacterBodies.FEMALE`),
  run every check on each body the template holds, and set a foot that stands on its ball down by the lowest of its
  own blended skin. **Watch out for:** the crouch clips stayed solved on the Quaternius female after the template
  moved to the `form` bodies: the legs are the same length, yet a raised foot hung 5 to 6 mm over the floor (the
  `form` toes curl 7.3 mm up at rest) and one variant's hand was 30 mm in the `form` female's calf; solved on
  `form`, the Quaternius feet sink 5 to 7 mm instead, and the rig's `ik_` targets become tracks the Quaternius
  skeleton has no bone for.
  **Seen:** gdstudio #1160 (PR #1285), 2026-11-11 (fix: `REFERENCE` and `BODIES` in `build_own.py`, the rig's
  `tread`, `plan._state`, `checks.TOES_SAME`, the four-body Godot suite).

## What a clip made on this rig must keep {#clip-rules}

<!-- new section: the rules kit #1150's clips follow so that they carry over to every body -->

- Key rotations on the 65 library bones only; positions only on `pelvis`, `root` and the `ik_` targets, in the
  reference body's metres (hips at 0.9166 m); never a scale key.
- Export no position channel for any other bone, not even a constant one: a constant position is the body the clip
  was made on, and it stretches every other body ([the rest pose](#rest-pose)).
- Make the clip on the `male` body (or the library's mannequin: the legs and trunk are the same) and check it on the
  `female` and the `chibi` with the template's `tools/mannequin/measure_bodies.gd`: every track finds its bone, the
  feet stay on the floor, the limbs stay out of each other.
- A ground speed belongs to the reference body: a body moves at the clip's speed times its `motion_scale`.
- A contact that must hold on every body (a foot through a turn, two hands on one thing) is keyed on its `ik_` target
  as well as posed.
