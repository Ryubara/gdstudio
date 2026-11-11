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

BODIES_TABLE
