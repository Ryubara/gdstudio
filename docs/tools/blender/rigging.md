# Rigging

<!-- new section: the rigging knowledge was split between cleaning kit rigs (rig-sharing.md) and character variants
(variants.md); nothing said how a new rig or a new skin is made and checked -->

How GDStudio rigs and skins a model in Blender: one shared skeleton per body type, so every clip plays on every
character, and weights that bend cleanly at the joints. Cleaning a third-party rig for a shared library is on
[Rig sharing](rig-sharing.md); bodies, clothes and parts on one rig are on [Variants](variants.md); the clips are on
[Animation](animation.md).

## One skeleton per body type {#shared-skeleton}

A game keeps one armature per body type and never changes its bones for one character: the Quaternius
`CharacterArmature` has 43 bones on the kit characters, and the zombie's 50 are the same 43 plus `Tongue1` to `Tongue5`
and `Eyelid.L` and `Eyelid.R` ([Rig sharing](rig-sharing.md)). A taller or broader character changes its armature
object's scale (left unapplied: the Brute at 1.18, the boss at 1.45) or pushes vertices along their normals by weight,
never the bones ([Variants](variants.md)). A clip made for the skeleton then plays on all of them, and Godot's
retargeting is not needed ([Godot rig sharing](../../engines/godot/rig-sharing.md)).

Name bones so Godot keeps them: a mesh that shares a bone's name makes Godot rename the bone (`Body` becomes `Body_2`),
so meshes are named `<part>_Mesh` ([Rig sharing](rig-sharing.md#what-broke)). Left and right are `.L` and `.R`, which
Blender's mirror tools and pose flipping read.

## Placing the joints {#joints}

A bone's head sits on the joint it turns about: the hip at the top of the thigh, the knee at the bend, the wrist where
the hand meets the forearm. Find the joints on the mesh (its loops, its bounds per part) and place the bones by script
from those numbers, so a rebuild places them again. Put a bone's tail on the next joint along its chain; a leaf bone (head,
hand, foot) points along the part. glTF stores no bone tails, so a rig read back from a glb has tails Blender guessed:
every zombie leg bone came back 0.518 long, and Blender's IK constraint then fails on it; solve two-bone chains by
script instead ([Gaits](gaits.md)).

Godot's bone frames are Blender's pose-bone frames, with positions mapped (x, y, z) to (x, -z, y)
([Rig sharing](rig-sharing.md#bone-axes-in-godot-and-clips-that-hold-a-weapon)).

## Weights {#weights}

Every vertex is weighted, to at most four bones (glTF's limit), with weights summing to 1. Away from a joint a vertex
belongs to its part's bone alone; across a joint the weight blends over a few centimetres, so the bend does not crease
or pinch. A rigid accessory (a cap, a pouch) is skinned 100% to one bone; two pieces that meet take the same weights
where they meet; skin borrowed from a body is copied by place, not by index ([Variants](variants.md#modular-parts)).
Weight both sides alike: a mirrored vertex has the mirrored weights.

Blender's automatic weights (parent with automatic weights) need a closed, welded mesh: a model imported from glTF is
split at every hard edge and UV seam, so weld it (merge by distance) before computing weights, or assign weights by
part from the geometry, which a script can repeat exactly.

## Sockets and hitboxes {#sockets}

An empty parented to a bone becomes a `BoneAttachment3D` in Godot: use it for a held item's grip, a muzzle or a hitbox
([Variants](variants.md), [Weapons](weapons.md#attachment-points)). A bone-parented mesh becomes a skinned mesh at
weight 1 with an Armature modifier on export.

## Checking a rig {#checks}

Pose the rig before handing it on: bend each elbow and knee 90 degrees and check that the hand or foot moves rigidly
with its parent bone and that nothing on the other side moves, then render the bent pose. A weight on the wrong bone
shows as a vertex left behind or dragged along, which a T-pose render hides.

## The rig eval {#eval}

The `rig-humanoid` eval ([Agent evals](../../studio/agent-evals.md)) rigs a blocky humanoid to a named 17-bone skeleton
and measures the joints, the weights (every vertex, at most four bones, its part's bone, mirrored) and two bends.
