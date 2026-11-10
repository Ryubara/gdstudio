# Rifle

The template's assault rifle: Deadnight's M4A1-type carbine (a carry handle, a triangle front sight, a round ribbed
hand guard, Tan furniture), GDStudio's own script-built model, at real length with the Toon Shooter kit's chunky
cross-sections, on the same palette and material as the pistol. Licence: [LICENSE.md](LICENSE.md).

| File | What it is |
| --- | --- |
| `rifle.glb` | The near level (held, close up): 1,236 triangles, one material (`Weapons`), 0.816 x 0.386 x 0.097 m |
| `rifle_far.glb` | The far level: 420 triangles, the same parts with no chamfers, half the sides on round parts and the small parts left out, every node at the near level's place |
| `rifle.tscn` | Both levels in one scene: `Near` drawn to 10 m, `Far` from 10 m (each mesh's Visibility Range, 0.5 m margin) |
| `rifle_weapons_palette.png`, `rifle_far_weapons_palette.png` | The 32 x 32 palette Godot extracts from each glb (lossless, no mipmaps, Detect 3D off) |
| `build_rifle.py` | Rebuilds both glbs with the pinned Blender (`blender -b --factory-startup -P build_rifle.py`) |

Godot's own levels of detail are off for both files (`meshes/generate_lods=false`): made from the kitbashed near level
they dropped the hand guard and pieces of the receiver at 15 to 30 m, where the far level keeps its outline. Show a
rifle that can be far from the camera (a pickup, another player's) through `rifle.tscn`, and change the switch on the
six meshes' Visibility Range in its inspector.

## Nodes

The glb's root holds the mesh `Rifle` (the receivers, barrel, hand guard, carry handle, grip and stock), origin at the
grip. In Godot the muzzle points along -X, up is +Y and the gun's left is +Z (the kit's weapon axes).

| Node | Where (m, in `Rifle`) | Use |
| --- | --- | --- |
| `Magazine` | (-0.121, 0.055, 0) | the magazine, its own mesh, origin at the well's mouth: drop it along its -Y for a reload |
| `Bolt` | (0.034, 0.168, 0) | the charging handle, origin at its root: pull it along +X (Deadnight uses 0.06 m) |
| `Muzzle` | (-0.506, 0.130, 0) | the flash hider's open end; its -Z points out of the barrel (flash, shot) |
| `Eject` | (-0.066, 0.135, -0.036) | the ejection port on the right; its -Z points out of the port |
| `Grip` | (0, 0, 0) | the right hand's handle; +Y up the handle (raked back 16 degrees), -Z along the fingers (the barrel) |
| `Trigger` | (-0.054, 0.047, 0) | the trigger's front face; -Z is the press |
| `Support` | (-0.246, 0.115, 0) | the left hand's handle, under the hand guard; +Y toward the muzzle, -Z the way the left fingers point (round the guard to the gun's right, and up) |
| `Butt` | (0.307, 0.095, 0) | the butt pad's rear face, where the stock meets the shoulder |

`Support` is 4 cm further back than on Deadnight's model: the female mannequin's arm is 0.49 m from shoulder to wrist,
and with the support where Deadnight put it the left hand stopped 4 cm short of it even with the chest turned 30
degrees (the hold study below).

## Holding it (a proposal for the weapon work)

The Universal Animation Library has pistol clips and no rifle clips, so the rifle needs a hold made from what the
template has. `tools/capture/rifle_hold_study.tscn` builds five on the female mannequin and measures each hand
against its target in the final pose (headless, it prints a `HOLD` line a figure; with a window and `HOLD_OUT` it saves
the renders):

| Hold | How it is made | Measured |
| --- | --- | --- |
| A | `Pistol_Aim_Neutral`, the rifle seated in the right fist the way the pistol is (its `Grip` on the pistol's) | the butt hangs in front of the face and the left hand cups the air under the receiver |
| B | A, and a two-bone IK pulls the left hand to `Support` | the hand stops 22.5 cm short: its target is 0.72 m from the shoulder, the arm 0.49 m |
| C | shouldered: the rifle placed in the model's space with `Butt` in the right shoulder's pocket (-0.13, 1.39, 0.06) and the barrel along the facing; both hands brought to `Grip` and `Support` by IK; the chest turned 30 degrees (left shoulder forward); over `Idle` | both hands on (0.1 cm and 0 cm), the barrel straight ahead |
| D | C turned 30 degrees up about the pocket | both hands on (0.7 cm and 0 cm) |
| E | low ready: the butt at (-0.12, 1.33, 0.06), the muzzle 35 degrees down and 20 across the body | both hands on |

Each hand's target is the right fist's place on the pistol's grip (from the pistol's seat) moved onto the rifle's
`Grip`, and mirrored onto `Support` for the left hand: the mannequin's rig is an exact mirror (each left bone's rest is
its right one's reflected across the body's middle plane, to 1e-6 m and 0.04 degrees). The male mannequin reaches
every target of C, D and E with the same placements.

**Proposed:** C for aiming and firing (D is the same hold at another pitch: turn the rifle about the shoulder's pocket
by the camera's pitch), E when not aiming, with the legs on the locomotion clips. All of it is engine nodes a person can
tune in the inspector, on the mannequin's `Skeleton3D`, in this order:

1. a chest turn of -30 degrees over `spine_01` to `spine_03` (the study's `tools/capture/spine_turn.gd`, a few lines of
   `SkeletonModifier3D`);
2. a `TwoBoneIK3D` per arm (`upperarm_*`, `lowerarm_*`, `hand_*`) with a `Marker3D` target on the rifle (the hand's
   place, from `Grip` and `Support` as above) and a pole marker for the elbow (out and down);
3. a `CopyTransformModifier3D` per hand that copies the target's rotation onto `hand_*`.

The rifle hangs on a node under the player's `Model` slot (the shoulder's pocket), so a clip's sway of the arms does not
move it, and a shot's recoil is a kick of that node back and up that the hands follow. A reload drops `Magazine` along
its -Y and brings the left hand's target to the belt and back, with no clip. Over 40 figures, the two IKs, the two hand
turns and the chest turn added 0.3 ms a frame on the desktop (2.1 to 2.4 ms of process time without them, 2.5 to 2.6 ms
with), about 8 microseconds a character; it is a cosmetic pose, computed on each machine from the aim pitch the game
already has, and never sent over the network.

What it does not do yet: the fingers keep the clip's fist (the left hand's fingers go into the 8 cm hand guard; a
fingers pose for the support grip, or a solve like Deadnight's grips, is the next step), and the head stays beside the
stock rather than on it. Rifle clips made in Blender on the universal rig (an idle, an aim with up and down, a shot, a
reload) would give a better body motion than a chest turn, at the cost of animating them; the IK hold above is the
start that the weapon work can ship with, and a clip can replace any part of it later.
